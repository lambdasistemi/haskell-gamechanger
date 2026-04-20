{ pkgs, project, ... }:

let
  hsPkgs = project.hsPkgs.haskell-gamechanger;
  shell = project.shell;
in
{
  library = hsPkgs.components.library;
  exe = hsPkgs.components.exes.hgc;
  tests = hsPkgs.components.tests.test;

  lint = pkgs.writeShellApplication {
    name = "lint";
    runtimeInputs = shell.nativeBuildInputs ++ shell.buildInputs;
    excludeShellChecks = [ "SC2046" "SC2086" ];
    text = ''
      cd "${./..}"
      fourmolu -m check $(find src app test -name '*.hs')
      cabal-fmt -c haskell-gamechanger.cabal
      hlint src app test
    '';
  };
}
