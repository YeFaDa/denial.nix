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
let
  prebuilt = import ../prebuilt-hashes.nix;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "denial-flutter-shell";
  version = import ../version.nix;

  # Upstream ships the shell inside the main compositor archive, hence the
  # `denial` entry. Looked up per platform rather than selected with an `if`:
  # on a platform upstream publishes nothing for, this throws at evaluation
  # time instead of fetching an x86_64 archive into an aarch64 store path.
  src = fetchurl (
    prebuilt.${stdenv.hostPlatform.system}.denial
      or (throw "denial-flutter-shell: upstream publishes no prebuilt shell for ${stdenv.hostPlatform.system}; set useSource = true to build from source")
  );

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
