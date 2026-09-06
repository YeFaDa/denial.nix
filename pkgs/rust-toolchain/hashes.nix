# Official Rust installer bundles (static.rust-lang.org), keyed by toolchain
# version — the `channel` in pkgs/denial/rust-toolchain.toml, which
# scripts/update-release-pins copies from upstream and keeps this table in
# step with — then by host platform.
#
# The bundle is unpacked by nixpkgs' own pkgs/development/compilers/rust/
# binary.nix, the same expression nixpkgs uses to bootstrap its rustc.
# Hashes are SRI sha256 of the .tar.xz, taken from the release's signed
# channel-rust-<version>.toml manifest.
{
  "1.98.0" = {
    "x86_64-linux" = "sha256-7Y7i33CQnIjLr4emz6OSDawAtTfeEqar5pBmQeD1lS8=";
    "aarch64-linux" = "sha256-rJKDGEMBru0G7Mn1qkwb5wQeGKGxl7bLbF0WLZj1Zto=";
  };
}
