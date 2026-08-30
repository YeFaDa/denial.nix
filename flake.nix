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
        in
        # No platform branching here on purpose. Upstream publishes prebuilt
        # artifacts for x86_64 only, and every prebuilt consumer looks its own
        # entry up in pkgs/prebuilt-hashes.nix and throws when the current
        # platform has none. So `denial` on aarch64 fails loudly with a message
        # telling you to use `denial-source`, instead of quietly handing you an
        # x86_64 binary.
        {
          denial = pkgs.denial;
          denial-source = pkgs.denial.override { useSource = true; };
          inherit (pkgs)
            denial-flutter-engine
            denial-flutter-shell
            denial-flutter-engine-source
            denial-flutter-shell-source
            ;
          "denial-settings" = pkgs.denialSettings;
          "denial-settings-source" = pkgs.denialSettings.override { useSource = true; };
          "denial-ui-development" = pkgs.denialUiDevelopment;
          # The source-built counterpart. Unlike the prebuilt one this is not
          # restricted to x86_64: the engines come from the shared source build
          # and the three upstream-only files are pinned per platform in
          # pkgs/flutter-engine-artifacts.nix.
          "denial-ui-development-source" = pkgs."denial-ui-development-source";
          # Exposed for the same reason as `denial-flutter-engine-source`, so
          # the extra modes can be built and inspected on their own. They are
          # not `denial-ui-development-source`'s only reason to exist -- it
          # depends on both -- but they are useful when debugging an engine
          # build, since a failing debug or profile tree can be reproduced
          # without paying for the whole toolchain.
          "denial-flutter-engine-debug-source" = pkgs."denial-flutter-engine-debug-source";
          "denial-flutter-engine-profile-source" = pkgs."denial-flutter-engine-profile-source";
          "gclient2nix-linux" = pkgs.gclient2nixLinux;
          "denial-update-check" = pkgs.updateCheck;
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
          # gclient2nix leaves the host platform as `None` on some code paths;
          # fill it in so the generated dependency graph matches the machine
          # doing the build. DEPS spells `host_cpu` the same way GN does, so
          # this reuses pkgs/flutter-arch.nix rather than carrying a second
          # table that would have to be kept in step with it.
          gclientHostCpu = (import ./pkgs/flutter-arch.nix {
            system = prev.stdenv.hostPlatform.system;
          }).cpu;
          gclient2nixLinux = final.runCommand "gclient2nix-linux" {
            nativeBuildInputs = [ final.makeWrapper ];
          } ''
            mkdir -p "$out/bin"
            cp ${final.gclient2nix}/bin/.gclient2nix-wrapped "$out/bin/gclient2nix"
            chmod u+w "$out/bin/gclient2nix"
            substituteInPlace "$out/bin/gclient2nix" \
              --replace-fail 'else None,' 'else {"host_os": "linux", "host_cpu": "${gclientHostCpu}"},'
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
          settingsSource = final.callPackage ./pkgs/denial-settings/source.nix {
            dart = dartSdkSource;
            flutter = flutterSdkSource;
            denial-flutter-engine-source = engineSource;
            inherit revisions materialFonts gradleWrapper;
          };
          denialSettings = final.callPackage ./pkgs/denial-settings/package.nix {
            denialSettingsSource = settingsSource;
          };
          denial = final.callPackage ./pkgs/denial/package.nix {
            denial-flutter-engine-prebuilt = enginePrebuilt;
            denial-flutter-shell-prebuilt = shellPrebuilt;
            denial-flutter-engine-source = engineSource;
            denial-flutter-shell-source = shellSource;
            denial-settings-prebuilt = denialSettings;
            denial-settings-source = settingsSource;
            # `useSource` deliberately left at its default of `false`. Nothing
            # here may pick a platform-specific value: the prebuilt consumers
            # already throw on platforms upstream publishes nothing for, so the
            # choice stays with whoever builds the package.
          };
          denialUiDevelopment = final.callPackage ./pkgs/denial-ui-development/package.nix { };

          # The UI toolchain needs two more engine modes than anything else
          # does. Same derivation, different `runtimeMode`: upstream's three
          # `args.gn` differ in two lines, so there is nothing mode-specific
          # to maintain here beyond the name.
          engineDebug = engineSource.override { runtimeMode = "debug"; };
          engineProfile = engineSource.override { runtimeMode = "profile"; };
          engineArtifacts = final.callPackage ./pkgs/flutter-engine-artifacts.nix { };
          denialUi = final.callPackage ./pkgs/denial-ui/package.nix { };
          denialUiDevelopmentSource = final.callPackage ./pkgs/denial-ui-development/source.nix {
            flutter = flutterSdkSource;
            flutterTools = flutterToolsSource;
            denial-flutter-engine-debug-source = engineDebug;
            denial-flutter-engine-profile-source = engineProfile;
            engineArtifacts = engineArtifacts;
            denialUi = denialUi;
            inherit materialFonts gradleWrapper;
          };

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
          # Exposed so `callPackage` can resolve the `denial-settings-source`
          # argument of pkgs/denial/package.nix by name, exactly like the two
          # engine/shell `-source` arguments above. Without it, that parameter
          # would be the only one of the six that callPackage cannot auto-fill.
          denial-settings-source = settingsSource;
          denial-ui-development-source = denialUiDevelopmentSource;
          # The two extra engine modes, exposed for the same reason the release
          # one is: so they can be built and inspected on their own.
          denial-flutter-engine-debug-source = engineDebug;
          denial-flutter-engine-profile-source = engineProfile;
          flutter-engine-artifacts = engineArtifacts;
          denial-ui = denialUi;
        };
      packages = nixpkgs.lib.genAttrs systems mkPackages;

      nixosModules.denial = import ./nix/module.nix;
      nixosModules.default = self.nixosModules.denial;
    };
}
