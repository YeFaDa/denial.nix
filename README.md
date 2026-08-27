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

### Prebuilt release packages

1. Bump the release version in `pkgs/version.nix`; all three packages read
   it, so they always move together.
2. Update the three release hashes (`denial` `src`, engine `src`, shell `src`),
   e.g. with `nix-prefetch-url` / `nix flake prefetch`, or use fake hashes and
   let `nix build` print the expected values.
3. Re-vendor `Cargo.lock` from the new tag:
   `curl -o pkgs/denial/Cargo.lock https://raw.githubusercontent.com/denialwm/denial/v<version>/compositor/Cargo.lock`.

### Source builds

Source packages use one coupled toolchain. The Flutter fork, Skia fork, Dart
checkout, Flutter tools snapshot, local engine, and Dart shell AOT output must
come from compatible revisions. Do not update only one of these inputs.

1. Read the new release's `prebuilt/flutter-engine/SOURCE_LOCK.json` and update
   `pkgs/denial-flutter-engine/gclient-deps.json` from its complete `DEPS`
   graph. Keep every fetched dependency pinned by revision and hash; do not use
   `gclient sync` or a developer checkout inside a Nix build.
2. Update the independent `nixpkgs-dart` input in `flake.nix` and `flake.lock`
   to a nixpkgs revision whose `dart-bin` exactly matches the Dart revision
   required by the new Flutter fork. On Linux, use `dart-bin`, not `dart`:
   historical nixpkgs may define `dart` as the source-built package.
3. Update `pkgs/denial-flutter-engine/flutter-tools-pubspec.lock.json` from
   `packages/flutter_tools/pubspec.yaml` using the matching Dart SDK. The lock
   must be the `flutter_tools` package lock, not Flutter's root workspace lock.
4. Update `pkgs/denial-flutter-shell/pubspec.lock.json` from `dart_shell` with
   the matching Flutter/Dart tools. Preserve the SDK package entries and all
   hosted package hashes so `pub2nix` can construct the dependency closure.
5. Update the fixed resource inputs in
   `pkgs/denial-flutter-shell/source.nix` when the new Flutter revision changes
   `material_fonts.version` or `gradle_wrapper.version`. Both archives need
   fixed hashes. Engine-only resources must come from the matching local engine
   output, not from a different Flutter generation.
6. Keep SDK hash verification enabled. Nix source projections must not create
   synthetic Git commits. Instead, inject the locked Dart revision through
   `third_party/dart/tools/GIT_REVISION` and pass the locked Flutter, Skia, and
   Dart revisions to the GN source projection. VM, `platform_strong.dill`,
   `gen_snapshot`, and the AOT kernel must share the same first ten bytes of
   the Dart SDK revision.
7. Run the static check before any long build:
   `nix flake check --all-systems --no-build --no-write-lock-file`.
8. Build the source package only after the inputs and checks pass:
   `nix build .#denial-flutter-shell-source --no-link --fallback`.
   This builds the engine first, then the shell AOT snapshot. Verify that the
   result contains `libapp.so`, `flutter_assets`, and the matching local engine
   generation.
9. Build `.#denial-source` only after the engine and shell source outputs pass.
   Build `.#denial` separately to confirm the default prebuilt x86-64 path was
   not regressed.

Never mix a source shell with a prebuilt engine, or a source engine with a
prebuilt shell. If the Dart SDK revision changes, rebuild the engine before
building the shell; reusing an older `platform_strong.dill` or `gen_snapshot`
can produce an SDK-hash failure during AOT compilation.
