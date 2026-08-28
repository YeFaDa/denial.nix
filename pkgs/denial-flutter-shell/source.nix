{
  lib,
  stdenv,
  fetchFromGitHub,
  buildDartApplication,
  dart,
  flutter,
  git,
  unzip,
  which,
  denial-flutter-engine-source,
  revisions,
  materialFonts,
  gradleWrapper,
}: 

let
  version = import ../version.nix;
  arch = if stdenv.hostPlatform.isx86_64 then "x64" else "arm64";
in
buildDartApplication.override { inherit dart; } (finalAttrs: {
  pname = "denial-flutter-shell-source";
  inherit version;
  pubspecLock = lib.importJSON ./pubspec.lock.json;
  sdkSourceBuilders = {
    flutter = name:
      stdenv.mkDerivation {
        pname = "denial-flutter-sdk-${name}";
        version = finalAttrs.version;
        dontUnpack = true;
        installPhase = ''
          mkdir -p "$out"
          if [ "${name}" = sky_engine ]; then
            cp -a "${denial-flutter-engine-source.dev}/flutter/sky/packages/sky_engine/." "$out/"
          elif [ -d "${flutter}/packages/${name}" ]; then
            cp -a "${flutter}/packages/${name}/." "$out/"
          elif [ -d "${flutter}/bin/cache/pkg/${name}" ]; then
            cp -a "${flutter}/bin/cache/pkg/${name}/." "$out/"
          else
            echo "missing Flutter SDK package: ${name}" >&2
            exit 1
          fi
        '';
        passthru.packageRoot = ".";
      };
  };
  src = fetchFromGitHub {
    owner = "denialwm";
    repo = "denial";
    tag = "v${version}";
    hash = "sha256-LEn3JA7PZ5IckhMhgTcVBokkxfxE/QJ/UmSNutM/GGY=";
  };
  sourceRoot = "source/dart_shell";
  strictDeps = true;
  dontStrip = true;
  nativeBuildInputs = [ flutter git unzip which ];

  configurePhase = ''
    runHook preConfigure
    export HOME="$TMPDIR/home"
    export PUB_CACHE="$TMPDIR/pub-cache"
    export FLUTTER_ROOT="$TMPDIR/flutter-sdk"
    mkdir -p "$HOME" "$PUB_CACHE"
    cp -a --no-preserve=mode "${flutter}/." "$FLUTTER_ROOT"
    chmod -R u+w "$FLUTTER_ROOT"
    export PATH="$FLUTTER_ROOT/bin:$PATH"
    engine_revision="${revisions.flutter}"
    cat > "$FLUTTER_ROOT/bin/cache/engine_stamp.json" <<EOF
    {
      "build_time_ms": 0,
      "git_revision": "$engine_revision",
      "git_revision_date": "1970-01-01T00:00:00Z",
      "content_hash": "$engine_revision"
    }
    EOF
    mkdir -p "$FLUTTER_ROOT/bin/cache/artifacts/material_fonts"
    unzip -q "${materialFonts}" -d "$FLUTTER_ROOT/bin/cache/artifacts/material_fonts"
    cat "$FLUTTER_ROOT/bin/internal/material_fonts.version" \
      > "$FLUTTER_ROOT/bin/cache/material_fonts.stamp"
    mkdir -p "$FLUTTER_ROOT/bin/cache/artifacts/gradle_wrapper"
    tar -xzf "${gradleWrapper}" -C "$FLUTTER_ROOT/bin/cache/artifacts/gradle_wrapper"
    cat "$FLUTTER_ROOT/bin/internal/gradle_wrapper.version" \
      > "$FLUTTER_ROOT/bin/cache/gradle_wrapper.stamp"
    mkdir -p "$FLUTTER_ROOT/bin/cache/pkg"
    ln -s "${denial-flutter-engine-source.dev}/flutter/sky/packages/sky_engine" \
      "$FLUTTER_ROOT/bin/cache/pkg/sky_engine"
    ln -s "${denial-flutter-engine-source.dev}/flutter/lib/gpu" \
      "$FLUTTER_ROOT/bin/cache/pkg/flutter_gpu"
    mkdir -p "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-${arch}"
    mkdir -p "$FLUTTER_ROOT/bin/cache/artifacts/engine/common"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/denial_host_release/font-subset" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-${arch}/font-subset"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/denial_host_release/gen/const_finder.dart.snapshot" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-${arch}/const_finder.dart.snapshot"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/denial_host_release/libflutter_linux_gtk.so" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-${arch}/libflutter_linux_gtk.so"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/denial_host_release/icudtl.dat" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-${arch}/icudtl.dat"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/denial_host_release/flutter_patched_sdk" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/common/flutter_patched_sdk"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/denial_host_release/gen/frontend_server_aot.dart.snapshot" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-${arch}/frontend_server_aot.dart.snapshot"
    for mode in debug profile release; do
      mkdir -p "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-${arch}-''${mode}"
      ln -s "${denial-flutter-engine-source.dev}/engine-build/out/denial_host_release/libflutter_linux_gtk.so" \
        "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-${arch}-''${mode}/libflutter_linux_gtk.so"
      ln -s "${denial-flutter-engine-source.dev}/engine-build/out/denial_host_release/flutter_linux" \
        "$FLUTTER_ROOT/bin/cache/artifacts/engine/linux-${arch}-''${mode}/flutter_linux"
    done
    printf '%s\n' "$engine_revision" > "$FLUTTER_ROOT/bin/cache/font-subset.stamp"
    printf '%s\n' "$engine_revision" > "$FLUTTER_ROOT/bin/cache/linux-sdk.stamp"
    printf '%s\n' "$engine_revision" > "$FLUTTER_ROOT/bin/cache/flutter_sdk.stamp"
    printf '%s\n' "$engine_revision" > "$FLUTTER_ROOT/bin/cache/engine.stamp"
    printf '%s\n' "$engine_revision" > "$FLUTTER_ROOT/bin/cache/engine_stamp.stamp"
    printf '%s\n' "$engine_revision" > "$FLUTTER_ROOT/bin/internal/engine_stamp.version"
    runHook postConfigure
  '';
  buildPhase = ''
    runHook preBuild
    export FLUTTER_ROOT="$TMPDIR/flutter-sdk"
    flutter() {
      "$FLUTTER_ROOT/bin/cache/dart-sdk/bin/dart" \
        --disable-dart-dev "$FLUTTER_ROOT/bin/cache/flutter_tools.snapshot" "$@"
    }
    flutter assemble \
      --suppress-analytics \
      --output="$TMPDIR/bundle" \
      --local-engine-src-path="${denial-flutter-engine-source.dev}/engine-build" \
      --local-engine=denial_host_release \
      --local-engine-host=denial_host_release \
      -dTargetPlatform=linux-${arch} \
      -dBuildMode=release \
      -dTreeShakeIcons=true \
      release_bundle_linux-${arch}_assets
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm555 "$TMPDIR/bundle/lib/libapp.so" \
      "$out/lib/denial/flutter/lib/libapp.so"
    mkdir -p "$out/lib/denial/flutter/data"
    cp -a "$TMPDIR/bundle/flutter_assets" \
      "$out/lib/denial/flutter/data/flutter_assets"
    chmod -R u=rwX,go=rX "$out/lib/denial/flutter/data/flutter_assets"
    install -Dm444 assets/fonts/OFL.txt \
      "$out/share/licenses/${finalAttrs.pname}/OFL.txt"
    runHook postInstall
  '';

  meta = {
    description = "Denial Dart shell built with the Denial Flutter fork";
    homepage = "https://github.com/denialwm/denial";
    license = with lib.licenses; [ gpl3Plus cc-by-sa-40 ofl ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
  };
})
