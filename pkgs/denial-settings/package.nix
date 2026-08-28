{
  lib,
  stdenv,
  fetchurl,
  zstd,
  makeWrapper,
  glib,
  gtk3,
  libepoxy,
  pango,
  cairo,
  atk,
  gdk-pixbuf,
  libglvnd,
}:

let
  prebuilt = import ../prebuilt-hashes.nix;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "denial-settings";
  version = import ../version.nix;

  src = fetchurl {
    inherit (prebuilt.denial) url hash;
  };

  nativeBuildInputs = [ zstd makeWrapper ];

  setSourceRoot = "sourceRoot=.";

  unpackPhase = ''
    runHook preUnpack
    tar -I zstd -xf "$src" usr/lib/denial/settings usr/share/applications/dev.denial.Settings.desktop 2>/dev/null || tar -I zstd -xf "$src" usr/lib/denial/settings
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/denial" "$out/bin" "$out/share/applications"
    cp -a usr/lib/denial/settings "$out/lib/denial/"
    ln -s ../lib/denial/settings/denial-settings "$out/bin/denial-settings"
    if [ -f usr/share/applications/dev.denial.Settings.desktop ]; then
      install -Dm444 usr/share/applications/dev.denial.Settings.desktop \
        "$out/share/applications/dev.denial.Settings.desktop"
    fi
    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/denial-settings" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
        glib gtk3 libepoxy pango cairo atk gdk-pixbuf libglvnd
      ]}"
  '';

  dontStrip = true;

  meta = {
    description = "Denial Settings application (GTK Flutter bundle)";
    homepage = "https://github.com/denialwm/denial";
    changelog = "https://github.com/denialwm/denial/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    hydraPlatforms = [ ];
  };
})
