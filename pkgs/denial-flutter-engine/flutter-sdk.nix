{
  lib,
  stdenv,
  gclient2nix,
  git,
  makeWrapper,
  dart,
  flutterTools,
}:

let
  version = "3.44.7-denial";
  gclientDeps = gclient2nix.importGclientDeps ./gclient-deps.json;
in
stdenv.mkDerivation {
  pname = "denial-flutter-sdk";
  inherit version;
  src = gclientDeps.".".path;
  sourceRoot = "source";
  nativeBuildInputs = [ git makeWrapper ];
  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    cp -a . "$out"
    chmod -R u+w "$out"
    rm -rf "$out/.git"
    mkdir -p "$out/bin/cache"
    ln -sf ${dart} "$out/bin/cache/dart-sdk"
    ln -sf ${flutterTools}/share/flutter_tools.snapshot \
      "$out/bin/cache/flutter_tools.snapshot"
    cp "$out/bin/internal/engine.version" "$out/bin/cache/engine.stamp"
    printf '%s\n' '${version}' > "$out/version"
    makeWrapper "$out/bin/cache/dart-sdk/bin/dart" "$out/bin/flutter" \
      --set FLUTTER_ROOT "$out" \
      --set FLUTTER_ALREADY_LOCKED true \
      --add-flags "--disable-dart-dev $out/bin/cache/flutter_tools.snapshot"
  '';

  passthru = { inherit gclientDeps; };

  meta = {
    description = "Denial's locked Flutter fork SDK and tool snapshot";
    homepage = "https://github.com/denialwm/flutter";
    license = lib.licenses.bsd3;
    platforms = lib.platforms.linux;
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
}
