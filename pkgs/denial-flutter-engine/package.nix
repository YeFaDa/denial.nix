{
  lib,
  stdenv,
  fetchurl,
  fontconfig,
  patchelf,
  zstd,
}:

# Denial embeds a fork of the Flutter engine (Flutter 3.44.7) whose sources
# are locked in prebuilt/flutter-engine/SOURCE_LOCK.json of the denial
# repository. Rebuilding
# it requires the full Chromium depot_tools/GN/Ninja toolchain of that fork,
# so this package consumes the artifact published in the upstream release
# instead. The compositor verifies the engine's SHA-256 fingerprint of the
# runtime bundle at startup, so this artifact must stay coupled to the denial
# package version.
stdenv.mkDerivation (finalAttrs: {
  pname = "denial-flutter-engine";
  version = import ../version.nix;

  src = fetchurl {
    # Upstream names the artifact with Arch's epoch prefix: epoch 1 +
    # version 0.2.10 => denial-flutter-engine-1.0.2.10-1-x86_64.pkg.tar.zst
    url = "https://github.com/denialwm/denial/releases/download/v${finalAttrs.version}/denial-flutter-engine-1.${finalAttrs.version}-1-x86_64.pkg.tar.zst";
    hash = "sha256-sNcM8UlBeJYbfb51ehOJWQTgOnJmEHUCUYMoO+Plfw0=";
  };

  nativeBuildInputs = [
    patchelf
    zstd
  ];

  # The engine resolves system fonts through libfontconfig.so.1, which the
  # prebuilt library cannot find without a RUNPATH on NixOS.
  buildInputs = [ fontconfig ];

  # Upstream release payload: a single Arch package.
  setSourceRoot = "sourceRoot=.";

  unpackPhase = ''
    runHook preUnpack
    tar -I zstd -xf "$src"
    runHook postUnpack
  '';

  buildPhase = ''
    runHook preBuild
    patchelf --set-rpath "${lib.makeLibraryPath [ fontconfig ]}" \
      usr/lib/denial/flutter/lib/libflutter_engine.so
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Layout expected by deniald's --flutter-bundle directory:
    #   lib/libflutter_engine.so, data/icudtl.dat
    install -Dm555 usr/lib/denial/flutter/lib/libflutter_engine.so \
      "$out/lib/denial/flutter/lib/libflutter_engine.so"
    install -Dm444 usr/lib/denial/flutter/data/icudtl.dat \
      "$out/lib/denial/flutter/data/icudtl.dat"

    # Provenance metadata shipped by upstream.
    install -Dm444 -t "$out/share/denial/flutter-engine" \
      usr/share/denial/flutter-engine/*
    install -Dm444 -t "$out/share/doc/${finalAttrs.pname}" \
      usr/share/doc/denial-flutter-engine/BUILD_INFO.md
    install -Dm444 -t "$out/share/licenses/${finalAttrs.pname}" \
      usr/share/licenses/denial-flutter-engine/LICENSE.*

    runHook postInstall
  '';

  dontStrip = true;

  meta = {
    description = "Prebuilt Flutter engine runtime for the Denial compositor (locked Flutter 3.44.7 fork)";
    homepage = "https://github.com/denialwm/denial";
    changelog = "https://github.com/denialwm/denial/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    hydraPlatforms = [ ];
  };
})
