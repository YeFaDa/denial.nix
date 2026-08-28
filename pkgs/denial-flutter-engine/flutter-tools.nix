{
  lib,
  stdenv,
  buildDartApplication,
  gclient2nix,
  dart,
  git,
  which,
  revisions,
  sdkSourceBuilders ? { },
}: 
let
  gclientDeps = gclient2nix.importGclientDeps ./gclient-deps.json;
  hostPlatform = if stdenv.hostPlatform.isx86_64 then "linux-x64" else "linux-arm64";
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
  dartCompileFlags = [ "--define=NIX_FLUTTER_HOST_PLATFORM=${hostPlatform}" ];
  nativeBuildInputs = [ git which ];

  preConfigure = ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    export FLUTTER_ROOT="$TMPDIR/flutter-root"
    mkdir -p "$FLUTTER_ROOT/bin/internal" "$FLUTTER_ROOT/bin/cache"
    ln -s ${dart} "$FLUTTER_ROOT/bin/cache/dart-sdk"
    cat > "$FLUTTER_ROOT/bin/cache/engine_stamp.json" <<EOF
    {
      "build_time_ms": 0,
      "git_revision": "${revisions.flutter}",
      "git_revision_date": "1970-01-01T00:00:00Z",
      "content_hash": "${revisions.flutter}"
    }
    EOF
    printf '%s\n' ${revisions.flutter} > "$FLUTTER_ROOT/bin/cache/engine.stamp"
    printf '%s\n' ${revisions.flutter} > "$FLUTTER_ROOT/bin/cache/engine_stamp.stamp"
    printf '%s\n' ${revisions.flutter} > "$FLUTTER_ROOT/bin/internal/engine_stamp.version"
  '';

  meta = {
    description = "Flutter tools built from the locked Denial Flutter fork";
    homepage = "https://github.com/denialwm/flutter";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
