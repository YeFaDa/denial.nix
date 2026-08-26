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

    package = lib.mkPackageOption pkgs "denial" { };

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
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ] ++ cfg.extraRuntimePackages;

    # Lets display managers discover the packaged wayland-sessions entry.
    services.displayManager.sessionPackages = [ cfg.package ];

    # deniald starts and stops denial-session.target through the systemd
    # user manager on its own; installing the packaged unit is enough.
    systemd.packages = [ cfg.package ];

    # The lock screen authenticates through PAM using the service named by
    # DENIAL_PAM_SERVICE (defaults to "login" upstream).
    security.pam.services.denial = { };
    environment.sessionVariables.DENIAL_PAM_SERVICE = "denial";

    hardware.graphics.enable = lib.mkDefault true;
    security.rtkit.enable = lib.mkDefault true;

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
      # Mirrors the upstream denial-portals.conf: GTK handles the generic
      # interfaces, Denial implements the Settings interface itself since
      # 0.2.16, and the wlroots backend consumes Denial's screencopy
      # protocol for ScreenCast and Screenshot.
      config.denial = {
        default = [ "gtk" ];
        "org.freedesktop.impl.portal.Settings" = [
          "denial"
          "gtk"
        ];
        "org.freedesktop.impl.portal.ScreenCast" = "wlr";
        "org.freedesktop.impl.portal.Screenshot" = "wlr";
      };
    };

    # Denial does not implement zwlr-layer-shell, so xdg-desktop-portal-wlr
    # must use the Zenity chooser shipped in the package instead of slurp.
    environment.etc."xdg/xdg-desktop-portal-wlr/Denial".source =
      "${cfg.package}/share/xdg-desktop-portal-wlr/Denial";
  };
}
