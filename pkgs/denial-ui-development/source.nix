{
  lib,
  stdenv,
  fetchFromGitHub,
  jq,
  python3,
  unzip,

  # The pinned Flutter fork: supplies the SDK skeleton (packages/, bin/internal,
  # lib/ui) that the runtime tree is assembled around.
  flutter,
  # flutter_tools.snapshot plus its resolved package_config.json.
  flutterTools,
  # Locally built engine trees. The debug one carries a full Dart SDK, the
  # Impeller compiler, const_finder, font-subset and the embedder headers; the
  # profile one carries gen_snapshot and the GTK engine.
  denial-flutter-engine-debug-source,
  denial-flutter-engine-profile-source,
  # The three entries upstream can only download. See
  # pkgs/flutter-engine-artifacts.nix.
  engineArtifacts,
  materialFonts,
  gradleWrapper,
  # The native client, installed as both `denial-ui` and the SDK's `flutter`.
  denialUi,
}:

let
  version = import ../version.nix;
  flutterArch = import ../flutter-arch.nix { system = stdenv.hostPlatform.system; };

  # Upstream's `FLUTTER_ENGINE_ABI` in tools/xtask. Written into the pub-cache
  # generation marker and the workspace marker so a toolchain and a compositor
  # that disagree about the engine ABI can say so instead of failing obscurely.
  engineAbi = "3.44.7.denial1";

  debugOut = "${denial-flutter-engine-debug-source.dev}/engine-build/out/${denial-flutter-engine-debug-source.localEngine}";
  profileOut = "${denial-flutter-engine-profile-source.dev}/engine-build/out/${denial-flutter-engine-profile-source.localEngine}";

  # Where the SDK runtime ends up. Quoted into the generated
  # `package_config.json`, so it has to be the real store path and not a
  # relative one.
  sdkRoot = "${placeholder "out"}/lib/denial/ui-development/flutter";

  # The commit `v${version}` points at. Spelled out because the workspace
  # marker records it and `fetchFromGitHub` does not expose the commit it
  # resolved a tag to -- passing `rev` here instead of `tag` would change the
  # tarball URL and therefore the hash. Bump with `pkgs/version.nix`; see
  # `scripts/update-release-pins`.
  sourceRev = "85b2303e2f09ae7b7b993641f90061a200f03d53";
in
stdenv.mkDerivation (finalAttrs: {
  pname = "denial-ui-development-source";
  inherit version;

  # Only needed for the workspace template: dart_shell, protocol/generated/dart,
  # docs/UI_DEVELOPMENT.md and the top-level licence and README. Everything else
  # comes from the inputs above.
  src = fetchFromGitHub {
    owner = "denialwm";
    repo = "denial";
    tag = "v${version}";
    hash = "sha256-qRbD0HvBJ87QWriQsx6GWdYVMnKj1Iae8QLRaxRL8T4=";
  };

  nativeBuildInputs = [
    jq
    python3
    unzip
  ];

  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;

  # Upstream builds this package by copying a tree that `flutter precache
  # --linux` populated over the network and then overwriting the parts it can
  # build locally. That first step is impossible in a Nix build, so this
  # derivation assembles the same tree from three sources instead:
  #
  #   1. the pinned Flutter checkout, for everything that is genuinely source
  #      (packages/flutter/lib, bin/internal, lib/ui, ...);
  #   2. the locally built debug and profile engines, which upstream also
  #      overlays -- this covers the whole Dart SDK, impellerc, const_finder,
  #      font-subset, gen_snapshot and the embedder headers;
  #   3. pkgs/flutter-engine-artifacts.nix for the three entries nobody builds.
  #
  # The lists below mirror `build_flutter_sdk_runtime` and
  # `overlay_locked_development_sdk` in tools/xtask/src/main.rs and are kept in
  # the same order so the two can be diffed.
  installPhase = ''
    runHook preInstall

    runtime="$TMPDIR/flutter-sdk-runtime"
    mkdir -p "$runtime"

    # ---- 1. directories and files taken straight from the Flutter checkout ----
    for relative in \
      bin/cache/artifacts/gradle_wrapper \
      bin/cache/artifacts/material_fonts \
      packages/flutter/lib \
      packages/flutter_localizations/lib \
      packages/flutter_test/lib \
      packages/flutter_tools/lib
    do
      mkdir -p "$runtime/$(dirname "$relative")"
      cp -a --no-preserve=mode "${flutter}/$relative" "$runtime/$relative"
    done

    for relative in \
      AUTHORS \
      LICENSE \
      PATENT_GRANT \
      packages/flutter/LICENSE \
      packages/flutter/pubspec.yaml \
      packages/flutter_localizations/pubspec.yaml \
      packages/flutter_test/pubspec.yaml \
      packages/flutter_tools/pubspec.yaml
    do
      if [ -e "${flutter}/$relative" ]; then
        install -Dm644 "${flutter}/$relative" "$runtime/$relative"
      fi
    done

    # Cache stamps and version markers, which are how the Flutter tool decides
    # whether it needs to re-download something. Upstream copies every file in
    # bin/cache under 1 MiB except the tool snapshot; the effect is the same.
    mkdir -p "$runtime/bin/cache"
    find "${flutter}/bin/cache" -maxdepth 1 -type f \
      ! -name flutter_tools.snapshot -size -1M \
      -exec cp -a --no-preserve=mode {} "$runtime/bin/cache/" \;
    mkdir -p "$runtime/bin/internal"
    find "${flutter}/bin/internal" -maxdepth 1 -type f -name '*.version' \
      -exec cp -a --no-preserve=mode {} "$runtime/bin/internal/" \;

    # ---- 2. material fonts and gradle wrapper, fetched separately ----
    mkdir -p "$runtime/bin/cache/artifacts/material_fonts"
    unzip -q "${materialFonts}" -d "$runtime/bin/cache/artifacts/material_fonts"
    mkdir -p "$runtime/bin/cache/artifacts/gradle_wrapper"
    tar -xzf "${gradleWrapper}" -C "$runtime/bin/cache/artifacts/gradle_wrapper"

    # ---- 3. the locally built engine, over what upstream overlays ----
    #
    # The whole Dart SDK comes from the debug build. Upstream reaches the same
    # place by copying a downloaded SDK and then replacing every one of these
    # paths, so starting from ours skips a step rather than diverging.
    # Two loops because `install` refuses directories, so the tree entries and
    # the file entries cannot share one.
    for relative in \
      lib \
      bin/resources/devtools
    do
      rm -rf "$runtime/bin/cache/dart-sdk/$relative"
      mkdir -p "$runtime/bin/cache/dart-sdk/$(dirname "$relative")"
      cp -a --no-preserve=mode "${debugOut}/dart-sdk/$relative" \
        "$runtime/bin/cache/dart-sdk/$relative"
    done
    for relative in \
      LICENSE \
      revision \
      sdk_packages.yaml \
      version \
      bin/dart \
      bin/dartaotruntime \
      bin/dartvm \
      bin/snapshots/analysis_server.dart.snapshot \
      bin/snapshots/analysis_server_aot.dart.snapshot \
      bin/snapshots/dart_tooling_daemon_aot.dart.snapshot \
      bin/snapshots/dartdev_aot.dart.snapshot \
      bin/snapshots/dds_aot.dart.snapshot \
      bin/snapshots/frontend_server_aot.dart.snapshot
    do
      rm -f "$runtime/bin/cache/dart-sdk/$relative"
      install -Dm755 "${debugOut}/dart-sdk/$relative" \
        "$runtime/bin/cache/dart-sdk/$relative"
    done

    # Sky engine: the GN-generated package, with the framework's own lib/ui on
    # top, exactly as upstream does it.
    rm -rf "$runtime/bin/cache/pkg/sky_engine"
    mkdir -p "$runtime/bin/cache/pkg/sky_engine"
    cp -a --no-preserve=mode \
      "${debugOut}/gen/dart-pkg/sky_engine/lib" \
      "$runtime/bin/cache/pkg/sky_engine/lib"
    rm -rf "$runtime/bin/cache/pkg/sky_engine/lib/ui"
    cp -a --no-preserve=mode "${flutter}/lib/ui" \
      "$runtime/bin/cache/pkg/sky_engine/lib/ui"
    install -Dm644 "${debugOut}/gen/dart-pkg/sky_engine/lib/_embedder.yaml" \
      "$runtime/bin/cache/pkg/sky_engine/lib/_embedder.yaml"

    install -Dm755 "${debugOut}/font-subset" \
      "$runtime/bin/cache/artifacts/engine/${flutterArch.platform}/font-subset"
    install -Dm644 "${debugOut}/gen/const_finder.dart.snapshot" \
      "$runtime/bin/cache/artifacts/engine/${flutterArch.platform}/const_finder.dart.snapshot"
    install -Dm755 "${debugOut}/impellerc" \
      "$runtime/bin/cache/artifacts/engine/${flutterArch.platform}/impellerc"
    # Not from the engine build: nothing in Denial's target list produces this
    # file, upstream's SDK tree takes it from the `flutter precache` download,
    # and pkgs/flutter-engine-artifacts.nix is this repository's equivalent.
    install -Dm644 "${engineArtifacts}/artifacts/engine/${flutterArch.platform}/icudtl.dat" \
      "$runtime/bin/cache/artifacts/engine/${flutterArch.platform}/icudtl.dat"
    mkdir -p "$runtime/bin/cache/artifacts/engine/common"
    cp -a --no-preserve=mode "${debugOut}/flutter_patched_sdk" \
      "$runtime/bin/cache/artifacts/engine/common/flutter_patched_sdk"
    cp -a --no-preserve=mode "${debugOut}/flutter_linux" \
      "$runtime/bin/cache/artifacts/engine/${flutterArch.platform}/flutter_linux"

    install -Dm755 "${profileOut}/gen_snapshot" \
      "$runtime/bin/cache/artifacts/engine/${flutterArch.platform}-profile/gen_snapshot"
    install -Dm755 "${profileOut}/libflutter_linux_gtk.so" \
      "$runtime/bin/cache/artifacts/engine/${flutterArch.platform}-profile/libflutter_linux_gtk.so"

    # ---- 4. the three entries that can only be downloaded ----
    artifacts="${engineArtifacts}/artifacts/engine/${flutterArch.platform}"
    install -Dm644 "$artifacts/isolate_snapshot.bin" \
      "$runtime/bin/cache/artifacts/engine/${flutterArch.platform}/isolate_snapshot.bin"
    install -Dm644 "$artifacts/vm_isolate_snapshot.bin" \
      "$runtime/bin/cache/artifacts/engine/${flutterArch.platform}/vm_isolate_snapshot.bin"
    cp -a --no-preserve=mode "$artifacts/shader_lib" \
      "$runtime/bin/cache/artifacts/engine/${flutterArch.platform}/shader_lib"

    # ---- 5. directories the Flutter tool expects to find even on Linux ----
    # Upstream creates these so that code paths probing for iOS tooling find an
    # empty directory instead of a missing one.
    for relative in \
      bin/cache/artifacts/engine/${flutterArch.platform}-release \
      bin/cache/artifacts/ios-deploy \
      bin/cache/artifacts/libimobiledevice \
      bin/cache/artifacts/libimobiledeviceglue \
      bin/cache/artifacts/libplist \
      bin/cache/artifacts/libusbmuxd \
      bin/cache/artifacts/openssl
    do
      mkdir -p "$runtime/$relative"
    done
    mkdir -p "$runtime/dev" "$runtime/examples"
    touch "$runtime/dev/.dartignore" "$runtime/examples/.dartignore"

    # ---- 6. flutter tool runtime: package_config.json plus its pub cache ----
    #
    # Upstream rewrites the resolved `package_config.json` so its dependencies
    # point at a pub cache shipped next to it, then copies each dependency's
    # pubspec.yaml and licence into that cache. Without the rewrite the paths
    # would point back into whatever build directory resolved them, which does
    # not exist at runtime.
    toolRuntime="$TMPDIR/tool-runtime"
    mkdir -p "$toolRuntime"
    python3 ${./prepare-tool-runtime.py} \
      "${flutter}/packages/flutter_tools/.dart_tool/package_config.json" \
      "$toolRuntime/pub-cache" \
      "$toolRuntime/package_config.json" \
      "file://${sdkRoot}" \
      "${engineAbi}"

    # ---- 7. assemble the payload ----
    destination="$out/lib/denial/ui-development"
    install -Dm755 "${denialUi}/bin/denial-ui" "$out/bin/denial-ui"
    ln -s denial-ui "$out/bin/denial-flutter"

    install -Dm755 "${debugOut}/libflutter_engine.so" \
      "$destination/lib/libflutter_engine.so"
    install -Dm755 "${profileOut}/libflutter_engine.so" \
      "$destination/profile/lib/libflutter_engine.so"
    # Matches where the compositor keeps its own copy, so the toolchain and
    # the session find ICU data in the same place on either side.
    install -Dm644 "${engineArtifacts}/artifacts/engine/${flutterArch.platform}/icudtl.dat" \
      "$destination/data/icudtl.dat"

    cp -a --no-preserve=mode "$runtime" "$destination/flutter"
    # Dart Code resolves Flutter launchers and rejects a symlink whose final
    # basename is not literally "flutter", so this has to be a real copy of the
    # client rather than a wrapper script.
    install -m755 "${denialUi}/bin/denial-ui" \
      "$destination/flutter/bin/flutter"
    install -Dm644 "${flutterTools}/share/flutter_tools.snapshot" \
      "$destination/flutter/bin/cache/flutter_tools.snapshot"
    mkdir -p "$destination/flutter/packages/flutter_tools/.dart_tool"
    install -Dm644 "$toolRuntime/package_config.json" \
      "$destination/flutter/packages/flutter_tools/.dart_tool/package_config.json"
    cp -a --no-preserve=mode "$toolRuntime/pub-cache" "$destination/pub-cache"

    # ---- 8. workspace template ----
    workspace="$out/share/denial/ui-development/workspace"
    mkdir -p "$workspace"
    for relative in \
      .gitignore \
      LICENSE \
      README.md \
      dart_shell \
      docs/UI_DEVELOPMENT.md \
      protocol/generated/dart
    do
      mkdir -p "$workspace/$(dirname "$relative")"
      cp -a --no-preserve=mode "$src/$relative" "$workspace/$relative"
    done
    for required in \
      dart_shell/pubspec.yaml \
      dart_shell/lib/main.dart \
      protocol/generated/dart/pubspec.yaml \
      dart_shell/.vscode/launch.json \
      dart_shell/.vscode/settings.json
    do
      test -f "$workspace/$required" \
        || (echo "workspace template is missing $required" >&2; exit 1)
    done
    jq -n \
      --arg version "${version}" \
      --arg revision "${sourceRev}" \
      --arg abi "${engineAbi}" \
      '{
        schema_version: 1,
        ui_development_api: 1,
        denial_version: $version,
        flutter_generation: $abi,
        source_ref: ("v" + $version),
        source_revision: $revision,
        source_state: "committed",
        workspace: "dart_shell"
      }' > "$workspace/.denial-ui-source.json"

    # ---- 9. lock metadata, minus the checksums we cannot honour ----
    # Upstream also ships `libflutter_engine.so.sha256` and `BUILD_INFO.md` for
    # both engines. Those describe upstream's CI-built binaries; ours are built
    # here and will not match, so shipping them would be advertising a checksum
    # this package does not satisfy. The lock inputs themselves are accurate
    # and are kept.
    meta_dir="$out/share/denial/ui-development"
    install -Dm644 "$src/packaging/arch/ui-development/manifest.json" \
      "$meta_dir/manifest.json"
    install -Dm644 "$src/prebuilt/flutter-engine/SOURCE_LOCK.json" \
      "$meta_dir/SOURCE_LOCK.json"
    for mode in debug profile; do
      for name in args.gn ENGINE_REVISION FLUTTER_REVISION; do
        install -Dm644 "$src/prebuilt/flutter-engine/linux-x64-$mode/$name" \
          "$meta_dir/$mode/$name"
      done
    done
    install -dm755 "$out/share/doc/denial-ui-development"
    install -Dm644 "$src/docs/UI_DEVELOPMENT.md" \
      "$out/share/doc/denial-ui-development/UI_DEVELOPMENT.md"
    install -Dm644 "${denialUi}/share/man/man1/denial-ui.1" \
      "$out/share/man/man1/denial-ui.1"
    install -Dm644 "$src/prebuilt/flutter-engine/linux-x64-release/LICENSE.flutter" \
      "$out/share/licenses/${finalAttrs.pname}/LICENSE.flutter"

    # ---- 10. permissions, matching what the Arch package ends up with ----
    chmod -R u=rwX,go=rX \
      "$destination/flutter" \
      "$destination/pub-cache" \
      "$workspace"
    find "$destination/flutter" "$destination/pub-cache" "$workspace" \
      -type d -exec chmod 0755 -- {} +

    runHook postInstall
  '';

  passthru = {
    inherit engineAbi flutter flutterTools;
  };

  # Nothing here is architecture-specific in the sense that would stop it
  # building: the engines come from the shared source build and the artifacts
  # are pinned per platform. It is listed for both, but see the note in
  # pkgs/flutter-engine-artifacts.nix about the download.
  meta = {
    description = "Live Flutter UI development toolchain for Denial, built from the locked engine sources";
    homepage = "https://github.com/denialwm/denial";
    # Denial's own code is GPL-3+; the Flutter SDK and engine it ships are
    # BSD-3-Clause.
    license = with lib.licenses; [ gpl3Plus bsd3 ];
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    # Mostly from source, but pkgs/flutter-engine-artifacts.nix contributes
    # the snapshot and shader files upstream only publishes as binaries.
    sourceProvenance = with lib.sourceTypes; [ fromSource binaryNativeCode ];
  };
})
