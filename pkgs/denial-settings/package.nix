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
  denialSettingsSource ? null,
  useSource ? false,
}:

let
  prebuilt = import ../prebuilt-hashes.nix;
in
assert !useSource || denialSettingsSource != null;
if useSource then denialSettingsSource else stdenv.mkDerivation (finalAttrs: {
  pname = "denial-settings";
  version = import ../version.nix;

  # Upstream ships the settings bundle inside the main compositor archive,
  # hence the `denial` entry. Looked up per platform rather than selected with
  # an `if`: on a platform upstream publishes nothing for, this throws at
  # evaluation time instead of fetching an x86_64 archive into an aarch64
  # store path. Only reached when useSource is false.
  src = fetchurl (
    prebuilt.${stdenv.hostPlatform.system}.denial
      or (throw "denial-settings: upstream publishes no prebuilt settings bundle for ${stdenv.hostPlatform.system}; build the -source variant instead")
  );

  nativeBuildInputs = [ zstd makeWrapper ];

  setSourceRoot = "sourceRoot=.";

  unpackPhase = ''
    runHook preUnpack
    # Upstream only started shipping the desktop entry in 0.2.x, so older
    # archives do not carry it. Ask the archive which members it has rather
    # than attempting the two-member extract and falling back on failure:
    # tar exits 2 when a requested member is missing *even though it already
    # extracted the others*, which made the old form extract `settings` twice
    # and, with stderr discarded, turn a corrupt download into a silent
    # downgrade that only surfaced later as a confusing `cp` failure.
    if tar -I zstd -tf "$src" usr/share/applications/dev.denial.Settings.desktop >/dev/null 2>&1; then
      tar -I zstd -xf "$src" \
        usr/lib/denial/settings \
        usr/share/applications/dev.denial.Settings.desktop
    else
      tar -I zstd -xf "$src" usr/lib/denial/settings
    fi
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
