{
  lib,
  rustPlatform,
  fetchFromGitHub,
  installShellFiles,
}:

# The `denial-ui` client, one of the four binaries in Denial's compositor
# workspace (alongside `deniald`, `denialctl` and `denial-nested`).
#
# Built here on its own rather than taken from `pkgs/denial` because the two
# need different cargo features: `deniald` wants `flutter` (which pulls in
# `kms`, `wire` and the whole Smithay stack), while `denial-ui` wants
# `ui-development`, which is just `control` and therefore only serde. Keeping
# them separate means pulling in the UI toolchain does not drag in every
# compositor system library, and vice versa.
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "denial-ui";
  version = import ../version.nix;

  src = fetchFromGitHub {
    owner = "denialwm";
    repo = "denial";
    tag = "v${finalAttrs.version}";
    hash = "sha256-qRbD0HvBJ87QWriQsx6GWdYVMnKj1Iae8QLRaxRL8T4=";
  };

  cargoRoot = "compositor";
  buildAndTestSubdir = "compositor";
  # Shared with pkgs/denial: same workspace, same lockfile, so the two can
  # never drift apart.
  cargoLock = {
    lockFile = ../denial/Cargo.lock;
    outputHashes = {
      "smithay-0.7.0" = "sha256-Dov9wh6qGuciLMTwOXM/eRA/Uo4jSvhcCqwJFdB2Vbg=";
      "smithay-drm-extras-0.1.0" = "sha256-Dov9wh6qGuciLMTwOXM/eRA/Uo4jSvhcCqwJFdB2Vbg=";
    };
  };

  strictDeps = true;

  nativeBuildInputs = [ installShellFiles ];

  buildFeatures = [ "ui-development" ];
  cargoBuildFlags = [ "--bin" "denial-ui" ];

  # Not needed: the `ui-development` feature is `control`, which is pure serde.
  # `pkgs/denial` needs a long list of system libraries and dlopen force-links
  # because of its `kms` feature; none of that is reachable from here.
  doCheck = false;

  postPatch = ''
    # Same substitution `pkgs/denial` applies. It is not on this binary's
    # compilation path -- `clipboard.rs` is a module of the `deniald` binary,
    # not of the `denial_core` library -- but keeping the two patches in step
    # means dropping it in one place cannot leave the other one building
    # against a different source tree.
    substituteInPlace compositor/src/bin/deniald/clipboard.rs \
      --replace-fail 'data.strip_circumfix(&[0xff, 0xd8], &[0xff, 0xd9])?' \
        'data.strip_prefix(&[0xff, 0xd8][..]).and_then(|d| d.strip_suffix(&[0xff, 0xd9][..]))?'
  '';

  postInstall = ''
    installManPage docs/man/denial-ui.1
  '';

  meta = {
    description = "Native client for inspecting, preparing and attaching to a Denial UI workspace";
    homepage = "https://github.com/denialwm/denial";
    license = lib.licenses.gpl3Plus;
    mainProgram = "denial-ui";
    platforms = [ "x86_64-linux" "aarch64-linux" ];
  };
})
