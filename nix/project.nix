{ pkgs, CHaP, dev-assets-mkdocs, system, ... }:

let
  indexState = "2026-04-19T00:00:00Z";

  shell = { pkgs, ... }: {
    tools = {
      cabal = { index-state = indexState; };
      cabal-fmt = {
        index-state = indexState;
        compiler-nix-name = "ghc984";
      };
      fourmolu = { index-state = indexState; };
      hlint = { index-state = indexState; };
    };
    withHoogle = false;
    buildInputs =
      [ pkgs.just pkgs.nodejs ]
      ++ dev-assets-mkdocs.devShells.${system}.default.buildInputs or [ ];
    inputsFrom = [ dev-assets-mkdocs.devShells.${system}.default ];
  };

  mkProject = { lib, pkgs, ... }: {
    name = "haskell-gamechanger";
    src = ./..;
    compiler-nix-name = "ghc9123";
    inputMap."https://chap.intersectmbo.org/" = CHaP;
    shell = shell { inherit pkgs; };
    modules = [ ];
  };

  project = pkgs.haskell-nix.cabalProject' mkProject;
in
project
