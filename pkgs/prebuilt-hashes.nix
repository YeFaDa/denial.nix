# Prebuilt release artifacts, keyed by host platform.
#
# Upstream currently publishes x86_64 payloads only. Rather than picking a
# fallback at evaluation time, every prebuilt consumer looks up its own entry
# here and throws when the current platform has none. That keeps the failure
# explicit: on an unsupported platform the build stops with a message pointing
# at `useSource = true`, instead of silently producing an x86_64 binary inside
# an aarch64 store path.
#
# To add a platform, add one attrset here. Nothing else has to change: no
# `if isx86_64` branches in the derivations, no overlay branches, no changes to
# the flake outputs. Partial coverage works too — if upstream ships an aarch64
# engine before it ships an aarch64 settings payload, list only `engine` under
# that platform and the other consumers keep throwing on their own.
#
# `shell` and `settings` deliberately reuse the `denial` entry: upstream ships
# both inside the main compositor archive.
let
  version = import ./version.nix;
in
{
  "x86_64-linux" = {
    denial = {
      url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-${version}-1-x86_64.pkg.tar.zst";
      hash = "sha256-oKI+C4UIIe9pd3nkLzDYpTeF1OwPV29LHV+CXwRCbQM=";
    };
"""
    f"""    engine = {
      url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-flutter-engine-1.${version}-1-x86_64.pkg.tar.zst";
      hash = "sha256-moyDvDyzMUTaxIHtBwSlYDzjiqBNczyElRzkSCM058w=";
    };
"""
    f"""    uiDevelopment = {
      url = "https://github.com/denialwm/denial/releases/download/v${version}/denial-ui-development-${version}-1-x86_64.pkg.tar.zst";
      hash = "sha256-v35GRv9JYPbnzG6LsZFMkNzpdo7aL3x4MzTh1Vt86yw=";
    };
  };
}
