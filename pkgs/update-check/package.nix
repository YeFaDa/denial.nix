{
  lib,
  stdenv,
  makeBinaryWrapper,
  curl,
  jq,
  nix,
  coreutils,
  dart,
}: 

stdenv.mkDerivation (finalAttrs: let
  revisions = import ../denial-flutter-engine/revisions.nix { inherit lib; };
in {
  pname = "denial-update-check";
  version = import ../version.nix;
  currentFlutterRevision = revisions.flutter;
  currentDartVersion = dart.version;
  currentDartRevision = revisions.dart;
  currentSkiaRevision = revisions.skia;
  currentMaterialFontsVersion = revisions.materialFontsVersion;
  currentGradleWrapperVersion = revisions.gradleWrapperVersion;

  dontUnpack = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    substitute "${./update-check.sh}" "$out/bin/denial-update-check" \
      --replace-fail '@version@' '${finalAttrs.version}' \
      --replace-fail '@dart_version@' '${finalAttrs.currentDartVersion}' \
      --replace-fail '@flutter_revision@' '${finalAttrs.currentFlutterRevision}' \
      --replace-fail '@dart_revision@' '${finalAttrs.currentDartRevision}' \
      --replace-fail '@skia_revision@' '${finalAttrs.currentSkiaRevision}' \
      --replace-fail '@material_fonts_path@' '${finalAttrs.currentMaterialFontsVersion}' \
      --replace-fail '@gradle_wrapper_path@' '${finalAttrs.currentGradleWrapperVersion}'
    chmod +x "$out/bin/denial-update-check"
    wrapProgram "$out/bin/denial-update-check" \
      --prefix PATH : "${lib.makeBinPath [ curl jq nix coreutils ]}"
    runHook postInstall
  '';

  meta = {
    description = "Check for Denial updates and print fields to update";
    homepage = "https://github.com/denialwm/denial";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
    mainProgram = "denial-update-check";
  };
})
