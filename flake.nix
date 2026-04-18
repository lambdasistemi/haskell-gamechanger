{
  description = "haskell-gamechanger — Haskell client for the GameChanger Cardano wallet";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    dev-assets-mkdocs.url = "github:paolino/dev-assets?dir=mkdocs";
  };

  outputs = { self, nixpkgs, flake-utils, dev-assets-mkdocs }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
      in
      {
        devShells.default = pkgs.mkShell {
          inputsFrom = [ dev-assets-mkdocs.devShells.${system}.default ];
          packages = [ pkgs.just ];
        };
      });
}
