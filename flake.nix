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
          denial-flutter-engine = if isX86 then pkgs.denial-flutter-engine else pkgs.denial-flutter-engine-source;
          denial-flutter-shell = if isX86 then pkgs.denial-flutter-shell else pkgs.denial-flutter-shell-source;
          inherit (pkgs) denial-flutter-engine-source denial-flutter-shell-source;
        };
    in
    {
      overlays.default = final: prev:
        let
          revisions = import ./pkgs/denial-flutter-engine/revisions.nix { lib = final.lib; };

          enginePrebuilt = final.callPackage ./pkgs/denial-flutter-engine/package.nix { };
          shellPrebuilt = final.callPackage ./pkgs/denial-flutter-shell/package.nix { };
          gclient2nix = final.gclient2nix;
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
            inherit revisions;
          };

          denial = final.callPackage ./pkgs/denial/package.nix {
            denial-flutter-engine-prebuilt = enginePrebuilt;
            denial-flutter-shell-prebuilt = shellPrebuilt;
            denial-flutter-engine-source = engineSource;
            denial-flutter-shell-source = shellSource;
          };
        in
        {
          denial-flutter-engine = enginePrebuilt;
          denial-flutter-shell = shellPrebuilt;
          inherit denial;
          denial-flutter-engine-source = engineSource;
          denial-flutter-shell-source = shellSource;
        };

      packages = nixpkgs.lib.genAttrs systems mkPackages;

      nixosModules.denial = import ./nix/module.nix;
      nixosModules.default = self.nixosModules.denial;
    };
}
