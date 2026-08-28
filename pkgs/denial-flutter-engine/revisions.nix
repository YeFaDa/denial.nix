{ lib }:

let
  lock = lib.importJSON ./gclient-deps.json;
  # Versions are pinned in the Flutter fork's bin/internal/*.
  # They are recorded here so material_fonts / gradle_wrapper URLs
  # stay derived from the locked Flutter revision instead of being
  # duplicated in flake.nix / source.nix.
  materialFontsVersion = "3012db47f3130e62f7cc0beabff968a33cbec8d8";
  gradleWrapperVersion = "fd5c1f2c013565a3bea56ada6df9d2b8e96d56aa";
in
{
  flutter = lock.".".args.rev;
  dart = lock."engine/src/flutter/third_party/dart".args.rev;
  skia = lock."engine/src/flutter/third_party/skia".args.rev;
  inherit materialFontsVersion gradleWrapperVersion;
}
