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

  # Shared with the engine, shell and settings derivations. `platform` rather
  # than `cpu`: flutter_tools wants the full Flutter platform name here.
  flutterArch = import ../flutter-arch.nix { system = stdenv.hostPlatform.system; };
in
buildDartApplication.override { inherit dart; } (finalAttrs: {
  pname = "denial-flutter-tools";
  version = "3.44.7-denial";
  src = gclientDeps.".".path;
  sourceRoot = "source/packages/flutter_tools";
  pubspecLock = lib.importJSON ./flutter-tools-pubspec.lock.json;
  inherit sdkSourceBuilders;
  dartEntryPoints = {
    "flutter_tools.snapshot" = "bin/flutter_tools.dart";
  };
  dartOutputType = "jit-snapshot";
  dartCompileFlags = [ "--define=NIX_FLUTTER_HOST_PLATFORM=${flutterArch.platform}" ];
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
