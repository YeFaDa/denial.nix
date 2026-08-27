{
  lib,
  stdenv,
  fetchurl,
  fontconfig,
  gclient2nix,
  gn,
  ninja,
  pkg-config,
  python3,
  patchelf,
  git,
  llvmPackages_21,
  glib,
  gtk3,
  libdrm,
  libepoxy,
  libx11,
  libxkbcommon,
  mesa,
  pango,
  unzip,
  wayland,
  zlib,
  dart,
}: 

let
  version = import ../version.nix;
  llvmPackages = llvmPackages_21;
  hostCpu =
    if stdenv.hostPlatform.isx86_64 then "x64"
    else if stdenv.hostPlatform.isAarch64 then "arm64"
    else throw "unsupported host platform: ${stdenv.hostPlatform.system}";
  devtoolsShared = fetchurl {
    url = "https://pub.dev/api/archives/devtools_shared-12.1.0.tar.gz";
    hash = "sha256-La96n7pqRwZosm7L0EIA97+ZKq2BosMdEkV8d5FBneo=";
  };


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

    mkdir -p third_party/gn third_party/dart/build/config third_party/dart/tools/sdks
    printf '%s\n' d684a576a6aa954ae107a03b2b4e1d61c3bebe93 \
      > third_party/dart/tools/GIT_REVISION
    python3 - <<'PY'
from pathlib import Path

path = Path("third_party/dart/tools/utils.py")
text = path.read_text()
old = "def GetShortGitHash(repo_path=DART_DIR):\n"
new = (
    "def GetShortGitHash(repo_path=DART_DIR):\n"
    "    revision = GetGitRevision(repo_path=repo_path)\n"
    "    if revision is not None:\n"
    "        return revision[:10]\n"
)
if text.count(old) != 1:
    raise SystemExit("GetShortGitHash definition not found exactly once")
path.write_text(text.replace(old, new, 1))
PY
    ln -sf ${gn}/bin/gn third_party/gn/gn
    printf 'checkout_llvm = false\n' > third_party/dart/build/config/gclient_args.gni
    ln -sf ${dart} third_party/dart/tools/sdks/dart-sdk
    mkdir -p prebuilts/linux-${hostCpu}
    ln -sf ${dart} prebuilts/linux-${hostCpu}/dart-sdk

    rm -f third_party/depot_tools/vpython3
    cat > third_party/depot_tools/vpython3 <<EOF
#!${stdenv.shell}
exec ${python3}/bin/python3 "\$@"
EOF
    chmod 755 third_party/depot_tools/vpython3

    if [ -f shell/platform/linux/fl_view_accessible.cc ]; then
      sed -i '7,9c#include <atk/atk.h>' shell/platform/linux/fl_view_accessible.cc
    fi

    substituteInPlace tools/gn \
      --replace-fail "revision_args['engine_version'] = get_repository_version(engine_path)" \
        "revision_args['engine_version'] = 'b20ca326b99f27e33a416ba684333b2a20f711a9'" \
      --replace-fail "revision_args['content_hash'] = get_content_hash()" \
        "revision_args['content_hash'] = 'b20ca326b99f27e33a416ba684333b2a20f711a9'" \
      --replace-fail "revision_args['skia_version'] = get_repository_version(skia_path)" \
        "revision_args['skia_version'] = '0ee042f542b3e79f5ac49115387718c6bb3d7d34'" \
      --replace-fail "revision_args['dart_version'] = get_repository_version(get_dart_path())" \
        "revision_args['dart_version'] = 'd684a576a6aa954ae107a03b2b4e1d61c3bebe93'"
    cd ..
  '';

  buildPhase = ''
    runHook preBuild
    export HOME="$TMPDIR/home"
    export PATH="$PWD/flutter/third_party/depot_tools:$PATH"
    export PYTHONPATH="$PWD/flutter/third_party/depot_tools:$PYTHONPATH"
    mkdir -p "$HOME"
    mkdir -p flutter/third_party/dart/third_party/devtools/devtools_shared
    tar -xzf "${devtoolsShared}" \
      -C flutter/third_party/dart/third_party/devtools/devtools_shared
    buildRoot="$TMPDIR/denial-flutter-engine-build"
    python3 ./flutter/tools/pub_get_offline.py
    (cd flutter/third_party/dart && ${dart}/bin/dart pub get --offline)
    (cd flutter && ${dart}/bin/dart pub get --offline)

    python3 ./flutter/tools/gn \
      --runtime-mode=release \
      --enable-fontconfig \
      --no-default-linux-sysroot \
      --out-dir="$buildRoot" \
      --target-dir=denial_host_release \
      --gn-args='pkg_config="${pkg-config}/bin/pkg-config"' \
      --gn-args='host_pkg_config="${pkg-config}/bin/pkg-config"' \
      ${lib.optionalString stdenv.hostPlatform.isAarch64 "--target-os=linux --linux-cpu=arm64"}

    ${ninja}/bin/ninja -C "$buildRoot/out/denial_host_release" -j19 \
      dart_sdk \
      flutter_patched_sdk/platform_strong.dill \
      libflutter_engine.so gen_snapshot libflutter_linux_gtk.so \
      flutter/shell/platform/linux:publish_headers_linux \
      flutter/tools/font_subset:font_subset

    output="$buildRoot/out/denial_host_release"
    test -f "$output/libflutter_engine.so"
    test -x "$output/gen_snapshot"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    output="$TMPDIR/denial-flutter-engine-build/out/denial_host_release"
    install -Dm555 "$output/libflutter_engine.so" \
      "$out/lib/denial/flutter/lib/libflutter_engine.so"
    install -Dm444 "$output/icudtl.dat" \
      "$out/lib/denial/flutter/data/icudtl.dat"
    chmod u+w "$out/lib/denial/flutter/lib/libflutter_engine.so"
    patchelf --set-rpath "${lib.makeLibraryPath [ fontconfig ]}" \
      "$out/lib/denial/flutter/lib/libflutter_engine.so"

    mkdir -p "$dev/engine-build" "$dev/flutter"
    cp -a "$TMPDIR/denial-flutter-engine-build/." "$dev/engine-build/"
    cp -a flutter/. "$dev/flutter/"
    install -Dm755 "$output/gen_snapshot" "$dev/gen_snapshot"
    cp -a "$output/dart-sdk" "$dev/engine-build/dart-sdk"
    cp -a "$output/flutter_patched_sdk" "$dev/engine-build/flutter_patched_sdk"
    cp -a "$output/gen" "$dev/engine-build/gen"
    install -Dm755 "$output/gen_snapshot" "$dev/gen_snapshot"
    install -Dm755 "$output/font-subset" "$dev/font-subset"
    install -Dm444 flutter/LICENSE "$out/share/licenses/${finalAttrs.pname}/LICENSE"
    runHook postInstall
  '';

  passthru = {
    inherit dart;
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
