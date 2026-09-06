# Official Dart SDK release archives, keyed by SDK version, then by host
# platform.
#
# The version here must match the Dart revision pinned by upstream's Flutter
# DEPS graph (see pkgs/denial-flutter-engine/revisions.nix):
# scripts/update-release-pins derives the version from
# dart-lang/sdk's tools/VERSION at that revision and appends an entry here.
#
# The archive is the same one nixpkgs' `dart-bin` fetches, so the flake reuses
# that derivation wholesale and only swaps `version` and `src`. Hashes are
# SRI sha256, obtained with:
#   nix store prefetch-file --hash-type sha256 <url>
{
  "3.12.2" = {
    "x86_64-linux" = "sha256-KOR7RM8HXzZ3EEbAaLsNF0IBz5x2CHRK7RzCMgQpnC0=";
    "aarch64-linux" = "sha256-+CyD7OfRaAR1UN/UpmTkBxrHxIi923LcQxAsItfgtRg=";
  };
}
