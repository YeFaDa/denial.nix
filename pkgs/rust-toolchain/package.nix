{
  callPackage,
  fetchurl,
  path,
  stdenv,
  version ? (builtins.fromTOML (builtins.readFile ../denial/rust-toolchain.toml)).toolchain.channel,
  hashes ? import ./hashes.nix,
}:

# A Rust toolchain pinned the way nixpkgs bootstraps its own: the official
# prebuilt installer bundle from static.rust-lang.org, unpacked by nixpkgs'
# pkgs/development/compilers/rust/binary.nix. Deliberately self-contained —
# no flake inputs, no external overlays — so the flake and NUR's default.nix
# evaluation resolve the identical toolchain against whichever nixpkgs they
# are given. Upstream's rust-toolchain.toml tracks current stable Rust and
# uses its newest stabilized APIs, so builds must not silently fall back to
# whatever rustc the surrounding nixpkgs ships.
#
# Owned surface: the version string and the hashes.nix table, both derived by
# scripts/update-release-pins from upstream and from Rust's signed release
# manifest. Everything else is nixpkgs' own machinery, evaluated against
# whichever nixpkgs this overlay is applied to.

let
  target = {
    "x86_64-linux" = "x86_64-unknown-linux-gnu";
    "aarch64-linux" = "aarch64-unknown-linux-gnu";
  }.${stdenv.hostPlatform.system} or (throw "rust-toolchain: unsupported system ${stdenv.hostPlatform.system}");

  hashes' = hashes.${version} or (throw "pkgs/rust-toolchain/hashes.nix has no entry for Rust ${version}");
  hash = hashes'.${stdenv.hostPlatform.system} or (throw "pkgs/rust-toolchain/hashes.nix has no ${stdenv.hostPlatform.system} entry for Rust ${version}");

  src = fetchurl {
    url = "https://static.rust-lang.org/dist/rust-${version}-${target}.tar.xz";
    inherit hash;
  };
in
callPackage "${toString path}/pkgs/development/compilers/rust/binary.nix" {
  inherit version src;
  platform = target;
  versionType = "dist";
}
