{
  lib,
  stdenv,
  makeBinaryWrapper,
  curl,
  jq,
  nix,
  coreutils,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "denial-update-check";
  version = import ../version.nix;

  dontUnpack = true;

  nativeBuildInputs = [ makeBinaryWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin"
    substitute "${./update-check.sh}" "$out/bin/denial-update-check" \
      --replace-fail '@version@' '${finalAttrs.version}'
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
