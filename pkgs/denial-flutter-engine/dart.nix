{
  lib,
  stdenv,
  fetchurl,
  unzip,
}:

let
  version = "3.12.2";
in
stdenv.mkDerivation {
  pname = "denial-dart-sdk";
  inherit version;

  src = fetchurl {
    url = "https://storage.googleapis.com/dart-archive/channels/stable/release/${version}/sdk/dartsdk-linux-${if stdenv.hostPlatform.isx86_64 then "x64" else "arm64"}-release.zip";
    hash =
      if stdenv.hostPlatform.isx86_64 then
        "sha256-KOR7RM8HXzZ3EEbAaLsNF0IBz5x2CHRK7RzCMgQpnC0="
      else
        "sha256-+CyD7OfRaAR1UN/UpmTkBxrHxIi923LcQxAsItfgtRg=";
  };

  nativeBuildInputs = [ unzip ];
  sourceRoot = ".";
  installPhase = ''
    mkdir -p "$out"
    cp -a ./. "$out/"
  '';
  dontStrip = true;

  meta = {
    description = "Dart SDK pinned by the Denial Flutter fork";
    homepage = "https://dart.dev/";
    license = lib.licenses.bsd3;
    platforms = [ "x86_64-linux" "aarch64-linux" ];
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
