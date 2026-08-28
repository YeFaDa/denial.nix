{ lib }:

let
  lock = lib.importJSON ./gclient-deps.json;
in
{
  flutter = lock.".".args.rev;
  dart = lock."engine/src/flutter/third_party/dart".args.rev;
  skia = lock."engine/src/flutter/third_party/skia".args.rev;
}
