# NUR evaluates repositories by importing this file with its own pinned
# nixpkgs and no flake support, so this is the non-flake entry point. It
# applies the same overlay the flake uses and exposes the same package set.
{ pkgs ? import <nixpkgs> {} }:
import ./nix/packages.nix {
  pkgs = pkgs.extend (import ./overlay.nix);
}
