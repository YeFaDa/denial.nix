{ lib }:

let
  lock = lib.importJSON ./gclient-deps.json;
  # These values mirror Flutter's bin/internal files exactly. The files contain
  # complete storage paths, not only revision IDs.
  materialFontsVersion = "flutter_infra_release/flutter/fonts/3012db47f3130e62f7cc0beabff968a33cbec8d8/fonts.zip";
  gradleWrapperVersion = "flutter_infra_release/gradle-wrapper/fd5c1f2c013565a3bea56ada6df9d2b8e96d56aa/gradle-wrapper.tgz";
in
{
  flutter = lock.".".args.rev;
  dart = lock."engine/src/flutter/third_party/dart".args.rev;
  skia = lock."engine/src/flutter/third_party/skia".args.rev;
  inherit materialFontsVersion gradleWrapperVersion;
}
