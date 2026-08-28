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

Source outputs share one coupled toolchain. The Flutter fork, Skia fork, Dart
SDK, Flutter tools snapshot, local engine, and Dart shell AOT output must come
from compatible revisions. Do not update only one of these inputs.

1. Read the new release's `prebuilt/flutter-engine/SOURCE_LOCK.json` and
   regenerate `pkgs/denial-flutter-engine/gclient-deps.json` from its complete
   `DEPS` graph (e.g. via `gclient2nix`). Keep every fetched dependency pinned
   by revision and hash. The Nix build must not run `gclient sync`, access a
   developer checkout, or use a mutable cache.
2. Keep `pkgs/denial-flutter-engine/revisions.nix` as the only revision
   interface. It derives the Flutter, Dart, and Skia revisions from
   `gclient-deps.json`. Its two additional attributes
   `materialFontsVersion` and `gradleWrapperVersion` are pinned from the
   locked Flutter fork's `bin/internal/material_fonts.version` and
   `bin/internal/gradle_wrapper.version`; update them together with the
   Flutter revision. Do not duplicate these four revisions/hashes in
   `source.nix`, `flutter-tools.nix`, `source.nix` for the shell, or
   `flake.nix` — `flake.nix` derives the `materialFonts` / `gradleWrapper`
   `fetchurl`s from `revisions.nix`.
3. Update the independent `nixpkgs-dart` input in `flake.nix` and `flake.lock`
   to a nixpkgs revision whose `dart-bin` exactly matches the Dart SDK revision
   required by the new Flutter fork. For the current historical package,
   update it with:
   `nix flake lock --update-input nixpkgs-dart`.
   On Linux use `dart-bin`, not `dart`: historical nixpkgs may define `dart` as
   the source-built package. Verify the selected package version and revision
   before building.
4. Update `pkgs/denial-flutter-engine/flutter-tools-pubspec.lock.json` from
   `packages/flutter_tools/pubspec.yaml` using the matching Dart SDK. The lock
   must be the `flutter_tools` package lock, not Flutter's root workspace lock.
5. Update `pkgs/denial-flutter-shell/pubspec.lock.json` from `dart_shell` with
   the matching Flutter/Dart tools. Preserve SDK package entries and all hosted
   package hashes so `pub2nix` can construct the dependency closure. The shell's
   fixed Flutter resources (`material_fonts`, `gradle_wrapper`) are now derived
   as separate `fetchurl`s in the overlay from `revisions.nix`; engine-only
   resources must still come from the matching local engine output, never from
   another Flutter generation.
   the Nix source projection and do not disable `verify_sdk_hash`. The engine
   projection injects the locked Dart revision through `tools/GIT_REVISION`
   (via a patched `GetShortGitHash`), while `revisions.nix` supplies the locked
   Flutter, Skia, and Dart revisions to GN. VM, `platform_strong.dill`,
   `gen_snapshot`, and the AOT kernel must share the same first ten bytes of
   the Dart SDK revision.
7. The engine `$dev` output is intentionally minimal: only
   `engine-build/out/denial_host_release/{flutter_patched_sdk,gen,gen_snapshot,font-subset,flutter_linux,libflutter_linux_gtk.so,icudtl.dat}`
   and `flutter/{packages,sky/packages/sky_engine,lib/gpu}`. Do not copy the
   full `buildRoot` or the full Flutter checkout into `$dev`.
8. Run the static check before any long build:
   `nix flake check --all-systems --no-build --no-write-lock-file`.
9. Choose the engine build parallelism with `NIX_BUILD_CORES`; the derivation
   passes it to Ninja and defaults to one job when it is unset. For example:
   `NIX_BUILD_CORES=16 nix build .#denial-flutter-shell-source --no-link --fallback`.
   This builds the engine first, then the shell AOT snapshot. Verify that the
   result contains `libapp.so`, `flutter_assets`, and the matching local engine
   generation.
10. Build the final compositor with the desired Flutter runtime mode. The Rust
    package is always source; select the runtime only via the package option:
    `nix build .#denial` (prebuilt) vs
    `nix build --impure --expr 'let f = builtins.getFlake (toString ./.); in f.packages.x86_64-linux.denial.override { useSource = true; }'`
    (source). There is no separate `.#denial-source` package; the single
    `denial` package with `useSource` is the selection boundary.

Never mix a source shell with a prebuilt engine, or a source engine with a
prebuilt shell. If the Dart SDK revision changes, rebuild the engine before
building the shell; reusing an older `platform_strong.dill` or `gen_snapshot`
can produce an SDK-hash failure during AOT compilation.
