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

  # Looked up per platform rather than selected with an `if`. Upstream ships
  # this toolchain for x86_64 only, so on any other platform this throws at
  # evaluation time with an actionable message instead of fetching an x86_64
  # archive into an aarch64 store path.
  src = fetchurl (
    prebuilt.${stdenv.hostPlatform.system}.uiDevelopment
      or (throw "denial-ui-development: upstream publishes no prebuilt toolchain for ${stdenv.hostPlatform.system}")
  );

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
    # This archive bundles a prebuilt Flutter SDK, which is BSD-3-Clause, on
    # top of Denial's own GPL-3+ code. Both have to be declared for the
    # license set downstream sees to be accurate.
    license = with lib.licenses; [ gpl3Plus bsd3 ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    hydraPlatforms = [ ];
  };
})
