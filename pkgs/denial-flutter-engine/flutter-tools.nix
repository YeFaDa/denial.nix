{
  lib,
  buildDartApplication,
  gclient2nix,
  runCommand,
  sdkSourceBuilders ? { },
  dart,
}:

let
  gclientDeps = gclient2nix.importGclientDeps ./gclient-deps.json;
in
buildDartApplication (finalAttrs: {
  gitHashes = {
    assets_for_android_views = "";
  };
  inherit gclientDeps sdkSourceBuilders;
  nativeBuildInputs = [ gclient2nix.gclientUnpackHook ];
  pname = "denial-flutter-tools";
  version = "3.44.7-denial";
  src = gclientDeps.".".path;
  sourceRoot = "source/packages/flutter_tools";
  pubspecLock = lib.importJSON ./flutter-tools-pubspec.lock.json;
  dart = dart;
  dartEntryPoints = {
    "flutter_tools.snapshot" = "bin/flutter_tools.dart";
  };
  dartOutputType = "jit-snapshot";
  dartCompileFlags = [ "--define=NIX_FLUTTER_HOST_PLATFORM=linux-x64" ];
  preConfigure = ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export FLUTTER_ROOT="$PWD/../.."
    mkdir -p "$FLUTTER_ROOT/bin/cache"
    cp "$FLUTTER_ROOT/bin/internal/engine.version" \
      "$FLUTTER_ROOT/bin/cache/engine.stamp"
  '';

  meta = {
    description = "Flutter tools built from the locked Denial Flutter fork";
    homepage = "https://github.com/denialwm/flutter";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
