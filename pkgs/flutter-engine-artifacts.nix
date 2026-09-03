# The handful of files a Flutter SDK normally gets from
# `flutter precache --linux` that Denial's own engine build has no target for.
#
# A Flutter SDK's `bin/cache/artifacts/engine/<platform>/` tree is populated by
# downloading it, not by building it. Most of that tree is replaceable here:
# `tools/xtask`'s `overlay_locked_development_sdk` in the upstream repository
# overwrites `dart-sdk`, `flutter_patched_sdk`, `impellerc`, `const_finder`,
# `font-subset`, `flutter_linux` and `gen_snapshot` with the locally built
# debug and profile engine outputs, and this repository does the same.
#
# Four entries survive that overlay and have no local producer:
#
#   icudtl.dat              the Dart VM's ICU data (about 840 KB)
#   isolate_snapshot.bin     Dart VM snapshot data (about 11 MB)
#   vm_isolate_snapshot.bin  Dart VM snapshot data
#   shader_lib/              Impeller's GLSL sources plus their BUILD.gn files
#
# `icudtl.dat` is in that category because nothing in Denial's own target list
# produces it: upstream's `build_artifacts` and `prepare-development-sdk` ninja
# invocations never name it, and the SDK tree takes it from the `flutter
# precache` download. The compositor's release engine does ship one -- that
# comes out of the same build, not from here.
#
# So they are downloaded. This is the one place in the repository that ships
# upstream binaries as part of a `-source` package, and
# `denial-ui-development-source` reflects that in its `sourceProvenance`.
#
# The revision these belong to is pinned in
# `pkgs/flutter-engine-revision.nix`, which is *not* the revision Denial builds
# its engine from. Upstream mixes the two as well -- the Arch packaging for
# `denial-ui-development` takes `icudtl.dat` from here and the engine itself
# from the source build.
#
# The hashes below were computed from `storage.flutter-io.cn`, the Flutter
# project's own mirror of this bucket, because the origin is unreachable from
# some networks. The mirror serves byte-identical content, so the hashes hold
# either way; if `storage.googleapis.com` is unreachable where you build,
# switch `url` to the mirror rather than changing the hashes.
{
  lib,
  stdenv,
  fetchurl,
  unzip,
}:
let
  revision = import ./flutter-engine-revision.nix;
  flutterArch = import ./flutter-arch.nix { system = stdenv.hostPlatform.system; };
  hashes = {
    "x86_64-linux" = "sha256-JYgg0qydyLKGq5Q0UFuZ3Em72/8XzwO28mxAnLHyzsE=";
    "aarch64-linux" = "sha256-svJ9kPNBX86Ee25GK5RLtZuQnEX+e1RMfJukqUd8cZk=";
  };
in
stdenv.mkDerivation {
  pname = "flutter-engine-artifacts";
  version = revision;

  src = fetchurl {
    url = "https://storage.googleapis.com/flutter_infra_release/flutter/${revision}/${flutterArch.platform}/artifacts.zip";
    hash =
      hashes."${stdenv.hostPlatform.system}"
        or (throw "flutter-engine-artifacts: no hash pinned for ${stdenv.hostPlatform.system}; download ${flutterArch.platform}/artifacts.zip for revision ${revision} and add it here");
  };

  nativeBuildInputs = [ unzip ];

  dontConfigure = true;
  dontBuild = true;

  # The archive also carries `flutter_tester`, `gen_snapshot`, `impellerc`,
  # `frontend_server_aot.dart.snapshot` and the path/tessellator libraries.
  # Those are all produced locally or not needed, and `flutter_tester` alone
  # is 35 MB, so only the four entries above are extracted.
  unpackPhase = ''
    runHook preUnpack
    unzip -q "$src" \
      icudtl.dat isolate_snapshot.bin vm_isolate_snapshot.bin 'shader_lib/*'
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    # Laid out the way the Flutter SDK lays it out under `bin/cache`, so the
    # ui-development package can copy it into place without renaming anything.
    target="$out/artifacts/engine/${flutterArch.platform}"
    mkdir -p "$target"
    cp -a icudtl.dat isolate_snapshot.bin vm_isolate_snapshot.bin shader_lib "$target/"
    runHook postInstall
  '';

  meta = {
    description = "Flutter engine artifacts upstream only publishes as downloads";
    homepage = "https://github.com/denialwm/flutter";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
