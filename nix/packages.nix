# The package set exposed by both the flake's `packages` output and
# default.nix — the file NUR evaluates.
{ pkgs }:
# No platform branching here on purpose. Upstream publishes prebuilt
# artifacts for x86_64 only, and every prebuilt consumer looks its own
# entry up in pkgs/prebuilt-hashes.nix and throws when the current
# platform has none. So `denial` on aarch64 fails loudly with a message
# telling you to use `denial-source`, instead of quietly handing you an
# x86_64 binary.
{
  denial = pkgs.denial;
  denial-source = pkgs.denial.override { useSource = true; };
  inherit (pkgs)
    denial-flutter-engine
    denial-flutter-shell
    denial-flutter-engine-source
    denial-flutter-shell-source
    ;
  "denial-settings" = pkgs.denialSettings;
  "denial-settings-source" = pkgs.denialSettings.override { useSource = true; };
  "denial-ui-development" = pkgs.denialUiDevelopment;
  # The source-built counterpart. Unlike the prebuilt one this is not
  # restricted to x86_64: the engines come from the shared source build
  # and the three upstream-only files are pinned per platform in
  # pkgs/flutter-engine-artifacts.nix.
  "denial-ui-development-source" = pkgs."denial-ui-development-source";
  # Exposed for the same reason as `denial-flutter-engine-source`, so
  # the extra modes can be built and inspected on their own. They are
  # not `denial-ui-development-source`'s only reason to exist -- it
  # depends on both -- but they are useful when debugging an engine
  # build, since a failing debug or profile tree can be reproduced
  # without paying for the whole toolchain.
  "denial-flutter-engine-debug-source" = pkgs."denial-flutter-engine-debug-source";
  "denial-flutter-engine-profile-source" = pkgs."denial-flutter-engine-profile-source";
  "gclient2nix-linux" = pkgs.gclient2nixLinux;
  "denial-update-check" = pkgs.updateCheck;
}
