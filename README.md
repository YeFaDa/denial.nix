# Denial — nixpkgs packaging

Nix packaging for [Denial](https://github.com/denialwm/denial), a Flutter-native
Wayland compositor, written in the style of the niri package in nixpkgs.

## What is built from source, what is not

| Component | Package | Default x86-64 mode | Source mode |
| --- | --- | --- | --- |
| `deniald`, `denialctl`, `denial-portal`, session files | `denial` | Rust source | Rust source |
| `libflutter_engine.so`, `icudtl.dat` | `denial-flutter-engine` | upstream release artifact | locked Flutter/Skia sources with GN/Ninja |
| `libapp.so`, `flutter_assets` | `denial-flutter-shell` | upstream release artifact | `buildFlutterApplication` with the matching local engine |

The flake's default `denial` output keeps the prebuilt x86-64 Flutter runtime.
`denial-source` builds the engine and Dart shell from source and is available
on both `x86_64-linux` and `aarch64-linux`. The latter has no prebuilt output.

The source engine checkout is assembled with nixpkgs' `gclient2nix` format from
the pinned Flutter `DEPS` graph. The build does not run `gclient sync`, access a
developer checkout, or use a mutable cache.

The Flutter side cannot be built with the stock nixpkgs engine: Denial pins a
fork of Flutter 3.44.7 and Skia, and the AOT snapshot must use that matching
engine. The source derivations therefore use the forked engine output rather
than `flutterPackages.v3_44`'s normal engine artifacts.

The four runtime bundle members remain coupled to one engine/shell pair. Mixing
the source shell with a release engine, or vice versa, is unsupported.

Only native Linux builds are supported for source mode. Cross-compiling the
Flutter engine is intentionally not enabled yet.

## Existing release artifacts

The prebuilt packages remain available for the x86-64 release path:

- `denial-flutter-engine`: prebuilt engine and ICU data
- `denial-flutter-shell`: prebuilt AOT snapshot and assets
 
The source lock remains at `prebuilt/flutter-engine/SOURCE_LOCK.json` in the
upstream repository. The checked-in `pkgs/denial-flutter-engine/gclient-deps.json`
contains its fixed dependency closure.

## Layout

```
flake.nix                       # packages, overlay, NixOS module
nix/module.nix                  # programs.denial NixOS module
pkgs/version.nix                # release version shared by all three packages
pkgs/denial/package.nix         # main package (compositor + session + bundle assembly)
pkgs/denial/Cargo.lock          # vendored from the release tag
pkgs/denial-flutter-engine/package.nix   # prebuilt engine + ICU data
pkgs/denial-flutter-shell/package.nix    # prebuilt AOT shell + assets
```

The main package assembles the runtime layout the upstream session launcher
expects (`$out/lib/denial/flutter/{lib,data}`); the four bundle members are
symlinks into the two prebuilt packages, so the packaged `denial-session`
script finds the bundle, the engine and the binaries relative to its own
prefix without any patching beyond the paths below:

- `/etc/denial/outputs.conf` → `$out/share/denial/outputs.conf` (per-user copy
  template; the machine-level `/etc/denial/session.conf` is still sourced when
  it exists and can be provided through `environment.etc`)
- desktop entry `Exec`/`TryExec` → `$out/bin/denial-session`

`deniald` dlopens `libEGL.so.1`, `libwayland-server.so`, `libpulse.so.0`,
`libpam.so.0` and `libddcutil.so.5`; those libraries are buildInputs so the
generated RUNPATH resolves them (same trick as niri, plus explicit force
linking of EGL/wayland-server). The prebuilt engine gets a patched RUNPATH to
find `libfontconfig`.

## Usage

Build (compositor from source + prebuilt Flutter artifacts):

```console
$ nix build github:YeFaDa/denial.nix#denial
```

Or install to your user profile and launch `denial-session` from a TTY:

```console
$ nix profile install github:YeFaDa/denial.nix#denial
```

NixOS:

```nix
{
  inputs.denial.url = "github:YeFaDa/denial.nix";

  outputs = { self, nixpkgs, denial }: {
    nixosConfigurations.host = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        denial.nixosModules.denial
        {
          nixpkgs.overlays = [ denial.overlays.default ];
          programs.denial.enable = true;
        }
      ];
    };
  };
}
```

The module installs the session, registers it with display managers
(`services.displayManager.sessionPackages`), makes `denial-session.target`
available to the systemd user manager (deniald starts it via D-Bus),
registers a PAM service for the lock screen, and wires up
xdg-desktop-portal (GTK + wlroots) matching the upstream portal
configuration.

Optional runtime tools the shell can use — matching upstream's optional
dependencies:

```nix
programs.denial.extraRuntimePackages = with pkgs; [
  networkmanager      # network controls (nmcli)
  upower              # battery status
  power-profiles-daemon
];
```

Notes:

- Xwayland, zenity and systemd are already on the session PATH by default.
- CJK fallback fonts (upstream ships `adobe-source-han-sans-cn-fonts`) are a
  fontconfig concern; add a CJK font to `fonts.packages` if needed.
- The `denial-ui-development` live-reload package is not packaged.
- The NixOS module enables hardware graphics support, rtkit, the graphical
  desktop stack, Polkit, dconf, Xwayland and xdg-desktop-portal by default
  (matching the base integration of the nixpkgs niri module); every setting
  is a `mkDefault` and can still be overridden in the host configuration.

## Updating

1. Bump the release version in `pkgs/version.nix`; all three packages read
   it, so they always move together.
2. Update the three hashes (`denial` `src`, engine `src`, shell `src`), e.g.
   with `nix-prefetch-url` / `nix flake prefetch` — or replace them with fake
   values and let `nix build` print the correct ones.
3. Re-vendor `Cargo.lock` from the new tag:
   `curl -o pkgs/denial/Cargo.lock https://raw.githubusercontent.com/denialwm/denial/v<version>/compositor/Cargo.lock`.
