# Denial — nixpkgs packaging

Nix packaging for [Denial](https://github.com/denialwm/denial), a Flutter-native
Wayland compositor, written in the style of the niri package in nixpkgs.

## What is built from source, what is not

| Component | Package | Default x86-64 mode | Source mode |
| --- | --- | --- | --- |
| `deniald`, `denialctl`, `denial-portal`, session files | `denial` | Rust source | Rust source |
| `libflutter_engine.so`, `icudtl.dat` | `denial-flutter-engine` | upstream release artifact | locked Flutter/Skia sources with GN/Ninja |
| `libapp.so`, `flutter_assets` | `denial-flutter-shell` | upstream release artifact | `buildFlutterApplication` with the matching local engine |
| live UI toolchain (Flutter SDK + debug/profile engines) | `denial-ui-development` | upstream release archive | `denial-ui-development-source`, assembled from the local engine builds |

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

**Upstream publishes prebuilt artifacts for x86_64 only.** This is not worked
around with a fallback: on any other platform the prebuilt consumers throw at
evaluation time with a message telling you to switch to `useSource = true`. The
choice is left to whoever builds the package, so an unsupported platform never
silently receives an x86_64 binary inside an aarch64 store path.

| | `denial` (default) | `denial-source` |
| --- | --- | --- |
| x86_64-linux | prebuilt Flutter runtime, fast | everything from source, slower but auditable |
| aarch64-linux | **fails**, telling you to use `denial-source` | everything from source, works |

Nothing in the packaging branches on the platform to make this happen. Every
prebuilt package looks its own entry up in `pkgs/prebuilt-hashes.nix`, a table
keyed by platform, and throws when there is none. Supporting a new platform
means adding one attrset there — no `if isx86_64` anywhere in the derivations,
the overlay, or the flake outputs. Partial coverage works too: if upstream ships
an aarch64 engine before an aarch64 settings payload, list only `engine` under
that platform and the other consumers keep throwing on their own.

The source engine checkout is assembled with nixpkgs' `gclient2nix` format from
the pinned Flutter `DEPS` graph. The build does not run `gclient sync`, access a
developer checkout, or use a mutable cache.

The Flutter side cannot be built with the stock nixpkgs engine: Denial pins a
fork of Flutter 3.44.7 and Skia, and the AOT snapshot must use that matching
engine. The source derivations therefore use the forked engine output rather
than `flutterPackages.v3_44`'s normal engine artifacts.

The four runtime bundle members remain coupled to one engine/shell pair. Mixing
the source shell with a release engine, or vice versa, is unsupported.

### `denial-ui-development-source`

This one is source-built by a different route than the others, because it is not
a build output so much as a whole Flutter SDK deliverable. Upstream assembles it
by copying a tree that `flutter precache --linux` populated over the network and
then overwriting the parts it can build locally; a Nix build cannot do the first
half, so this derivation assembles the same tree from:

1. the pinned Flutter checkout, for everything that is genuinely source;
2. the locally built **debug** and **profile** engines, which upstream also
   overlays — this covers the entire Dart SDK, `impellerc`, `const_finder`,
   `font-subset`, `gen_snapshot` and the embedder headers;
3. `pkgs/flutter-engine-artifacts.nix` for four entries nothing builds:
   `icudtl.dat`, `isolate_snapshot.bin`, `vm_isolate_snapshot.bin` and
   `shader_lib/`.

That third group is why `denial-ui-development-source` declares
`binaryNativeCode` alongside `fromSource`. It is the one `-source` package in
this repository that ships upstream binaries, and the downloads are pinned per
platform in `pkgs/flutter-engine-artifacts.nix`. `icudtl.dat` belongs there
because nothing in Denial's own target list produces it — upstream's SDK tree
takes it from the `flutter precache` download, so this repository takes it from
the same archive.

The debug and profile engines come from the same engine derivation as the
release one, parameterised on `runtimeMode`:

```nix
pkgs.denial-flutter-engine-debug-source
pkgs.denial-flutter-engine-profile-source
```

Upstream commits one `args.gn` per mode and the three differ in two lines
(`flutter_runtime_mode` and `dart_runtime_mode`), so there is no second copy of
the build logic. The ninja target lists do differ, and are a table in
`pkgs/denial-flutter-engine/source.nix`.

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
  template; the launcher resolves this from the store, so a file in `/etc` is
  never read)
- desktop entry `Exec`/`TryExec` → `$out/bin/denial-session`

The template is only ever a seed for `~/.config/denial/outputs.conf`, written on
first login and owned by the user afterwards. There is deliberately no option to
configure it from the NixOS module: system and home directory scopes should not
overlap, and a system-level setting that stops applying the moment the user edits
their own copy is worse than no setting at all.

`/etc/denial/session.conf` is the one machine-level file the launcher still
sources when it exists; the module provides it through `environment.etc`.

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
registers a PAM service for the lock screen, enables xdg-desktop-portal with
the GTK and wlroots backends, and exposes the portal routing the `denial`
package already ships (`share/xdg-desktop-portal/denial-portals.conf`) through
`xdg.portal.configPackages`.

Session-wide environment variables go through `/etc/denial/session.conf`, which
`denial-session` sources on every start:

```nix
programs.denial = {
  extraSessionConf.DENIAL_RUST_LOG = "deniald=debug";
};
```

They are deliberately not exported through `environment.sessionVariables`,
which would put them into every PAM session on the machine — ssh logins, ttys
and any other desktop environment — rather than just the Denial one.

Output configuration is not exposed here at all. `denial-session` seeds
`$out/share/denial/outputs.conf` into `~/.config/denial/outputs.conf` on first
login and never looks at it again, so a system-level setting would stop
applying the moment the user edited their own copy. Configure outputs in your
home directory instead.

The module does not write `xdg.portal.config.denial`. That option lands in
`/etc/xdg/xdg-desktop-portal/denial-portals.conf`, and `portals.conf(5)` reads
only the first file found while ranking every config directory above every
data directory — such a copy would shadow the packaged routing and drift
silently whenever upstream changes it.

Optional runtime tools the shell can use — matching upstream's optional
dependencies:

```nix
programs.denial.extraRuntimePackages = with pkgs; [
  networkmanager      # network controls (nmcli)
  upower              # battery status
  power-profiles-daemon
];
```

### UI development toolchain

Editing Denial's UI needs a Flutter toolchain that running the session does
not: `denial-ui-development` bundles a pinned Flutter SDK, the debug and
profile engines, and a workspace template. Nothing pulls it in on its own —
turn it on explicitly:

```nix
programs.denial.uiDevelopment.enable = true;
```

The toolchain follows the compositor you actually selected, not the `useSource`
flag, so a source-built `denial` gets `denial-ui-development-source` and a
prebuilt one gets the prebuilt toolchain. Hand-written
`programs.denial.package` definitions are followed the same way. To pin the
other combination anyway:

```nix
programs.denial.uiDevelopment.package = pkgs."denial-ui-development-source";
```

Only the prebuilt toolchain is x86-64 only, for the same reason `pkgs.denial`
is; the `-source` variant builds on both supported platforms.

Notes:

- Xwayland, zenity and systemd are already on the session PATH by default.
- CJK fallback fonts (upstream ships `adobe-source-han-sans-cn-fonts`) are a
  fontconfig concern; add a CJK font to `fonts.packages` if needed.
- The `denial` package includes `denial-settings` and its desktop entry, using
  whichever bundle `useSource` selects.
- **`aarch64` needs one extra line.** Upstream publishes no prebuilt artifacts
  for it, so `pkgs.denial` throws there by design:

  ```nix
  programs.denial.package = pkgs.denial-source;
  ```

  The same applies to the UI development toolchain, whose `-source` variant is
  available here as well; see
  [UI development toolchain](#ui-development-toolchain).
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

`scripts/update-release-pins <tag>` performs every step below — version pins,
`gclient-deps.json`, both Pub locks, `Cargo.lock`, the artifacts archive hashes
and the `bin/internal` paths — and is what the daily workflow runs. Step 4
stays manual by design: a Dart input change stops the script and asks for
`nixpkgs-dart` to be updated first. The steps are spelled out for when the
script cannot run, and to make reviewable what it does.

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
