{
  lib,
  stdenv,
  fetchurl,
  zstd,
}:

let
  prebuilt = import ../prebuilt-hashes.nix;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "denial-ui-development";
  version = import ../version.nix;

  src = fetchurl {
    inherit (prebuilt.uiDevelopment) url hash;
  };

  nativeBuildInputs = [ zstd ];

  setSourceRoot = "sourceRoot=.";

  unpackPhase = ''
    runHook preUnpack
    tar -I zstd -xf "$src"
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out"
    cp -a usr/. "$out/"
    # Keep only the UI development payload
    # usr/bin/denial-ui, usr/lib/denial/ui-development, usr/share/denial/ui-development
    runHook postInstall
  '';

  dontStrip = true;

  meta = {
    description = "Prebuilt UI development toolchain for Denial (Flutter SDK + profile engine + pub cache)";
    homepage = "https://github.com/denialwm/denial";
    changelog = "https://github.com/denialwm/denial/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    hydraPlatforms = [ ];
  };
})
