{
  lib,
  stdenv,
  fetchFromGitHub,
  flutter,
  denial-flutter-engine-source,
}:

let
  version = import ../version.nix;
  arch = if stdenv.hostPlatform.isx86_64 then "x64" else "arm64";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "denial-flutter-shell-source";
  inherit version;
  src = fetchFromGitHub {
    owner = "denialwm";
    repo = "denial";
    tag = "v${version}";
    hash = "sha256-LEn3JA7PZ5IckhMhgTcVBokkxfxE/QJ/UmSNutM/GGY=";
  };
  sourceRoot = "source/dart_shell";
  strictDeps = true;
  dontStrip = true;
  nativeBuildInputs = [ flutter ];

  configurePhase = ''
    runHook preConfigure
    export HOME="$TMPDIR/home"
    export PUB_CACHE="$TMPDIR/pub-cache"
    mkdir -p "$HOME" "$PUB_CACHE"
    cp ${./pubspec.lock.json} pubspec.lock
    flutter config --no-analytics --enable-linux-desktop
    flutter pub get --offline
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild
    flutter assemble \
      --suppress-analytics \
      --output="$TMPDIR/bundle" \
      --local-engine-src-path="${denial-flutter-engine-source.dev}/engine-build" \
      --local-engine=denial_host_release \
      --local-engine-host=denial_host_release \
      -dTargetPlatform=linux-${arch} \
      -dBuildMode=release \
      -dTreeShakeIcons=true \
      release_bundle_linux-${arch}_assets
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 "$TMPDIR/bundle/lib/libapp.so" \
      "$out/lib/denial/flutter/lib/libapp.so"
    mkdir -p "$out/lib/denial/flutter/data"
    cp -a "$TMPDIR/bundle/flutter_assets" \
      "$out/lib/denial/flutter/data/flutter_assets"
    chmod -R u=rwX,go=rX "$out/lib/denial/flutter/data/flutter_assets"
    install -Dm444 assets/fonts/OFL.txt \
      "$out/share/licenses/${finalAttrs.pname}/OFL.txt"
    runHook postInstall
  '';

  meta = {
    description = "Denial Dart shell built with the Denial Flutter fork";
    homepage = "https://github.com/denialwm/denial";
    license = with lib.licenses; [ gpl3Plus cc-by-sa-40 ofl ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
