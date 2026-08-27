{
  lib,
  buildDartApplication,
  gclient2nix,
  dart,
  git,
  which,
  sdkSourceBuilders ? { },
}:
let
  gclientDeps = gclient2nix.importGclientDeps ./gclient-deps.json;
in
buildDartApplication.override { inherit dart; } (finalAttrs: {
  pname = "denial-flutter-tools";
  version = "3.44.7-denial";
  src = gclientDeps.".".path;
  sourceRoot = "source/packages/flutter_tools";
  pubspecLock = lib.importJSON ./flutter-tools-pubspec.lock.json;
  gitHashes = {
    assets_for_android_views = "sha256-GN7nBxBwnlByp3E8uUDabWiuMUoYYHPtIveF+RiEpS8=";
  };
  inherit sdkSourceBuilders;
  dartEntryPoints = {
    "flutter_tools.snapshot" = "bin/flutter_tools.dart";
  };
  dartOutputType = "jit-snapshot";
  dartCompileFlags = [ "--define=NIX_FLUTTER_HOST_PLATFORM=linux-x64" ];
  nativeBuildInputs = [ git which ];

  preConfigure = ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export FLUTTER_ROOT="$TMPDIR/flutter-root"
    mkdir -p "$FLUTTER_ROOT/bin/internal" "$FLUTTER_ROOT/bin/cache"
    ln -s ${dart} "$FLUTTER_ROOT/bin/cache/dart-sdk"
    cat > "$FLUTTER_ROOT/bin/cache/engine_stamp.json" <<'EOF'
    {
      "build_time_ms": 0,
      "git_revision": "b20ca326b99f27e33a416ba684333b2a20f711a9",
      "git_revision_date": "1970-01-01T00:00:00Z",
      "content_hash": "b20ca326b99f27e33a416ba684333b2a20f711a9"
    }
    EOF
    printf '%s\n' b20ca326b99f27e33a416ba684333b2a20f711a9 \
      > "$FLUTTER_ROOT/bin/cache/engine.stamp"
    printf '%s\n' b20ca326b99f27e33a416ba684333b2a20f711a9 \
      > "$FLUTTER_ROOT/bin/cache/engine_stamp.stamp"
    printf '%s\n' b20ca326b99f27e33a416ba684333b2a20f711a9 \
      > "$FLUTTER_ROOT/bin/internal/engine_stamp.version"
  '';

  meta = {
    description = "Flutter tools built from the locked Denial Flutter fork";
    homepage = "https://github.com/denialwm/flutter";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
