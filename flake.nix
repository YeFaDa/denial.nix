{
  description = "Denial, a Flutter-native Wayland compositor — nixpkgs-style packaging";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system}.extend self.overlays.default;
    in
    {
      overlays.default = final: prev: {
        denial-flutter-engine = final.callPackage ./pkgs/denial-flutter-engine/package.nix { };
        denial-flutter-shell = final.callPackage ./pkgs/denial-flutter-shell/package.nix { };
        denial = final.callPackage ./pkgs/denial/package.nix { };
      };

      packages.${system} = {
        inherit (pkgs) denial denial-flutter-engine denial-flutter-shell;
        default = pkgs.denial;
      };

      nixosModules.denial = import ./nix/module.nix;
      nixosModules.default = self.nixosModules.denial;
    };
}
