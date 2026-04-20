{ pkgs, checks, hgc, ... }:

let
  runnable = {
    inherit hgc;
    inherit (checks) tests lint;
  };
in
builtins.mapAttrs
  (_: drv: {
    type = "app";
    program = pkgs.lib.getExe drv;
  })
  runnable
