{
  callPackage,
  fetchurl,
  lib,
  makeWrapper,
  path,
  runCommand,
  stdenv,
  version ? (builtins.fromTOML (builtins.readFile ../denial/rust-toolchain.toml)).toolchain.channel,
  # Not named `hashes`: nixpkgs' top-level scope has an unrelated `hashes`
  # attribute, and callPackage auto-fills scope-matching arguments even when
  # a default is given.
  toolchainHashes ? import ./hashes.nix,
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

  hashes' = toolchainHashes.${version} or (throw "pkgs/rust-toolchain/hashes.nix has no entry for Rust ${version}");
  hash = hashes'.${stdenv.hostPlatform.system} or (throw "pkgs/rust-toolchain/hashes.nix has no ${stdenv.hostPlatform.system} entry for Rust ${version}");

  src = fetchurl {
    url = "https://static.rust-lang.org/dist/rust-${version}-${target}.tar.xz";
    inherit hash;
  };

  # Upstream's dist toolchain ships rust-lld and links with it by default on
  # x86_64-unknown-linux-gnu. rustc then drives the link as
  # `cc -B <rustlib>/bin/gcc-ld -fuse-ld=lld`, and the cc-wrapper does not
  # translate the dependency -L paths it hands over into -rpath on that path,
  # so every binary comes out with an empty RUNPATH and each dlopen()ed
  # library fails to resolve at runtime.
  #
  # nixpkgs' own rustc does not have this: it is configured with
  # `--disable-lld` (rustc.nix:147, plus the `"rust-lld"` -> `"lld"` rename
  # at rustc.nix:344) and ships no bundled linker -- its rustlib bin/ holds
  # nothing but rust-objcopy. nixpkgs runs into the very same thing whenever
  # it uses this exact tarball as its bootstrap compiler, and passes these
  # two flags there (rustc.nix:100-106, same comment word for word).
  #
  # Bake them into the toolchain rather than into every consumer: with this,
  # the whole toolchain links through the cc-wrapper's ld and derives RUNPATH
  # from buildInputs, exactly like nixpkgs' rustc.
  noSelfContainedLinkerFlags = [
    "-Clinker-features=-lld"
    "-Clink-self-contained=-linker"
  ];

  dist = callPackage "${toString path}/pkgs/development/compilers/rust/binary.nix" {
    inherit version src;
    platform = target;
    versionType = "dist";
  };
in
dist
// {
  rustc = runCommand "rustc-${version}" {
    inherit (dist.rustc) version src meta;
    passthru = (dist.rustc.passthru or { }) // {
      unwrapped = dist.rustc;
    };
    nativeBuildInputs = [ makeWrapper ];
  } ''
    mkdir -p "$out/bin"
    for program in ${dist.rustc}/bin/*; do
      makeWrapper "$program" "$out/bin/$(basename "$program")" \
        --add-flags "${lib.escapeShellArgs noSelfContainedLinkerFlags}"
    done
  '';
}
