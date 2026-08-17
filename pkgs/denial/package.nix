{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  installShellFiles,
  makeWrapper,
  pkg-config,

  # Libraries linked by the compositor (Smithay KMS backends).
  libgbm,
  libinput,
  libxkbcommon,
  seatd,
  systemd, # libudev

  # Libraries the compositor loads with dlopen() at runtime. They are not
  # referenced at link time, but being buildInputs puts them on the RUNPATH
  # of deniald so the dynamic linker resolves the dlopen() calls.
  libglvnd, # libEGL.so.1        - Smithay GL renderer
  wayland, # libwayland-server.so - Wayland frontend
  libpulseaudio, # libpulse.so.0    - audio controls
  pam, # libpam.so.0       - session unlock authentication
  ddcutil, # libddcutil.so.5   - external display controls

  # Tools required on PATH by the packaged session launcher and the shell.
  bash,
  coreutils,
  xwayland,
  zenity,

  denial-flutter-engine,
  denial-flutter-shell,
}:

# Packaging model (mirrors niri's nixpkgs package for the Rust part):
#
#  - deniald / denialctl are built from source with cargo, exactly like the
#    upstream release does (`cargo build --locked --release --features flutter
#    --bin deniald --bin denialctl`, see tools/denial-pc).
#
#  - The Dart shell (libapp.so AOT snapshot + flutter_assets) and the forked
#    Flutter engine can only be produced by the Flutter SDK fork pinned in
#    prebuilt/flutter-tools/3.44.7, which nixpkgs cannot build. They are
#    packaged separately as prebuilt artifacts (denial-flutter-shell and
#    denial-flutter-engine) and linked into this package's runtime bundle.
#    deniald checks the engine fingerprint of the bundle at startup, so the
#    three packages must stay on the same release.
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "denial";
  version = import ../version.nix;

  src = fetchFromGitHub {
    owner = "denialwm";
    repo = "denial";
    tag = "v${finalAttrs.version}";
    hash = "sha256-PFpVj9dwkU1NZfE3+po1yyA6d/tQrpXQDsLPEjWBNAc=";
  };

  # The cargo workspace lives in compositor/: cargoRoot places the vendored
  # dependencies and lockfile, buildAndTestSubdir makes the build/install
  # hooks run cargo there.
  cargoRoot = "compositor";
  buildAndTestSubdir = "compositor";
  # Identical to compositor/Cargo.lock at the release tag; vendored here so
  # the build does not depend on the source tree's copy. Smithay and
  # smithay-drm-extras are pinned as git dependencies of the same revision,
  # so they share one fetchgit hash.
  cargoLock = {
    lockFile = ./Cargo.lock;
    outputHashes = {
      "smithay-0.7.0" = "sha256-Dov9wh6qGuciLMTwOXM/eRA/Uo4jSvhcCqwJFdB2Vbg=";
      "smithay-drm-extras-0.1.0" = "sha256-Dov9wh6qGuciLMTwOXM/eRA/Uo4jSvhcCqwJFdB2Vbg=";
    };
  };

  strictDeps = true;

  nativeBuildInputs = [
    installShellFiles
    makeWrapper
    pkg-config
  ];

  buildInputs = [
    libgbm
    libinput
    libxkbcommon
    seatd
    systemd

    libglvnd
    wayland
    libpulseaudio
    pam
    ddcutil
  ];

  # Matches upstream's release build: the "flutter" feature pulls in the
  # kms, control and wire features required by deniald and denialctl.
  buildFeatures = [ "flutter" ];

  # The compositor test suite drives real DRM/KMS devices.
  doCheck = false;

  postPatch = ''
    patchShebangs packaging/arch/denial-session

    # The launcher reads the system output-configuration template when it
    # initializes a user's copy; /etc is not populated on non-NixOS use of
    # this package, so point it at the packaged template instead.
    substituteInPlace packaging/arch/denial-session \
      --replace-fail '/etc/denial/outputs.conf' "${lib.placeholder "out"}/share/denial/outputs.conf"

    substituteInPlace packaging/arch/denial.desktop \
      --replace-fail '/usr/bin/denial-session' "${lib.placeholder "out"}/bin/denial-session"
  '';

  # The cc-wrapper prunes RUNPATH entries of buildInputs that are never
  # linked, so libraries loaded with dlopen() must also be force-linked
  # (like niri does for libEGL) to stay resolvable by soname.
  env = {
    RUSTFLAGS = toString (
      map (arg: "-C link-arg=" + arg) [
        "-Wl,--push-state,--no-as-needed"
        "-lEGL" # Smithay GL renderer
        "-lwayland-server" # Wayland frontend (dlopen'd unversioned)
        "-lpulse" # audio controls
        "-lpam" # lock-screen authentication
        "-lddcutil" # external display controls
        "-Wl,--pop-state"
      ]
    );
  };

  postInstall = ''
    # Flutter runtime bundle assembled at the location the session launcher
    # derives from its own prefix ($prefix/lib/denial/flutter). Every member
    # is a symlink into the prebuilt component packages:
    #   lib/libapp.so + data/flutter_assets          <- denial-flutter-shell
    #   lib/libflutter_engine.so + data/icudtl.dat   <- denial-flutter-engine
    bundle="$out/lib/denial/flutter"
    mkdir -p "$bundle/lib" "$bundle/data"

    ln -s "${lib.getLib denial-flutter-shell}/lib/denial/flutter/lib/libapp.so" \
      "$bundle/lib/libapp.so"
    ln -s "${lib.getLib denial-flutter-shell}/lib/denial/flutter/data/flutter_assets" \
      "$bundle/data/flutter_assets"
    ln -s "${lib.getLib denial-flutter-engine}/lib/denial/flutter/lib/libflutter_engine.so" \
      "$bundle/lib/libflutter_engine.so"
    ln -s "${lib.getLib denial-flutter-engine}/lib/denial/flutter/data/icudtl.dat" \
      "$bundle/data/icudtl.dat"

    install -Dm555 packaging/arch/denial-session "$out/bin/denial-session"
    wrapProgram "$out/bin/denial-session" \
      --prefix PATH : "${lib.makeBinPath [
        bash
        coreutils
        systemd
        xwayland
        zenity
      ]}"

    install -Dm644 packaging/arch/denial.desktop \
      "$out/share/wayland-sessions/denial.desktop"
    install -Dm644 packaging/denial-session.target \
      "$out/lib/systemd/user/denial-session.target"
    install -Dm644 packaging/arch/denial-portals.conf \
      "$out/share/xdg-desktop-portal/denial-portals.conf"
    install -Dm644 packaging/arch/xdg-desktop-portal-wlr-Denial \
      "$out/share/xdg-desktop-portal-wlr/Denial"
    install -Dm644 packaging/arch/outputs.conf packaging/arch/session.conf \
      -t "$out/share/denial"

    installManPage docs/man/deniald.1 docs/man/denialctl.1 docs/man/denial-session.1

    install -Dm644 README.md -t "$out/share/doc/${finalAttrs.pname}"
    install -Dm644 LICENSE LICENSES/*.txt \
      dart_shell/assets/fonts/OFL.txt \
      -t "$out/share/licenses/${finalAttrs.pname}"
  '';

  passthru = {
    providedSessions = [ "denial" ];
    inherit denial-flutter-engine denial-flutter-shell;
  };

  meta = {
    description = "Flutter-native Wayland compositor and desktop shell";
    homepage = "https://github.com/denialwm/denial";
    changelog = "https://github.com/denialwm/denial/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [
      gpl3Plus # compositor
      cc-by-sa-40 # bundled wallpapers and cursor assets
      ofl # bundled JetBrains Mono
    ];
    mainProgram = "deniald";
    platforms = [ "x86_64-linux" ]; # prebuilt shell bundle is x86-64 only
    sourceProvenance = with lib.sourceTypes; [
      binaryNativeCode # Flutter engine and AOT shell from the release payload
    ];
    hydraPlatforms = [ ];
    maintainers = [ ];
  };
})
