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

`denial-update-check` first compares the current version with the latest
immutable Denial release tag. If there is no new release, it exits without
reading `SOURCE_LOCK.json`, Flutter `DEPS`, or any source inputs. After a new
release is found, it reads the matching `SOURCE_LOCK.json`, Flutter fork's
`bin/internal` paths, and Dart revision from Flutter `DEPS`. It never follows
`main`, `master`, a moving branch, or an unpinned `latest` URL.

Run the complete report:

```console
$ nix run .#denial-update-check -- --json
```
The JSON report includes the release version, all prebuilt archive URLs and
hashes when a new release exists, source revisions, source resource paths, and
the exact update actions for `Cargo.lock`, `gclient-deps.json`, and both Pub
locks. Source dependency hashes are generated by `gclient2nix`; they are not
duplicated as manual fields in this repository.

`--no-source` is available only when a quick release-tag check is needed.
`--force` additionally downloads the three x86-64 release archives to compute
their hashes even when the version has not changed; it is not needed for the
normal check and may take time.

### Updating one release
1. If `has_update` is `1`, update `pkgs/version.nix`,
   `pkgs/prebuilt-hashes.nix`, and `pkgs/denial/Cargo.lock` using the
   reported immutable tag and archive hashes.
2. Regenerate `pkgs/denial-flutter-engine/gclient-deps.json` from the fixed
   Flutter source `DEPS` with `gclient2nix`; do not copy source hashes by hand.
3. Regenerate `flutter-tools-pubspec.lock.json` from the fixed Flutter source
   `packages/flutter_tools/pubspec.yaml` using the locked `nixpkgs-dart`
   `dart-bin`. Use the release source's `dart_shell/pubspec.lock` for the shell.
4. If the reported Dart version or revision changes, stop and update
   `nixpkgs-dart` and `flake.lock` manually. The updater must not guess this
   revision or use `denial-ui-development` as a fallback.
5. Update the two `bin/internal` paths in `revisions.nix` and verify both
   `denial` and `denial-source`.

The release and source changes above are one update transaction. Do not merge
only the prebuilt hashes while leaving source pins from another release.

### Verification

6. Run `nix flake check --all-systems --no-build --no-write-lock-file`.
7. Build the default Rust-source package with prebuilt Flutter artifacts:
   `nix build .#denial --no-link --fallback`.
8. Build the complete source package when source pins changed:
   `NIX_BUILD_CORES=16 nix build .#denial-source --no-link --fallback`.
9. Verify `deniald --version`, `libflutter_engine.so`, `libapp.so`, and
   `flutter_assets`; review and commit all pins together.

The daily GitHub workflow runs the same report and opens a PR after updating
the automatic pins. It does not build either package; build and review the PR
manually before merging. A Dart input change is reported for manual
maintenance and does not create a partial PR.

The source build never consumes `denial-ui-development`. That package is an
independent prebuilt developer toolchain and is not a source-build input.

Never mix a source shell with a prebuilt engine, or a source engine with a
prebuilt shell. If the Dart SDK revision changes, rebuild the engine before
building the shell; reusing an older `platform_strong.dill` or `gen_snapshot`
can produce an SDK-hash failure during AOT compilation.
