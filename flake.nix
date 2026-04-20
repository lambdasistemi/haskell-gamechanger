{
  description = "haskell-gamechanger — Haskell client for the GameChanger Cardano wallet";

  nixConfig = {
    extra-substituters = [ "https://cache.iog.io" ];
    extra-trusted-public-keys = [
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
    ];
  };

  inputs = {
    haskellNix.url = "github:input-output-hk/haskell.nix";
    nixpkgs.follows = "haskellNix/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    CHaP = {
      url = "github:intersectmbo/cardano-haskell-packages?ref=repo";
      flake = false;
    };
    dev-assets-mkdocs.url = "github:paolino/dev-assets?dir=mkdocs";
  };

  outputs =
    { self
    , nixpkgs
    , flake-utils
    , haskellNix
    , CHaP
    , dev-assets-mkdocs
    , ...
    }:
    flake-utils.lib.eachSystem [ "x86_64-linux" ] (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ haskellNix.overlay ];
          inherit (haskellNix) config;
        };

        project = import ./nix/project.nix {
          inherit pkgs CHaP dev-assets-mkdocs system;
        };

        checks = import ./nix/checks.nix {
          inherit pkgs project;
        };

        apps = import ./nix/apps.nix {
          inherit pkgs checks;
          hgc = project.hsPkgs.haskell-gamechanger.components.exes.hgc;
        };
      in
      {
        packages = {
          default = project.hsPkgs.haskell-gamechanger.components.exes.hgc;
          hgc = project.hsPkgs.haskell-gamechanger.components.exes.hgc;
        };

        devShells.default = project.shell;

        inherit checks apps;
      });
}
