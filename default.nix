# NUR evaluates repositories by importing this file with its own pinned
# nixpkgs and no flake support, so this is the non-flake entry point. It
# applies the same overlay the flake uses, exposes the same package set, and
# additionally exports the overlay and the NixOS module so NUR consumers can
# use them the standard way (`nur.repos.YeFaDa.overlays.default` +
# `nur.repos.YeFaDa.nixosModules.denial`; the module needs the overlay
# applied for its `pkgs.denial` default to resolve).
{ pkgs ? import <nixpkgs> {} }:
let
  denialOverlay = import ./overlay.nix;
in
(import ./nix/packages.nix { pkgs = pkgs.extend denialOverlay; }) // {
  overlays.default = denialOverlay;
  nixosModules.denial = import ./nix/module.nix;
  nixosModules.default = import ./nix/module.nix;
}
