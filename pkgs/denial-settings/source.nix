{
  lib,
  stdenv,
  fetchFromGitHub,
  buildDartApplication,
  dart,
  flutter,
  git,
  makeWrapper,
  pkg-config,
  unzip,
  which,
  glib,
  gtk3,
  libepoxy,
  pango,
  cairo,
  atk,
  gdk-pixbuf,
  libglvnd,
  denial-flutter-engine-source,
  revisions,
  materialFonts,
  gradleWrapper,
}:

let
  version = import ../version.nix;
  # Shared with flutter-tools and the engine. Both spellings are used below:
  # `platform` for the Flutter cache/artifact layout, `cpu` for the Dart build
  # output tree.
  flutterArch = import ../flutter-arch.nix { system = stdenv.hostPlatform.system; };
in
buildDartApplication.override { inherit dart; } (finalAttrs: {
  pname = "denial-settings-source";
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
    hash = "sha256-bvti0xjlqNEd8o1/XfOetM7TwPJyvXesNJmLAKAWpZM=";
  };
  sourceRoot = "source/settings_app";
  strictDeps = true;
  dontStrip = true;
  nativeBuildInputs = [ flutter git makeWrapper pkg-config unzip which ];
  buildInputs = [ glib gtk3 ];

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
    mkdir -p "$FLUTTER_ROOT/bin/cache/artifacts/engine/${flutterArch.platform}"
    mkdir -p "$FLUTTER_ROOT/bin/cache/artifacts/engine/common"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/${denial-flutter-engine-source.localEngine}/font-subset" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/${flutterArch.platform}/font-subset"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/${denial-flutter-engine-source.localEngine}/gen/const_finder.dart.snapshot" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/${flutterArch.platform}/const_finder.dart.snapshot"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/${denial-flutter-engine-source.localEngine}/libflutter_linux_gtk.so" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/${flutterArch.platform}/libflutter_linux_gtk.so"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/${denial-flutter-engine-source.localEngine}/icudtl.dat" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/${flutterArch.platform}/icudtl.dat"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/${denial-flutter-engine-source.localEngine}/flutter_patched_sdk" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/common/flutter_patched_sdk"
    ln -s "${denial-flutter-engine-source.dev}/engine-build/out/${denial-flutter-engine-source.localEngine}/gen/frontend_server_aot.dart.snapshot" \
      "$FLUTTER_ROOT/bin/cache/artifacts/engine/${flutterArch.platform}/frontend_server_aot.dart.snapshot"
    for mode in debug profile release; do
      mkdir -p "$FLUTTER_ROOT/bin/cache/artifacts/engine/${flutterArch.platform}-''${mode}"
      ln -s "${denial-flutter-engine-source.dev}/engine-build/out/${denial-flutter-engine-source.localEngine}/libflutter_linux_gtk.so" \
        "$FLUTTER_ROOT/bin/cache/artifacts/engine/${flutterArch.platform}-''${mode}/libflutter_linux_gtk.so"
      ln -s "${denial-flutter-engine-source.dev}/engine-build/out/${denial-flutter-engine-source.localEngine}/flutter_linux" \
        "$FLUTTER_ROOT/bin/cache/artifacts/engine/${flutterArch.platform}-''${mode}/flutter_linux"
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
    flutter pub get --offline
    flutter build linux \
      --local-engine-src-path="${denial-flutter-engine-source.dev}/engine-build" \
      --local-engine=${denial-flutter-engine-source.localEngine} \
      --local-engine-host=${denial-flutter-engine-source.localEngine} \
      --suppress-analytics \
      --release \
      --target=lib/main.dart \
      --tree-shake-icons
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    bundle="build/linux/${flutterArch.cpu}/release/bundle"
    test -x "$bundle/denial-settings"
    mkdir -p "$out/lib/denial/settings"
    cp -a "$bundle/." "$out/lib/denial/settings/"
    chmod -R u=rwX,go=rX "$out/lib/denial/settings"
    makeWrapper "$out/lib/denial/settings/denial-settings" \
      "$out/bin/denial-settings" \
      --prefix LD_LIBRARY_PATH : "${lib.makeLibraryPath [
        glib
        gtk3
        libepoxy
        pango
        cairo
        atk
        gdk-pixbuf
        libglvnd
      ]}"
    install -Dm644 ../packaging/arch/dev.denial.Settings.desktop \
      "$out/share/applications/dev.denial.Settings.desktop"
    substituteInPlace "$out/share/applications/dev.denial.Settings.desktop" \
      --replace-fail /usr/bin/denial-settings "$out/bin/denial-settings"
    install -Dm444 ../dart_shell/assets/fonts/OFL.txt \
      "$out/share/licenses/${finalAttrs.pname}/OFL.txt"
    runHook postInstall
  '';

  meta = {
    description = "Denial Settings application built with the Denial Flutter fork";
    homepage = "https://github.com/denialwm/denial";
    license = with lib.licenses; [ gpl3Plus ofl ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.fromSource ];
    hydraPlatforms = [ ];
  };
})
