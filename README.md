# Nix/Nixos packaging for denialwm/denial

> **Upstream maintains its own Nix flake.** The Denial repository ships a
> `flake.nix` and `nix/` directory, including a NixOS module. This repository
> is an independent, unofficial packaging with no affiliation to upstream.
> Use upstream's flake if you want the officially supported setup.

Unoffical Nix packaging for [Denial](https://github.com/denialwm/denial), a Flutter-native
Wayland compositor.

Maintainer Note: Due to limited personal maintenance bandwidth, I may not be able to keep up with upstream updates or provide up-to-date binary caches in a timely manner. Contributions and co-maintainers are highly welcome.

> **Note**
>
> Because this repository consumes upstream prebuilt artifacts, only the Denial
> desktop itself is guaranteed to work. Other modules and features are not
> guaranteed to run correctly.
>
> The packaging in this repository was done by AI, and my own NixOS experience
> is not extensive.

## What is built from source, what is not

| Component | Package | Default x86-64 mode | Source mode |
| --- | --- | --- | --- |
| `deniald`, `denialctl`, `denial-portal`, session files | `denial` | Rust source | Rust source |
| `libflutter_engine.so`, `icudtl.dat` | `denial-flutter-engine` | upstream release artifact | locked Flutter/Skia sources with GN/Ninja |
| `libapp.so`, `flutter_assets` | `denial-flutter-shell` | upstream release artifact | `buildFlutterApplication` with the matching local engine |
| live UI toolchain (Flutter SDK + debug/profile engines) | `denial-ui-development` | upstream release archive in an FHS environment | `denial-ui-development-source`, assembled from the local engine builds |

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
expects (`$out/lib/denial/flutter/{lib,data}`). The launcher derives its prefix
from `argv[0]`, so nothing in it is written against `/usr` and the only path
that needs patching is the desktop entry's `Exec`/`TryExec`, pointed at
`$out/bin/denial-session`.

`session.conf` and `outputs.conf` are looked up the same way, taking the first
that exists: a `$DENIAL_*` override, then `/etc/denial/`, then the packaged
copy under `$out/etc/denial/`. Both packaged copies are upstream's own
`packaging/arch` files installed verbatim, and neither carries an active
directive — they document the accepted syntax in comments. The two module
options that write the `/etc` files are documented under
[Usage](#usage).

`deniald` dlopens `libEGL.so.1`, `libwayland-server.so`, `libpulse.so.0`,
`libpam.so.0` and `libddcutil.so.5`; those libraries are buildInputs so the
generated RUNPATH resolves them (same trick as niri, plus explicit force
linking of EGL/wayland-server). The prebuilt engine gets a patched RUNPATH to
find `libfontconfig`. Both engine variants (prebuilt and source) also get
`/run/opengl-driver/lib` on that RUNPATH: the shell's GPU telemetry dlopens
NVML (`libnvidia-ml.so.1`) by bare soname from Dart FFI inside the engine, and
that library comes from the NVIDIA driver rather than the store, so it can only
resolve through the host's OpenGL driver directory. A missing directory is
skipped by the dynamic linker, which leaves hosts without the driver — or
without NixOS — unaffected.

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
        { programs.denial.enable = true; }
      ];
    };
  };
}
```

Importing the module is enough. It applies `denial.overlays.default` itself,
because the `programs.denial.package` and
`programs.denial.uiDevelopment.package` defaults are looked up as
`pkgs.denial` and `pkgs."denial-ui-development"`. Overlays are additive, so
also listing `nixpkgs.overlays = [ denial.overlays.default ];` yourself gives
the same attribute values twice rather than a conflict; the overlay stays
exported for anyone who wants `pkgs.denial` outside the module.

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

Display configuration goes through `programs.denial.outputsConf`, which takes
the file content as a string:

```nix
programs.denial.outputsConf = ''
  eDP-1=0,0
  primary=eDP-1
  scale=eDP-1,1.5
'';
```

Or assembled from other Nix values:

```nix
let layout = [ "eDP-1=0,0" "DP-1=1920,0" "primary=DP-1" ]; in
{
  programs.denial.outputsConf = lib.concatStringsSep "\n" layout;
}
```

The content is written to `/etc/denial/outputs.conf` and treated as
declarative: rearranging a display in Settings keeps the result in
`~/.local/state/denial/outputs.conf`, and changing this string makes the new
content replace it at the next login. Leave it unset to write no `/etc` file
at all and let each user configure `~/.config/denial/outputs.conf` themselves.

The accepted directives — `eDP-1=0,0` placement, `mode`, `scale`, `primary`,
`transform`, `vrr`, `system_bar` and `maximize_padding` — are the ones the
commented reference shipped inside the package documents.

The module does not write `xdg.portal.config.denial`. That option lands in
`/etc/xdg/xdg-desktop-portal/denial-portals.conf`, and `portals.conf(5)` reads
only the first file found while ranking every config directory above every
data directory — such a copy would shadow the packaged routing and drift
silently whenever upstream changes it.

Optional runtime tools the shell can use — matching upstream's optional
dependencies:

```nix
programs.denial.extraRuntimePackages = with pkgs; [
  networkmanager        # network controls (nmcli)
  iwd                   # Wi-Fi controls without NetworkManager
  modemmanager          # mobile signal status and SIM PIN unlock
  upower                # battery status
  power-profiles-daemon
  lact                  # AMD GPU performance controls
  pipewire-pulse        # desktop audio controls
  fprintd               # fingerprint unlock and enrollment
  sudo                  # authorize fingerprint management in Settings
];
```

Settings controls external monitor brightness over DDC/CI, which needs access
to `/dev/i2c-*`. That access is granted by default; turn it off if the machine
manages I2C for something else:

```nix
programs.denial.ddc.enable = false;
```

Privileged operations from the session — mounting a drive, connecting to a
network, changing the clock — show a Polkit password dialog. The agent that
draws it is started automatically; disable it if another component in the same
session already provides one, or replace the command:

```nix
programs.denial.polkitAgent = {
  enable = true;
  command = "${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1";
};
```

### UI development toolchain

Editing Denial's UI needs a Flutter toolchain that running the session does
not: `denial-ui-development` bundles a pinned Flutter SDK, the debug and
profile engines, and a workspace template. Nothing pulls it in on its own —
turn it on explicitly:

```nix
programs.denial.uiDevelopment.enable = true;
```

The prebuilt toolchain is the upstream release archive wrapped in a bubblewrap
FHS environment (`buildFHSEnv`). The payload is built for generic Linux — its
ELFs carry a `/lib64` interpreter where NixOS mounts a rejecting stub, and
their sonames have no `ld.so.cache` to resolve through — so patching it
ELF-by-ELF is not realistic. Inside the environment it runs exactly as
upstream intends: the launcher's compiled-in `/usr/lib/denial/ui-development`
root is recreated, `flutter build` shells out to the packaged CMake, Ninja and
Clang, and `/run/opengl-driver` stays reachable so GL uses the host's driver.
The first `denial-ui prepare` copies the Pub cache seed and build state into
`~/.cache/denial/ui-development`, so the read-only store behaves like a
root-owned `/usr` would upstream. The entry point keeps upstream's CLI:
`denial-ui COMMAND [WORKSPACE]`, with `denial-ui doctor` reporting whatever
is missing.

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
  whichever bundle `useSource` selects. The shell's `/usr/bin/...` lookups are
  gone: `denial-session` exports `DENIAL_COMPOSITOR_BINARY`,
  `DENIAL_CONTROL_TOOL` and `DENIAL_SETTINGS_BINARY` as package-relative paths,
  so Settings opens with no `session.conf` entry and no module involved. One
  adaptation does remain: the prebuilt bundle's ELF interpreter is repointed at
  the NixOS loader (upstream builds it for generic Linux, which NixOS's stub
  loader refuses to run).
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

