# Denial — nixpkgs packaging

Nix packaging for [Denial](https://github.com/denialwm/denial), a Flutter-native
Wayland compositor, written in the style of the niri package in nixpkgs.

## What is built from source, what is not

| Component | Package | Default x86-64 mode | Source mode |
| --- | --- | --- | --- |
| `deniald`, `denialctl`, `denial-portal`, session files | `denial` | Rust source | Rust source |
| `libflutter_engine.so`, `icudtl.dat` | `denial-flutter-engine` | upstream release artifact | locked Flutter/Skia sources with GN/Ninja |
| `libapp.so`, `flutter_assets` | `denial-flutter-shell` | upstream release artifact | `buildFlutterApplication` with the matching local engine |

The default `denial` package always builds `deniald`, `denialctl`, and
`denial-portal` from Rust source. Its `useSource` option selects only the
Flutter runtime pair:

```nix
pkgs.denial.override { useSource = true; }
```

With `useSource = false` (the default), Flutter engine and shell artifacts are
prebuilt. With `useSource = true`, both are built from the locked Flutter/Skia
source inputs. The package does not infer this choice from the host architecture.
The separate engine and shell source outputs remain available for inspection.

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

Prebuilt artifacts are only the Flutter runtime pair:

- `denial-flutter-engine`: prebuilt engine and ICU data (`package.nix`)
- `denial-flutter-shell`: prebuilt AOT snapshot and assets (`package.nix`)
- `denial-flutter-engine/source.nix` / `denial-flutter-shell/source.nix`: source
  builds from the locked Flutter/Skia checkout

The `denial` Rust package itself is always built from source; only its Flutter
runtime inputs are selectable via `useSource`.

The source lock remains at `prebuilt/flutter-engine/SOURCE_LOCK.json` in the
upstream repository. The checked-in `pkgs/denial-flutter-engine/gclient-deps.json`
contains its fixed dependency closure. Its revisions are exposed only through
`pkgs/denial-flutter-engine/revisions.nix`; do not duplicate them.

## Layout

```
flake.nix                       # packages, overlay, NixOS module
nix/module.nix                  # programs.denial NixOS module
pkgs/version.nix                # release version shared by all three packages
pkgs/denial/package.nix         # main package (Rust source + useSource switch)
pkgs/denial/Cargo.lock          # vendored from the release tag
pkgs/denial-flutter-engine/package.nix   # prebuilt engine + ICU data
pkgs/denial-flutter-engine/source.nix    # source engine (GN/Ninja)
pkgs/denial-flutter-engine/revisions.nix # Flutter/Skia/Dart revisions from gclient-deps.json
pkgs/denial-flutter-shell/package.nix    # prebuilt AOT shell + assets
pkgs/denial-flutter-shell/source.nix     # source AOT shell (flutter assemble)
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

To select source Flutter artifacts, override the single package option:

```console
$ nix build --impure --expr '
  let f = builtins.getFlake (toString ./.);
  in f.packages.x86_64-linux.denial.override { useSource = true; }
'
$ nix profile install --impure --expr '
  let f = builtins.getFlake (toString ./.);
  in f.packages.x86_64-linux.denial.override { useSource = true; }
'
```

The package name remains `denial`; `deniald`, `denialctl`, and
`denial-portal` are always built from Rust source. `useSource` controls only
the Flutter engine and shell pair. The package does not infer the choice from
the host architecture.

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
- `denial-settings` and `denial-ui-development` are optional x86-64 packages.
  They are not runtime dependencies of `denial`; install them explicitly when
  needed.
- The NixOS module enables hardware graphics support, rtkit, the graphical
  desktop stack, Polkit, dconf, Xwayland and xdg-desktop-portal by default
  (matching the base integration of the nixpkgs niri module); every setting
  is a `mkDefault` and can still be overridden in the host configuration.

## Updating

`denial-update-check` checks the latest non-draft Denial release. It reports
what must change but never edits the working tree or commits changes.

### Prebuilt packages

1. Run:
   `nix run .#denial-update-check -- --json`.
2. Set the version in `pkgs/version.nix` to the reported release version.
3. Update the matching entries in `pkgs/prebuilt-hashes.nix`. The `denial`
   artifact is used by the prebuilt shell and the optional settings package;
   `engine` and `uiDevelopment` are separate artifacts.
4. Fetch `compositor/Cargo.lock` from the same upstream tag into
   `pkgs/denial/Cargo.lock`.

### Source packages

5. Read the new release's `prebuilt/flutter-engine/SOURCE_LOCK.json` and
   regenerate `pkgs/denial-flutter-engine/gclient-deps.json` with the complete
   `DEPS` graph using `gclient2nix`. Every dependency must remain pinned by
   revision and hash. Never run `gclient sync` or use a mutable developer
   checkout in a Nix build.
6. Select an independent `nixpkgs` revision whose `dart-bin` matches the Dart
   revision in the lock graph, then update `nixpkgs-dart` in `flake.nix` and
   `flake.lock` with `nix flake lock --update-input nixpkgs-dart`. On Linux use
   `dart-bin`, not necessarily `dart`.
7. Regenerate `flutter-tools-pubspec.lock.json` from
   `packages/flutter_tools/pubspec.yaml` and `pubspec.lock.json` from
   `dart_shell/pubspec.yaml`, using the matching Flutter/Dart toolchain. The
   first is a package lock, not Flutter's root workspace lock.
8. Read the matching fork's `flutter/bin/internal/material_fonts.version` and
   `gradle_wrapper.version` and update the two attributes in
   `pkgs/denial-flutter-engine/revisions.nix`. The `devtools_shared` archive
   URL and hash are derived directly from the Flutter tools lock by
   `source.nix`.
9. Keep SDK hash verification enabled. Do not create synthetic Git commits;
   the source projection injects the locked Dart revision through
   `third_party/dart/tools/GIT_REVISION` and passes the locked Flutter, Skia,
   and Dart revisions to GN. VM, `platform_strong.dill`, `gen_snapshot`, and
   the AOT kernel must share the same first ten bytes of the Dart revision.

### Verification and release

10. Run the static check:
    `nix flake check --all-systems --no-build --no-write-lock-file`.
11. Verify the default package (Rust source + prebuilt Flutter runtime):
    `nix build .#denial --no-link --fallback`.
12. Verify the complete source variant explicitly:
    `NIX_BUILD_CORES=16 nix build --impure --expr 'let f = builtins.getFlake (toString ./.); in f.packages.x86_64-linux.denial-source' --no-link --fallback`.
    `denial-source` is a package alias for `denial.override { useSource = true; }`;
    the Rust compositor is source-built in both variants.
13. Verify `deniald --version`, `libflutter_engine.so`, `libapp.so`, and
    `flutter_assets`. Review the diff and commit all pins together.

The daily GitHub workflow runs `denial-update-check --json`, prints the result,
and validates the current pins. It is intentionally a detector/validator; it
does not silently rewrite or commit release pins. A maintainer must apply and
review the reported changes before merging them.

Never mix a source shell with a prebuilt engine, or a source engine with a
prebuilt shell. If the Dart SDK revision changes, rebuild the engine before
building the shell; reusing an older `platform_strong.dill` or `gen_snapshot`
can produce an SDK-hash failure during AOT compilation.
