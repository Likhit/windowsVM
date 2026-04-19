{ pkgs, module }:

let
  lib = pkgs.lib;

  # Evaluate a NixOS module configuration
  eval = moduleConfig: lib.evalModules {
    modules = [
      module
      moduleConfig
      ({ lib, ... }: {
        options = {
          boot = lib.mkOption { type = lib.types.anything; default = {}; };
          environment = lib.mkOption {
            type = lib.types.submodule {
              options = {
                systemPackages = lib.mkOption { type = lib.types.listOf lib.types.package; default = []; };
                etc = lib.mkOption { type = lib.types.anything; default = {}; };
              };
            };
            default = {};
          };
          services = lib.mkOption { type = lib.types.anything; default = {}; };
          virtualisation = lib.mkOption { type = lib.types.anything; default = {}; };
          networking = lib.mkOption { type = lib.types.anything; default = {}; };
          users = lib.mkOption { type = lib.types.anything; default = {}; };
          systemd = lib.mkOption { type = lib.types.anything; default = {}; };
          assertions = lib.mkOption {
            type = lib.types.listOf lib.types.anything;
            default = [];
          };
          warnings = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [];
          };
        };
        config._module.args = { inherit pkgs; };
      })
    ];
  };

  # Check if we can access the enable option (proves module evaluates)
  evalSucceeds = moduleConfig:
    let
      result = eval moduleConfig;
      evaluated = builtins.tryEval result.config.windowsVM.enable;
    in
      evaluated.success;

  # For enabled configs, check that all options are accessible
  evalEnabledSucceeds = moduleConfig:
    let
      result = eval moduleConfig;
      evaluated = builtins.tryEval (builtins.deepSeq result.config.windowsVM result);
    in
      evaluated.success;

  # Check that evaluation fails (required option missing)
  evalFails = moduleConfig:
    let
      result = eval moduleConfig;
      evaluated = builtins.tryEval (builtins.deepSeq result.config.windowsVM result);
    in
      !evaluated.success;

in
{
  # Test: module evaluates with enable = false
  eval-disabled = pkgs.runCommand "eval-disabled" {} ''
    ${if evalSucceeds { windowsVM.enable = false; }
      then "echo 'PASS: module evaluates with enable = false'"
      else builtins.throw "FAIL: module should evaluate cleanly with enable = false"}
    touch $out
  '';

  # Test: module evaluates with enable = true and all required options
  eval-enabled = pkgs.runCommand "eval-enabled" {} ''
    ${if evalEnabledSucceeds {
        windowsVM = {
          enable = true;
          isoPath = "/path/to/Win11.iso";
          gpu.pciId = "0000:00:02.0";
        };
      }
      then "echo 'PASS: module evaluates with all required options'"
      else builtins.throw "FAIL: module should evaluate cleanly with all required options set"}
    touch $out
  '';

  # Test: evaluation fails when isoPath is missing
  eval-missing-iso = pkgs.runCommand "eval-missing-iso" {} ''
    ${if evalFails {
        windowsVM = {
          enable = true;
          gpu.pciId = "0000:00:02.0";
        };
      }
      then "echo 'PASS: evaluation fails when isoPath is missing'"
      else builtins.throw "FAIL: evaluation should fail when isoPath is missing"}
    touch $out
  '';

  # Test: module evaluates without gpu.pciId (SPICE-only mode)
  eval-no-gpu = pkgs.runCommand "eval-no-gpu" {} ''
    ${if evalEnabledSucceeds {
        windowsVM = {
          enable = true;
          isoPath = "/path/to/Win11.iso";
        };
      }
      then "echo 'PASS: module evaluates without gpu.pciId (SPICE-only)'"
      else builtins.throw "FAIL: module should evaluate without gpu.pciId"}
    touch $out
  '';
}
