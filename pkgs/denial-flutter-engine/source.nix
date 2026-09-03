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
  revisions,

  # Which Flutter runtime mode to build: "release", "debug" or "profile".
  #
  # Upstream commits one `args.gn` per mode under
  # `prebuilt/flutter-engine/linux-x64-<mode>/` and they differ in exactly two
  # lines (`flutter_runtime_mode` and `dart_runtime_mode`), so one derivation
  # parameterised on the mode covers all three instead of carrying a second
  # copy of the build logic. The ninja target list differs more substantially
  # and is picked from the table below.
  #
  # Left at "release" so the shell and settings packages keep resolving the
  # store paths they have always resolved.
  runtimeMode ? "release",
}: 

let
  version = import ../version.nix;
  llvmPackages = llvmPackages_21;

  # GN's output directory name. Upstream spells it the same way in
  # `tools/denial-flutter-engine`; consumers resolve it through
  # `passthru.localEngine` rather than hardcoding it.
  target = "denial_host_${runtimeMode}";

  # Upstream runs two commands over this engine tree and each asks for a
  # different set of ninja targets: `build` compiles `libflutter_engine.so`
  # in every mode (the compositor embeds the release one, and the UI
  # development toolchain ships the debug and profile ones under
  # `ui-development/{lib,profile}/`), while `prepare-development-sdk`
  # compiles the tree a live UI workspace reads (a full Dart SDK, the
  # Impeller compiler, const_finder, the Linux embedder headers, and the
  # profile tree's AOT compiler and GTK engine).
  #
  # Both lists are folded into one per mode so a single build of a mode yields
  # everything that mode is ever asked for. The release list is the historical
  # one and must not change: it is what the shell and settings packages were
  # built against.
  ninjaTargets = {
    release = [
      "dart_sdk"
      "flutter_patched_sdk/platform_strong.dill"
      "libflutter_engine.so"
      "gen_snapshot"
      "libflutter_linux_gtk.so"
      "flutter/shell/platform/linux:publish_headers_linux"
      "flutter/tools/font_subset:font_subset"
    ];
    debug = [
      "dart_sdk"
      "flutter_patched_sdk/platform_strong.dill"
      "libflutter_engine.so"
      "flutter/shell/platform/linux:publish_headers_linux"
      "flutter/tools/const_finder:const_finder"
      "flutter/tools/font_subset:font_subset"
      "impellerc"
    ];
    profile = [
      "libflutter_engine.so"
      "gen_snapshot"
      "libflutter_linux_gtk.so"
    ];
  }."${runtimeMode}" or (throw "denial-flutter-engine-source: unknown runtimeMode '${runtimeMode}'");

  # Mirrors the `[[ -x ... ]]` checks upstream runs after ninja. The release
  # pair is the one that existed before; the others are what
  # `prepare-development-sdk` verifies.
  devAssertions = {
    release = [
      "gen_snapshot"
      "libflutter_linux_gtk.so"
      "flutter_linux"
      "flutter_patched_sdk/platform_strong.dill"
    ];
    debug = [
      "dart-sdk/bin/dart"
      "flutter_patched_sdk/platform_strong.dill"
      "flutter_linux/flutter_linux.h"
      "gen/const_finder.dart.snapshot"
      "font-subset"
      "impellerc"
      "gen/dart-pkg/sky_engine/lib/_embedder.yaml"
    ];
    profile = [
      "gen_snapshot"
      "libflutter_linux_gtk.so"
    ];
  }."${runtimeMode}" or (throw "denial-flutter-engine-source: unknown runtimeMode '${runtimeMode}'");

  # Shared with flutter-tools, the shell and the settings app. This was
  # previously called `hostCpu` and held only the CPU part, but every use site
  # prefixed it with `linux-` again; take the full platform name directly.
  flutterArch = import ../flutter-arch.nix { system = stdenv.hostPlatform.system; };
  devtoolsSharedDetails = (lib.importJSON ./flutter-tools-pubspec.lock.json).packages.devtools_shared;
  devtoolsShared = fetchurl {
    url = "${devtoolsSharedDetails.description.url}/api/archives/${devtoolsSharedDetails.description.name}-${devtoolsSharedDetails.version}.tar.gz";
    sha256 = devtoolsSharedDetails.description.sha256;
  };


  gclientDeps = gclient2nix.importGclientDeps ./gclient-deps.json;
in
stdenv.mkDerivation (finalAttrs: {
  # The release build keeps its historical name; a name change would change
  # its store path and invalidate every cache entry built against it. The
  # other modes carry the mode so `nix store ls`-style listings stay readable.
  pname =
    if runtimeMode == "release" then
      "denial-flutter-engine-source"
    else
      "denial-flutter-engine-${runtimeMode}-source";
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
    mkdir -p engine/src/flutter/buildtools/${flutterArch.platform}/clang/bin
    for tool in clang clang++ llvm-ar llvm-cov llvm-nm llvm-objcopy llvm-ranlib llvm-readelf llvm-size llvm-strip; do
      for root in ${llvmPackages.clang} ${llvmPackages.llvm} ${llvmPackages.lld}; do
        if [ -x "$root/bin/$tool" ]; then
          ln -sf "$root/bin/$tool" "engine/src/flutter/buildtools/${flutterArch.platform}/clang/bin/$tool"
          break
        fi
      done
    done
  '';

  postPatch = ''
    cd flutter
    patchShebangs tools/gn

    mkdir -p third_party/gn third_party/dart/build/config third_party/dart/tools/sdks
    printf '%s\n' ${revisions.dart} \
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
    mkdir -p prebuilts/${flutterArch.platform}
    ln -sf ${dart} prebuilts/${flutterArch.platform}/dart-sdk

    rm -f third_party/depot_tools/vpython3
    cat > third_party/depot_tools/vpython3 <<EOF
#!${stdenv.shell}
exec ${python3}/bin/python3 "\$@"
EOF
    chmod 755 third_party/depot_tools/vpython3

    # Upstream wraps the ATK include in `extern "C"`. Because the wrapper is
    # opened *before* the include, it drags the whole include closure into C
    # linkage: atk.h -> atkversion.h -> glib.h -> gatomic.h -> glib-typeof.h,
    # which pulls in <type_traits>. C++ forbids template declarations inside
    # an `extern "C"` block, so the build dies with
    # "error: template with C linkage". Dropping the wrapper keeps the symbols
    # unmangled, which is what ATK wants anyway.
    #
    # Matched on content rather than line numbers: the previous
    # `sed -i '7,9c...'` silently retargeted itself whenever upstream edited
    # anything above this block. `--replace-fail` turns that into a build
    # error instead.
    #
    # No `if [ -f ... ]` guard on purpose: if upstream moves or renames this
    # file we want a hard failure, not a silently skipped patch.
    substituteInPlace shell/platform/linux/fl_view_accessible.cc \
      --replace-fail 'extern "C" {
#include <atk/atk.h>
}' '#include <atk/atk.h>'
    substituteInPlace tools/gn \
      --replace-fail "revision_args['engine_version'] = get_repository_version(engine_path)" \
        "revision_args['engine_version'] = '${revisions.flutter}'" \
      --replace-fail "revision_args['content_hash'] = get_content_hash()" \
        "revision_args['content_hash'] = '${revisions.flutter}'" \
      --replace-fail "revision_args['skia_version'] = get_repository_version(skia_path)" \
        "revision_args['skia_version'] = '${revisions.skia}'" \
      --replace-fail "revision_args['dart_version'] = get_repository_version(get_dart_path())" \
        "revision_args['dart_version'] = '${revisions.dart}'"
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
    (cd flutter/third_party/dart && ${dart}/bin/dart pub get --offline)
    (cd flutter && ${dart}/bin/dart pub get --offline)

    python3 ./flutter/tools/gn \
      --runtime-mode=${runtimeMode} \
      --enable-fontconfig \
      --no-default-linux-sysroot \
      --out-dir="$buildRoot" \
      --target-dir=${target} \
      --gn-args='pkg_config="${pkg-config}/bin/pkg-config"' \
      --gn-args='host_pkg_config="${pkg-config}/bin/pkg-config"' \
      # GN infers these from the host, which lands correctly on x86_64;
      # aarch64 needs them spelled out. The `isAarch64` test stays a condition
      # rather than a table lookup because this is a difference in build
      # behaviour, not in naming -- but the value comes from the shared table,
      # so no arch name is hardcoded outside pkgs/flutter-arch.nix.
      ${lib.optionalString stdenv.hostPlatform.isAarch64 "--target-os=linux --linux-cpu=${flutterArch.cpu}"}

    ${ninja}/bin/ninja -C "$buildRoot/out/${target}" -j"''${NIX_BUILD_CORES:-1}" \
      ${lib.concatStringsSep " " ninjaTargets}

    output="$buildRoot/out/${target}"
    # Every mode builds this: release embeds it into the compositor and the
    # other two ship inside `denial-ui-development-source`. The mode-specific
    # trees are checked in installPhase against the `devAssertions` table.
    test -f "$output/libflutter_engine.so"
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    output="$TMPDIR/denial-flutter-engine-build/out/${target}"

    # Only the release build produces a runtime library. The debug and profile
    # trees exist for `denial-ui-development-source`, which reads them through
    # `dev` and never links against them, so their `out` is left empty rather
    # than carrying a library nothing would load.
    ${lib.optionalString (runtimeMode == "release") ''
      install -Dm555 "$output/libflutter_engine.so" \
        "$out/lib/denial/flutter/lib/libflutter_engine.so"
      install -Dm444 "$output/icudtl.dat" \
        "$out/lib/denial/flutter/data/icudtl.dat"
      chmod u+w "$out/lib/denial/flutter/lib/libflutter_engine.so"
      # --add-rpath, not --set-rpath: this library is built here and already
      # carries a RUNPATH from the GN/Ninja build. Overwriting it would drop
      # those entries and only leave fontconfig behind.
      patchelf --add-rpath "${lib.makeLibraryPath [ fontconfig ]}" \
        "$out/lib/denial/flutter/lib/libflutter_engine.so"
    ''}

    # Leaves `out` empty, which `nix build` accepts silently and which reads as
    # a broken package to anyone who tries it. Say where the payload went.
    ${lib.optionalString (runtimeMode != "release") ''
      mkdir -p "$out/share/doc/${finalAttrs.pname}"
      printf '%s\n' \
        "The artifacts of this build live in the dev output, under" \
        "engine-build/out/${target} -- including libflutter_engine.so." \
        "" \
        "The out output exists for the release build's runtime library," \
        "which the compositor embeds. This mode's engine serves" \
        "denial-ui-development-source, which reads it from dev, so out" \
        "carries nothing to install." \
        > "$out/share/doc/${finalAttrs.pname}/OUTPUTS.md"
    ''}

    mkdir -p "$dev/engine-build/out"
    cp -a "$output" "$dev/engine-build/out/${target}"
    # Driven by the `devAssertions` table rather than spelled out per mode, so
    # adding a mode means adding one list entry instead of another block of
    # `test` calls here.
    for artifact in ${lib.concatStringsSep " " devAssertions}; do
      test -e "$dev/engine-build/out/${target}/$artifact" \
        || (echo "missing $artifact in ${runtimeMode} dev output" >&2; exit 1)
    done

    mkdir -p "$dev/flutter/sky/packages" "$dev/flutter/lib"
    cp -a flutter/sky/packages/sky_engine "$dev/flutter/sky/packages/"
    # `flutter_gpu`, the package backing `dart:ui`'s GPU API. No `|| true`:
    # the directory is present in the locked revision (verified against
    # `engine/src/flutter/lib/gpu/pubspec.yaml`), and if upstream moves or
    # renames it we want the build to fail here rather than hand
    # `denial-ui-development-source` a silently incomplete dev tree.
    cp -a flutter/lib/gpu "$dev/flutter/lib/"
    install -Dm444 flutter/LICENSE "$dev/flutter/LICENSE"
    runHook postInstall
  '';

  passthru = {
    inherit dart runtimeMode;
    localEngine = target;
    localEngineSrcPath = "${placeholder "dev"}/engine-build";
  };

  meta = {
    description = "Denial Flutter engine (${runtimeMode}) built from its locked Flutter and Skia sources";
    homepage = "https://github.com/denialwm/flutter";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
