{
  lib,
  stdenv,
  fontconfig,
  gclient2nix,
  gn,
  ninja,
  pkg-config,
  python3,
  patchelf,
  git,
  llvmPackages_21,
  dartSdk,
  glib,
  gtk3,
  libdrm,
  libepoxy,
  libx11,
  libxkbcommon,
  mesa,
  pango,
  wayland,
  zlib,
}:

let
  version = import ../version.nix;
  llvmPackages = llvmPackages_21;
  hostCpu =
    if stdenv.hostPlatform.isx86_64 then "x64"
    else if stdenv.hostPlatform.isAarch64 then "arm64"
    else throw "unsupported host platform: ${stdenv.hostPlatform.system}";
  gclientDeps = gclient2nix.importGclientDeps ./gclient-deps.json;
in
stdenv.mkDerivation (finalAttrs: {
  pname = "denial-flutter-engine-source";
  inherit version gclientDeps;
  sourceRoot = "engine/src";
  outputs = [ "out" "dev" ];
  dontConfigure = true;
  dontStrip = true;
  strictDeps = true;

  nativeBuildInputs = [
    gclient2nix.gclientUnpackHook
    git
    gn
    llvmPackages.bintools
    llvmPackages.clang
    llvmPackages.lld
    ninja
    patchelf
    pkg-config
    python3
  ];

  buildInputs = [
    fontconfig
    glib
    gtk3
    libdrm
    libepoxy
    libx11
    libxkbcommon
    mesa
    pango
    wayland
    zlib
  ];

  postUnpack = ''
    mkdir -p engine/src/flutter/buildtools/linux-${hostCpu}/clang/bin
    for tool in clang clang++ llvm-ar llvm-cov llvm-nm llvm-objcopy llvm-ranlib llvm-readelf llvm-size llvm-strip; do
      for root in ${llvmPackages.clang} ${llvmPackages.llvm} ${llvmPackages.lld}; do
        if [ -x "$root/bin/$tool" ]; then
          ln -sf "$root/bin/$tool" "engine/src/flutter/buildtools/linux-${hostCpu}/clang/bin/$tool"
          break
        fi
      done
    done
  '';

  postPatch = ''
    cd flutter
    patchShebangs tools/gn
    for repository in . third_party/skia third_party/dart; do
      git -C "$repository" init --initial-branch=nixpkgs
      GIT_AUTHOR_NAME=Nixpkgs GIT_COMMITTER_NAME=Nixpkgs \
        GIT_AUTHOR_EMAIL= GIT_COMMITTER_EMAIL= \
        GIT_AUTHOR_DATE='1/1/1970 00:00:00 +0000' \
        GIT_COMMITTER_DATE='1/1/1970 00:00:00 +0000' \
        git -C "$repository" commit --allow-empty --message='Initial source snapshot'
    done

    mkdir -p third_party/gn
    ln -sf ${gn}/bin/gn third_party/gn/gn
    mkdir -p third_party/dart/build/config third_party/dart/tools/sdks
    printf 'checkout_llvm = false\n' > third_party/dart/build/config/gclient_args.gni
    ln -sf ${dartSdk} third_party/dart/tools/sdks/dart-sdk
    mkdir -p prebuilts/linux-${hostCpu}
    ln -sf ${dartSdk} prebuilts/linux-${hostCpu}/dart-sdk
    substituteInPlace tools/gn \
      --replace-fail "revision_args['content_hash'] = get_content_hash()" \
        "revision_args['content_hash'] = 'b20ca326b99f27e33a416ba684333b2a20f711a9'"
    cd ../..
  '';

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    buildRoot="$TMPDIR/denial-flutter-engine-build"
    python3 ./engine/src/flutter/tools/gn \
      --runtime-mode=release \
      --enable-fontconfig \
      --prebuilt-dart-sdk \
      --no-default-linux-sysroot \
      --no-full-dart-sdk \
      --out-dir="$buildRoot" \
      --target-dir=denial_host_release \
      ${lib.optionalString stdenv.hostPlatform.isAarch64 "--target-os=linux --linux-cpu=arm64"}
    ${ninja}/bin/ninja -C "$buildRoot/out/denial_host_release" -j"$NIX_BUILD_CORES" \
      libflutter_engine.so gen_snapshot libflutter_linux_gtk.so
    output="$buildRoot/out/denial_host_release"
    test -f "$output/libflutter_engine.so"
    test -x "$output/gen_snapshot"
  '';

  installPhase = ''
    runHook preInstall
    output="$TMPDIR/denial-flutter-engine-build/out/denial_host_release"
    install -Dm555 "$output/libflutter_engine.so" \
      "$out/lib/denial/flutter/lib/libflutter_engine.so"
    install -Dm444 "$output/icudtl.dat" \
      "$out/lib/denial/flutter/data/icudtl.dat"
    patchelf --set-rpath "${lib.makeLibraryPath [ fontconfig ]}" \
      "$out/lib/denial/flutter/lib/libflutter_engine.so"
    mkdir -p "$dev/engine-build" "$dev/flutter"
    cp -a "$TMPDIR/denial-flutter-engine-build/." "$dev/engine-build/"
    cp -a engine/src/flutter/. "$dev/flutter/"
    install -Dm755 "$output/gen_snapshot" "$dev/gen_snapshot"
    install -Dm444 engine/src/flutter/LICENSE \
      "$out/share/licenses/${finalAttrs.pname}/LICENSE"
    runHook postInstall
  '';

  passthru = {
    inherit dartSdk;
    localEngine = "denial_host_release";
    localEngineSrcPath = "${placeholder "dev"}/engine-build";
  };

  meta = {
    description = "Denial Flutter engine built from its locked Flutter and Skia sources";
    homepage = "https://github.com/denialwm/flutter";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
