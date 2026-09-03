# Flutter architecture naming, keyed by Nix platform.
#
# Flutter and the engine build scripts spell CPU architectures their own way
# and none of them match Nix's `x86_64-linux`:
#
#   cpu       "x64" / "arm64"
#             GN and the Dart build output tree (`build/linux/x64/release/...`).
#
#   platform  "linux-x64" / "linux-arm64"
#             The Flutter target platform name, also used for the cache
#             directory layout (`bin/cache/artifacts/engine/linux-x64/...`)
#             and for the engine's own `buildtools/linux-x64` and
#             `prebuilts/linux-x64` paths.
#
# Both spellings come from the same table so that adding a platform means
# editing one file rather than the four that used to carry their own copy of
# this mapping. Keyed by `system` and looked up with `or` + `throw`, exactly
# like pkgs/prebuilt-hashes.nix: an unknown platform fails at evaluation time
# with a message saying where to add it, instead of silently falling back to
# one of the two known values.
#
# Note this table is independent of pkgs/prebuilt-hashes.nix on purpose: that
# one records where upstream publishes prebuilt artifacts (x86_64 only today),
# this one records how to name a CPU when building from source (both
# platforms). They will not always cover the same set.
{ system }:
{
  "x86_64-linux" = {
    cpu = "x64";
    platform = "linux-x64";
  };
  "aarch64-linux" = {
    cpu = "arm64";
    platform = "linux-arm64";
  };
}."${system}" or (throw "flutter-arch.nix: no Flutter architecture mapping for ${system}; add an entry here")
