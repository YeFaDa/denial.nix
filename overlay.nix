# The overlay shared by both entry points:
#   - flake.nix applies it over the flake's nixpkgs input;
#   - default.nix applies it over whatever nixpkgs NUR passes in.
# It must stay free of flake inputs: the NUR entry point evaluates without
# flake support and without eval-time network access, so everything it needs
# (Rust toolchain, Dart SDK) is pinned inside this repository.
final: prev:
let
    revisions = import ./pkgs/denial-flutter-engine/revisions.nix { lib = final.lib; };

    # Rust toolchain pinned to upstream's rust-toolchain.toml; the vendored
    # copy at pkgs/denial/rust-toolchain.toml is overwritten by
    # scripts/update-release-pins on each release. Builds must not drift to
    # whatever rustc the surrounding nixpkgs happens to ship: upstream tracks
    # current stable Rust and uses its newest stabilized APIs in-tree.
    rustToolchain = final.callPackage ./pkgs/rust-toolchain { };
    rustPlatformPinned = final.makeRustPlatform {
      inherit (rustToolchain) rustc cargo;
    };

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
    # Also drop gclient2nix's joblib disk cache. It has no concurrency
    # protection: writes use open(..., "wb") (truncate-then-write), so a
    # worker reading mid-write gets a truncated func_code.py, which
    # extract_first_line() reports as first_line=-1. That looks like the
    # function changed, so joblib warns and calls clear() -- which
    # deletes the whole cache directory under the other workers, and the
    # rewrite of func_code.py then fails with FileNotFoundError. With
    # Parallel(n_jobs=20) this is not a rare race, it is the normal case.
    #
    # The cache is worthless here anyway: every run starts from a fresh
    # mktemp -d, so it never survives to be reused.

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
        --replace-fail 'else None,' 'else {"host_os": "linux", "host_cpu": "${gclientHostCpu}"},' \
        --replace-fail 'Memory(user_cache_dir("gclient2nix"), verbose=0)' 'Memory(None, verbose=0)'
      wrapProgram "$out/bin/gclient2nix" \
        --set PATH ${final.lib.makeBinPath [ final.nurl ]}
    '';
    # Pinned Dart SDK. Reuses nixpkgs' `dart-bin` derivation wholesale
    # (same unpack / dontStrip / bin-patchelf install) and only swaps
    # `version` and `src`, the same way nixpkgs' own flutter package
    # pins the Dart bundled with older Flutter releases. The version
    # must match the Dart revision locked in upstream's Flutter DEPS
    # graph; scripts/update-release-pins keeps
    # pkgs/dart-sdk/{version,sdks}.nix in step with it. Pinning here
    # instead of via a second nixpkgs input means the version survives
    # nixpkgs moving on, and works against whatever nixpkgs the flake
    # is evaluated with (NUR overrides the input).
    dartSdk =
      let
        dartVersion = import ./pkgs/dart-sdk/version.nix;
        dartSystemName = {
          "x86_64-linux" = "linux-x64";
          "aarch64-linux" = "linux-arm64";
        };
        system = prev.stdenv.hostPlatform.system;
        dartSdks = import ./pkgs/dart-sdk/sdks.nix;
      in
      final.dart-bin.overrideAttrs (old: {
        version = dartVersion;
        src = final.fetchurl {
          url = "https://storage.googleapis.com/dart-archive/channels/stable/release/${dartVersion}/sdk/dartsdk-${dartSystemName.${system} or (throw "pkgs/dart-sdk: unsupported system ${system}")}-release.zip";
          hash = (dartSdks.${dartVersion} or (throw "pkgs/dart-sdk/sdks.nix has no entry for Dart ${dartVersion}")).${system} or (throw "pkgs/dart-sdk/sdks.nix has no ${system} hash for Dart ${dartVersion}");
        };
      });
    engineSource = final.callPackage ./pkgs/denial-flutter-engine/source.nix {
      dart = dartSdk;
      inherit gclient2nix revisions;
    };
    flutterToolsSource = final.callPackage ./pkgs/denial-flutter-engine/flutter-tools.nix {
      dart = dartSdk;
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
      dart = dartSdk;
      inherit gclient2nix;
      flutterTools = flutterToolsSource;
    };
    shellSource = final.callPackage ./pkgs/denial-flutter-shell/source.nix {
      flutter = flutterSdkSource;
      denial-flutter-engine-source = engineSource;
      inherit revisions materialFonts gradleWrapper;
    };
    settingsSource = final.callPackage ./pkgs/denial-settings/source.nix {
      dart = dartSdk;
      flutter = flutterSdkSource;
      denial-flutter-engine-source = engineSource;
      inherit revisions materialFonts gradleWrapper;
    };
    denialSettings = final.callPackage ./pkgs/denial-settings/package.nix {
      denialSettingsSource = settingsSource;
    };
    denial = final.callPackage ./pkgs/denial/package.nix {
      rustPlatform = rustPlatformPinned;
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
    denialUi = final.callPackage ./pkgs/denial-ui/package.nix {
      rustPlatform = rustPlatformPinned;
    };
    denialUiDevelopmentSource = final.callPackage ./pkgs/denial-ui-development/source.nix {
      flutter = flutterSdkSource;
      flutterTools = flutterToolsSource;
      denial-flutter-engine-debug-source = engineDebug;
      denial-flutter-engine-profile-source = engineProfile;
      engineArtifacts = engineArtifacts;
      denialUi = denialUi;
      inherit materialFonts gradleWrapper;
    };

    updateCheck = final.callPackage ./pkgs/update-check/package.nix { dart = dartSdk; };
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
}
