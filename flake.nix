{
  description = "Denial, a Flutter-native Wayland compositor — nixpkgs-style packaging";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  inputs.nixpkgs-dart.url = "github:NixOS/nixpkgs/61eb395f5d618db696e4918efc774431fb15056e";

  outputs = { self, nixpkgs, nixpkgs-dart }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];

      mkPackages = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
          isX86 = system == "x86_64-linux";
        in
        {
          denial = if isX86 then pkgs.denial else pkgs.denial.override { useSource = true; };
          denial-source = pkgs.denial.override { useSource = true; };
          denial-flutter-engine = if isX86 then pkgs.denial-flutter-engine else pkgs.denial-flutter-engine-source;
          denial-flutter-shell = if isX86 then pkgs.denial-flutter-shell else pkgs.denial-flutter-shell-source;
          inherit (pkgs) denial-flutter-engine-source denial-flutter-shell-source;
          "gclient2nix-linux" = pkgs.gclient2nixLinux;
          "denial-update-check" = pkgs.updateCheck;
        } // nixpkgs.lib.optionalAttrs isX86 {
          "denial-settings" = pkgs.denialSettings;
          "denial-ui-development" = pkgs.denialUiDevelopment;
        };
    in
    {
      overlays.default = final: prev:
        let
          revisions = import ./pkgs/denial-flutter-engine/revisions.nix { lib = final.lib; };

          materialFonts = final.fetchurl {
            url = "https://storage.googleapis.com/${revisions.materialFontsVersion}";
            hash = "sha256-5W+o6btFif3pZL495FHz5bJR5KHq+x3JjZSt0DTdWoY=";
          };
          gradleWrapper = final.fetchurl {
            url = "https://storage.googleapis.com/${revisions.gradleWrapperVersion}";
            hash = "sha256-MelCi68aKy9IXxEQxYmfhSZJsz1Goumwf50XdS1QGQo=";
          };

          enginePrebuilt = final.callPackage ./pkgs/denial-flutter-engine/package.nix { };
          shellPrebuilt = final.callPackage ./pkgs/denial-flutter-shell/package.nix { };
          gclient2nix = final.gclient2nix;
          gclient2nixLinux = final.runCommand "gclient2nix-linux" {
            nativeBuildInputs = [ final.makeWrapper ];
          } ''
            mkdir -p "$out/bin"
            cp ${final.gclient2nix}/bin/.gclient2nix-wrapped "$out/bin/gclient2nix"
            chmod u+w "$out/bin/gclient2nix"
            substituteInPlace "$out/bin/gclient2nix" \
              --replace-fail 'else None,' 'else {"host_os": "linux", "host_cpu": "x64"},'
            wrapProgram "$out/bin/gclient2nix" \
              --set PATH ${final.lib.makeBinPath [ final.nurl ]}
          '';
          dartSdkSource = nixpkgs-dart.legacyPackages.${prev.stdenv.hostPlatform.system}.dart-bin;
          engineSource = final.callPackage ./pkgs/denial-flutter-engine/source.nix {
            dart = dartSdkSource;
            inherit gclient2nix revisions;
          };
          flutterToolsSource = final.callPackage ./pkgs/denial-flutter-engine/flutter-tools.nix {
            dart = dartSdkSource;
            inherit gclient2nix revisions;
            sdkSourceBuilders = {
              flutter = name:
                final.runCommand "denial-flutter-sdk-${name}" {
                  passthru.packageRoot = ".";
                } ''
                  mkdir -p "$out"
                  if [ "${name}" = sky_engine ]; then
                    cp -a "${engineSource.dev}/flutter/sky/packages/sky_engine/." "$out/"
                  else
                    cp -a "${engineSource.dev}/flutter/packages/${name}/." "$out/"
                  fi
                '';
            };
          };
          flutterSdkSource = final.callPackage ./pkgs/denial-flutter-engine/flutter-sdk.nix {
            dart = dartSdkSource;
            inherit gclient2nix;
            flutterTools = flutterToolsSource;
          };
          shellSource = final.callPackage ./pkgs/denial-flutter-shell/source.nix {
            flutter = flutterSdkSource;
            denial-flutter-engine-source = engineSource;
            inherit revisions materialFonts gradleWrapper;
          };

          denial = final.callPackage ./pkgs/denial/package.nix {
            denial-flutter-engine-prebuilt = enginePrebuilt;
            denial-flutter-shell-prebuilt = shellPrebuilt;
            denial-flutter-engine-source = engineSource;
            denial-flutter-shell-source = shellSource;
          };
          denialSettings = final.callPackage ./pkgs/denial-settings/package.nix { };
          denialUiDevelopment = final.callPackage ./pkgs/denial-ui-development/package.nix { };
          updateCheck = final.callPackage ./pkgs/update-check/package.nix { dart = dartSdkSource; };
        in
        {
          denial-flutter-engine = enginePrebuilt;
          denial-flutter-shell = shellPrebuilt;
          inherit denial denialSettings denialUiDevelopment updateCheck gclient2nixLinux;
          "denial-settings" = denialSettings;
          "denial-ui-development" = denialUiDevelopment;
          "denial-update-check" = updateCheck;
          denial-flutter-engine-source = engineSource;
          denial-flutter-shell-source = shellSource;
        };
      packages = nixpkgs.lib.genAttrs systems mkPackages;

      nixosModules.denial = import ./nix/module.nix;
      nixosModules.default = self.nixosModules.denial;
    };
}
