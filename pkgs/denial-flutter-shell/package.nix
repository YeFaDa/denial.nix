{
  lib,
  stdenv,
  fetchurl,
  zstd,
}:

# Prebuilt Dart shell of Denial: the AOT snapshot (libapp.so) and the Flutter
# assets of the desktop shell. The snapshot must be produced by the Flutter
# SDK fork pinned in prebuilt/flutter-tools/3.44.7 of the denial repository;
# it only loads in the matching forked engine, so this artifact must stay
# coupled to the denial-flutter-engine and denial package versions.
stdenv.mkDerivation (finalAttrs: {
  pname = "denial-flutter-shell";
  version = import ../version.nix;

  src = fetchurl {
    url = "https://github.com/denialwm/denial/releases/download/v${finalAttrs.version}/denial-${finalAttrs.version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-pxYAGM2bizwUsnYtvn3/gcLHlYWKWUYkQ3Hc807wSbE=";
  };

  nativeBuildInputs = [ zstd ];

  # Official release payload: an Arch package whose interesting members are
  # usr/lib/denial/flutter/{lib/libapp.so,data/flutter_assets}.
  setSourceRoot = "sourceRoot=.";

  unpackPhase = ''
    runHook preUnpack
    tar -I zstd -xf "$src" \
      usr/lib/denial/flutter/lib/libapp.so \
      usr/lib/denial/flutter/data/flutter_assets \
      usr/share/licenses/denial
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    # Layout expected by deniald's --flutter-bundle directory:
    #   lib/libapp.so, data/flutter_assets
    install -Dm555 usr/lib/denial/flutter/lib/libapp.so \
      "$out/lib/denial/flutter/lib/libapp.so"
    mkdir -p "$out/lib/denial/flutter/data"
    cp -a usr/lib/denial/flutter/data/flutter_assets \
      "$out/lib/denial/flutter/data/flutter_assets"
    chmod -R u=rwX,go=rX "$out/lib/denial/flutter/data/flutter_assets"

    install -Dm444 -t "$out/share/licenses/${finalAttrs.pname}" \
      usr/share/licenses/denial/*

    runHook postInstall
  '';

  dontStrip = true;

  meta = {
    description = "Prebuilt Flutter shell (AOT snapshot and assets) for the Denial compositor";
    homepage = "https://github.com/denialwm/denial";
    changelog = "https://github.com/denialwm/denial/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [
      gpl3Plus # shell code
      cc-by-sa-40 # bundled wallpapers and cursor assets
      ofl # bundled fonts
    ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    hydraPlatforms = [ ];
  };
})
