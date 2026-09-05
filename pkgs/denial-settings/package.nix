{
  lib,
  stdenv,
  fetchurl,
  zstd,
  makeWrapper,
  patchelf,
  glib,
  gtk3,
  libepoxy,
  pango,
  cairo,
  atk,
  gdk-pixbuf,
  libglvnd,
  harfbuzz,
  zlib,
  fontconfig,
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

  nativeBuildInputs = [ zstd makeWrapper patchelf ];

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
      # Upstream's entry hardcodes /usr/bin, which does not exist on NixOS;
      # the source build already makes the same substitution, so the two
      # variants stay consistent.
      substituteInPlace "$out/share/applications/dev.denial.Settings.desktop" \
        --replace-fail /usr/bin/denial-settings "${lib.placeholder "out"}/bin/denial-settings"
    fi
    runHook postInstall
  '';

  postFixup = ''
    # Upstream builds this bundle for generic Linux: the runner's ELF
    # interpreter points at /lib64/ld-linux-x86-64.so.2, where NixOS mounts a
    # rejecting stub, and NixOS offers no ld.so.cache or default library
    # directories to fall back on. Point the interpreter at this stdenv's
    # loader and spell out every direct DT_NEEDED of the two prebuilt objects
    # in the LD_LIBRARY_PATH below — a missing entry is a startup failure,
    # not a degraded feature.
    chmod u+w "$out/lib/denial/settings/denial-settings"
    patchelf --set-interpreter "${stdenv.cc.bintools.dynamicLinker}" \
      "$out/lib/denial/settings/denial-settings"
    wrapProgram "$out/bin/denial-settings" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
        glib gtk3 libepoxy pango cairo atk gdk-pixbuf libglvnd
        harfbuzz zlib fontconfig stdenv.cc.cc.lib
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
