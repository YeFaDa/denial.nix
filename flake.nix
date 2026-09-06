{
  description = "Denial, a Flutter-native Wayland compositor — nixpkgs-style packaging";
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
    in
    {
      # Shared with default.nix, which is what NUR evaluates (no flake
      # support): both entry points apply the same overlay over whichever
      # nixpkgs they are given.
      overlays.default = import ./overlay.nix;

      packages = nixpkgs.lib.genAttrs systems (system:
        import ./nix/packages.nix {
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ (import ./overlay.nix) ];
          };
        });

      nixosModules.denial = import ./nix/module.nix;
      nixosModules.default = self.nixosModules.denial;
    };
}
