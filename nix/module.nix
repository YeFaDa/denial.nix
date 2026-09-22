{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.denial;
in
{
  options.programs.denial = {
    enable = lib.mkEnableOption "Denial, a Flutter-native Wayland compositor";

    # One switch for where the Flutter components come from. It moves the
    # default of both packages below so they cannot disagree: a source-built
    # compositor paired with a prebuilt toolchain (or the other way round) would
    # mix two engine builds that were never meant to run against each other.
    #
    # It only sets defaults. Defining `package` or `uiDevelopment.package`
    # explicitly still wins, so unusual combinations remain possible.
    useSource = lib.mkOption {
      type = lib.types.bool;
      default = false;
      example = true;
      description = ''
        Whether to build the Flutter components Denial bundles (the engine,
        the shell and the settings app) from source instead of taking
        upstream's prebuilt artifacts.

        Enabling this changes the default of {option}`package` and
        {option}`uiDevelopment.package` to their `-source` counterparts.
        The Rust side of Denial is built from source either way.

        Required on aarch64: upstream publishes prebuilt artifacts for
        x86_64 only, so the prebuilt packages refuse to evaluate there.
      '';
    };

    package = lib.mkPackageOption pkgs "denial" {
      default = if cfg.useSource then [ "denial-source" ] else [ "denial" ];
      extraDescription = ''
        Defaults to `pkgs."denial-source"` when
        {option}`useSource` is enabled.
      '';
    };

    # Deliberately decoupled from the compositor: nothing pulls the toolchain
    # in on its own, and enabling Denial does not install it. It is a
    # development dependency for people editing Denial's UI, not something a
    # session needs to start.
    uiDevelopment = {
      enable = lib.mkEnableOption "the Denial UI development toolchain";

      package = lib.mkPackageOption pkgs "denial-ui-development" {
        # Keyed off the compositor actually in use, not off `useSource`, so a
        # hand-written `package` still gets a toolchain built the same way.
        # `or false` covers packages that do not carry the marker (a local
        # override, say) by falling back to upstream's default.
        default =
          if cfg.package.flutterFromSource or false then
            [ "denial-ui-development-source" ]
          else
            [ "denial-ui-development" ];
        extraDescription = ''
          Installed only when {option}`enable` is set. Follows
          {option}`package`: a source-built compositor gets
          `pkgs."denial-ui-development-source"`, a prebuilt one gets the
          prebuilt toolchain.
        '';
      };
    };

    # Denial's Settings app controls external monitor brightness over DDC/CI,
    # which talks to the display itself across the I2C bus. That needs access
    # to /dev/i2c-*, so the compositor's users have to be in the `i2c` group.
    #
    # Default matches upstream's module. Turning it off leaves the brightness
    # control in Settings failing on external displays; internal panels are
    # driven through the backlight interface instead and are unaffected.
    ddc.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to grant I2C device access for Denial's DDC monitor controls.
      '';
    };

    # Privileged desktop operations -- mounting a drive, connecting to a
    # network, changing the clock -- ask Polkit for permission rather than
    # running through sudo. Polkit only decides; the agent is the password
    # dialog the user actually sees. Without one those requests fail silently.
    #
    # Denial ships no agent of its own, so one is started as a user service
    # alongside the session. Disable this when another desktop component in
    # the same session already provides one, or two dialogs race each other.
    polkitAgent = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to run a PolicyKit authentication agent in Denial sessions.
        '';
      };
      command = lib.mkOption {
        type = lib.types.str;
        default = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
        defaultText = lib.literalExpression ''
          "''${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1"
        '';
        description = "Absolute command used for the PolicyKit authentication agent.";
      };
    };

    # Tools the shell and session launch by name, e.g. nmcli, powerprofilesctl
    # or lact. They are only put on the session PATH, matching the optional
    # dependencies of the upstream packages.
    extraRuntimePackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      example = lib.literalExpression ''
        with pkgs; [
          networkmanager
          upower
          power-profiles-daemon
        ]
      '';
      description = "Extra packages to expose on the Denial session PATH.";
    };

    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional session user to add to video/input/render/seat groups. Leave null to manage groups manually.";
    };

    extraSessionConf = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = { DENIAL_RUST_LOG = "deniald=debug"; };
      description = "Extra KEY=VALUE entries for /etc/denial/session.conf.";
    };

    # Safe to set from the system scope even though the compositor writes the
    # resolved file: the launcher treats declarative contents as read-only and
    # copies them to $XDG_STATE_HOME/denial/outputs.conf, where display changes
    # land. A user's live layout therefore survives until these contents change.
    outputsConf = lib.mkOption {
      type = lib.types.nullOr lib.types.lines;
      default = null;
      example = lib.literalMD ''
        ```
        eDP-1=0,0
        primary=eDP-1
        scale=eDP-1,1.5
        ```
      '';
      description = ''
        Contents of {file}`/etc/denial/outputs.conf`, in the format the
        packaged reference documents.

        Live changes made from Settings are written to
        {file}`$XDG_STATE_HOME/denial/outputs.conf` and persist while these
        contents stay unchanged; editing them and rebuilding replaces the
        live file.

        Left null, no {file}`/etc` file is written and the launcher reads the
        commented-out reference inside the Denial store path, which asks for
        automatic output placement.
      '';
    };
  };
  config = lib.mkIf cfg.enable (let
    sessionConf = lib.concatStringsSep "\n" (lib.flatten [
      "# Generated by NixOS. Sourced by denial-session at session start."
      #
      # `export`, not a plain assignment: denial-session sources this file
      # but only forwards exported variables to the compositor and its
      # children, which is where the shell reads them from.
      #
      # The paths the compositor package ships itself -- the compositor, the
      # control client and the Settings binary -- are not repeated here: the
      # session launcher derives them from its own location and exports
      # DENIAL_COMPOSITOR_BINARY, DENIAL_CONTROL_TOOL and
      # DENIAL_SETTINGS_BINARY, and an entry here would override that.
      #
      # Listed before extraSessionConf so an explicit entry there wins.
      #
      # The lock screen authenticates through this PAM service; the module
      # defines it below.
      "export DENIAL_PAM_SERVICE=denial"
      # The shell's editable-UI feature runs the UI development toolchain by
      # absolute path. Only set when that toolchain is actually installed.
      (lib.optional cfg.uiDevelopment.enable
        "export DENIAL_DEVELOPMENT_TOOL=${cfg.uiDevelopment.package}/bin/denial-ui")
      (lib.mapAttrsToList (n: v: "export ${n}=${v}") cfg.extraSessionConf)
    ]);

  in {
    environment.systemPackages =
      [ cfg.package ]
      ++ lib.optional cfg.uiDevelopment.enable cfg.uiDevelopment.package
      ++ cfg.extraRuntimePackages;

    # Lets display managers discover the packaged wayland-sessions entry.
    services.displayManager.sessionPackages = [ cfg.package ];

    # deniald starts and stops denial-session.target through the systemd
    # user manager on its own; installing the packaged unit is enough.
    systemd.packages = [ cfg.package ];

    # Tied to the session target rather than the graphical session: the agent
    # has to be up before anything in the session asks for authorization, and
    # taken down with it so a second login does not leave two behind.
    systemd.user.services.denial-polkit-agent = lib.mkIf cfg.polkitAgent.enable {
      description = "PolicyKit authentication agent for Denial";
      documentation = [ "https://github.com/denialwm/denial" ];
      wantedBy = [ "denial-session.target" ];
      partOf = [ "denial-session.target" ];
      after = [ "denial-session.target" ];
      serviceConfig = {
        ExecStart = cfg.polkitAgent.command;
        Restart = "on-failure";
        RestartSec = "250ms";
      };
    };

    # systemd runs this before entering a sleep state, as root, and applies
    # the mode the compositor published for the active session. systemd
    # searches /etc/systemd/system-sleep along with the vendor directories.
    # The lock screen authenticates through PAM using the service named by
    # DENIAL_PAM_SERVICE (defaults to "login" upstream).
    security.pam.services.denial = { };

    # Every /etc entry in one definition: two assignments to this option are a
    # conflict, and the attributes have to be merged rather than split.
    environment.etc = {
      "systemd/system-sleep/denial-suspend-mode".source =
        "${cfg.package}/lib/systemd/system-sleep/denial-suspend-mode";

      "denial/session.conf".text = sessionConf + "\n";
    }
    // lib.optionalAttrs (cfg.outputsConf != null) {
      # Added only when the option carries text. An empty entry instead of an
      # absent one would make NixOS write a zero-byte /etc/denial/outputs.conf,
      # which the launcher would treat as a real source and use in place of the
      # packaged reference -- and an empty outputs.conf is not the same as the
      # commented-out one.
      "denial/outputs.conf".text = cfg.outputsConf;
    };

    users.groups.video = { };
    users.groups.input = { };
    users.groups.render = { };
    users.groups.seat = { };
    users.users = lib.optionalAttrs (cfg.user != null) {
      ${cfg.user} = { extraGroups = [ "video" "input" "render" "seat" ]; };
    };
    hardware.graphics.enable = lib.mkDefault true;
    security.rtkit.enable = lib.mkDefault true;

    # mkDefault, not a plain assignment: a host that already manages I2C for
    # another reason keeps its own setting. The module only supplies the
    # default Denial's DDC support needs.
    hardware.i2c.enable = lib.mkDefault cfg.ddc.enable;

    # Base Wayland session integration, same defaults the niri module gets
    # from wayland-session.nix: Polkit for power/network portals, dconf for
    # the GTK portal, Xwayland for the X clients the session launcher puts
    # on PATH.
    services.graphical-desktop.enable = lib.mkDefault true;
    security.polkit.enable = lib.mkDefault true;
    programs.dconf.enable = lib.mkDefault true;
    programs.xwayland.enable = lib.mkDefault true;

    xdg.portal = {
      enable = lib.mkDefault true;
      extraPortals = with pkgs; [
        xdg-desktop-portal-gtk
        xdg-desktop-portal-wlr
      ];
      # The package ships upstream's routing as
      # share/xdg-desktop-portal/denial-portals.conf: GTK for the generic
      # interfaces, Denial for the Settings interface it implements itself
      # since 0.2.16, and the wlroots backend for ScreenCast/Screenshot,
      # which consumes Denial's screencopy protocol. Registering the package
      # here exposes that file through XDG_DATA_DIRS, the same way GNOME and
      # KDE ship their own -portals.conf.
      #
      # Deliberately not xdg.portal.config: that would land in
      # /etc/xdg/xdg-desktop-portal/denial-portals.conf, and portals.conf(5)
      # reads only the first file found while ranking every config directory
      # above every data directory. Such a copy would shadow the packaged one
      # and drift silently whenever upstream changes its routing.
      configPackages = [ cfg.package ];
    };
  });
}
