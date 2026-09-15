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

      # The module's package defaults are looked up as `pkgs.denial` and
      # `pkgs."denial-ui-development"`, so the overlay has to be applied for
      # them to resolve. Doing it here means a consumer only imports the
      # module; `overlays.default` stays exported for anyone who wants
      # `pkgs.denial` outside the module. Overlays are additive, so a host
      # that already lists it gets the same attribute values twice, not a
      # conflict.
      nixosModules.denial = {
        imports = [ ./nix/module.nix ];
        nixpkgs.overlays = [ self.overlays.default ];
      };
      nixosModules.default = self.nixosModules.denial;
    };
}
