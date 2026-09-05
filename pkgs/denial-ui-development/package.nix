{
  lib,
  stdenv,
  fetchurl,
  zstd,
  buildFHSEnv,

  # Direct DT_NEEDED of the payload's generic Linux ELFs (the launcher, the
  # SDK's dart, the engines). NixOS has no ld.so.cache or default library
  # directories to fall back on, so every soname the payload references must
  # be present in the FHS /usr/lib this environment builds its cache from.
  glib,
  gtk3,
  pango,
  cairo,
  atk,
  gdk-pixbuf,
  libepoxy,
  harfbuzz,
  zlib,
  fontconfig,
  libglvnd,
  mesa,

  # `flutter build linux` shells out to these. The upstream archive bundles
  # none of them and expects the distribution to provide them, so they run
  # inside the same environment.
  git,
  cmake,
  ninja,
  pkg-config,
  clang,
}:

let
  version = import ../version.nix;
  prebuilt = import ../prebuilt-hashes.nix;

  # The raw upstream payload: generic Linux ELFs (the `denial-ui` launcher,
  # the pinned Flutter 3.44.7 fork SDK, the debug and profile engines and the
  # Pub cache seed). Nothing here is patched: the launcher's compiled-in root
  # is /usr/lib/denial/ui-development, which the FHS tree below recreates, and
  # every writable path it touches (build root, Pub cache seed copies, staged
  # bundles) lives under the user's XDG cache, not in its own tree — so the
  # read-only store works exactly like a root-owned /usr does upstream.
  payload = stdenv.mkDerivation (finalAttrs: {
    pname = "denial-ui-development-payload";
    inherit version;

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
      runHook postInstall
    '';

    dontStrip = true;

    # Internal input of the FHS environment below; not a user-facing package.
    meta.platforms = [ "x86_64-linux" ];
  });
in
# The payload cannot run on NixOS directly: its ELFs carry a generic
# /lib64/ld-linux-x86-64.so.2 interpreter, where NixOS mounts a rejecting
# stub, and there is no ld.so.cache to resolve their sonames through.
# Wrapping the whole tree in an FHS environment is what makes it usable —
# individually patching an entire Flutter SDK (dart, gen_snapshot,
# flutter_tester, two engines) is not a realistic alternative. The
# environment recreates the FHS locations the launcher expects, provides the
# native toolchain `flutter build linux` shells out to, and leaves
# /run/opengl-driver reachable (bubblewrap binds /run wholesale) so GL works
# with the host's driver: buildFHSEnv already exports
# XDG_DATA_DIRS=/run/opengl-driver/share, which covers glvnd's vendor lookup.
buildFHSEnv {
  pname = "denial-ui-development";
  inherit version;

  # Keep upstream's CLI (`denial-ui COMMAND [WORKSPACE]`) as the entry point.
  executableName = "denial-ui";
  runScript = "/usr/bin/denial-ui";

  targetPkgs = pkgs: with pkgs; [
    glib
    gtk3
    pango
    cairo
    atk
    gdk-pixbuf
    libepoxy
    harfbuzz
    zlib
    fontconfig
    libglvnd
    mesa
    stdenv.cc.cc.lib # libstdc++.so.6, libgcc_s.so.1

    git
    cmake
    ninja
    pkg-config
    clang
  ];

  # extraBuildCommands runs outside the rootfs tree in this buildFHSEnv
  # backend, so every path here must be spelled through $out. The tree keeps
  # usr/lib as a usrmerge symlink to usr/lib64 (dangling in the build
  # sandbox), so the payload lands in usr/lib64 and stays reachable through
  # both paths at runtime — including the launcher's compiled-in
  # /usr/lib/denial/ui-development.
  extraBuildCommands = ''
    mkdir -p "$out/usr/bin" "$out/usr/lib64/denial"
    ln -s ${payload}/bin/denial-ui "$out/usr/bin/denial-ui"
    ln -s ${payload}/bin/denial-flutter "$out/usr/bin/denial-flutter"
    ln -s ${payload}/lib/denial/ui-development "$out/usr/lib64/denial/ui-development"
  '';

  passthru = {
    inherit payload;
  };

  meta = {
    description = "Prebuilt UI development toolchain for Denial (Flutter SDK + profile engine + pub cache), FHS-wrapped";
    homepage = "https://github.com/denialwm/denial";
    changelog = "https://github.com/denialwm/denial/releases/tag/v${version}";
    # This archive bundles a prebuilt Flutter SDK, which is BSD-3-Clause, on
    # top of Denial's own GPL-3+ code. Both have to be declared for the
    # license set downstream sees to be accurate.
    license = with lib.licenses; [ gpl3Plus bsd3 ];
    platforms = [ "x86_64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    hydraPlatforms = [ ];
  };
}
