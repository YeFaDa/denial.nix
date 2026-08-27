{
  description = "Denial, a Flutter-native Wayland compositor — nixpkgs-style packaging";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      isX86 = system: system == "x86_64-linux";

      mkPackages = system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          inherit (pkgs)
            denial
            denial-flutter-engine
            denial-flutter-shell
            denial-source
            denial-flutter-engine-source
            denial-flutter-shell-source
            ;
        }
        // nixpkgs.lib.optionalAttrs (isX86 system) {
          denial-prebuilt = pkgs.denial-prebuilt;
        };
    in
    {
      overlays.default = final: prev:
        let
          isX86 = prev.stdenv.hostPlatform.system == "x86_64-linux";

          enginePrebuilt = final.callPackage ./pkgs/denial-flutter-engine/package.nix { };
          shellPrebuilt = final.callPackage ./pkgs/denial-flutter-shell/package.nix { };

          dartSdkSource = final.callPackage ./pkgs/denial-flutter-engine/dart.nix { };
          flutterToolsSource = final.callPackage ./pkgs/denial-flutter-engine/flutter-tools.nix {
            dart = dartSdkSource;
            sdkSourceBuilders = {
              flutter = name:
                final.runCommand "denial-flutter-sdk-package-${name}" {
                  passthru.packageRoot = ".";
                } ''
                  ln -s "${engineSource.dev}/flutter/packages/${name}" "$out"
                '';
            };
          };
          flutterSdkSource = final.callPackage ./pkgs/denial-flutter-engine/flutter-sdk.nix {
            dart = dartSdkSource;
            flutterTools = flutterToolsSource;
          };
          engineSource = final.callPackage ./pkgs/denial-flutter-engine/source.nix {
            dartSdk = dartSdkSource;
          };
          shellSource = final.callPackage ./pkgs/denial-flutter-shell/source.nix {
            flutter = flutterSdkSource;
            denial-flutter-engine-source = engineSource;
          };

          denialPrebuilt = final.callPackage ./pkgs/denial/package.nix {
            denial-flutter-engine = enginePrebuilt;
            denial-flutter-shell = shellPrebuilt;
          };
          denialSource = (final.callPackage ./pkgs/denial/package.nix {
            denial-flutter-engine = engineSource;
            denial-flutter-shell = shellSource;
          }).overrideAttrs (old: {
            meta = old.meta // {
              platforms = [ "x86_64-linux" "aarch64-linux" ];
              sourceProvenance = [ final.lib.sourceTypes.fromSource ];
              hydraPlatforms = [ ];
            };
          });
        in
        {
          denial-flutter-engine = if isX86 then enginePrebuilt else engineSource;
          denial-flutter-shell = if isX86 then shellPrebuilt else shellSource;
          denial = if isX86 then denialPrebuilt else denialSource;
          denial-source = denialSource;
          denial-flutter-engine-source = engineSource;
          denial-flutter-shell-source = shellSource;
        }
        // nixpkgs.lib.optionalAttrs isX86 {
          denial-prebuilt = denialPrebuilt;
        };

      packages = nixpkgs.lib.genAttrs systems mkPackages;

      nixosModules.denial = import ./nix/module.nix;
      nixosModules.default = self.nixosModules.denial;
    };
}
