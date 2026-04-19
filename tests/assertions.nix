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

  # Get failed assertions from a config
  getFailedAssertions = moduleConfig:
    let
      result = eval moduleConfig;
      assertions = result.config.assertions;
    in
      builtins.filter (a: !a.assertion) assertions;

  # Base config with windowsVM enabled and required options
  baseConfig = {
    windowsVM = {
      enable = true;
      isoPath = "/path/to/Win11.iso";
      gpu.pciId = "0000:00:02.0";
    };
  };

  # Full valid host config with all prerequisites met
  fullHostConfig = {
    windowsVM = {
      enable = true;
      isoPath = "/path/to/Win11.iso";
      gpu.pciId = "0000:00:02.0";
    };
    boot = {
      kernelParams = [ "intel_iommu=on" "iommu=pt" ];
      initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
    };
    virtualisation.libvirtd = {
      enable = true;
      qemu.swtpm.enable = true;
    };
  };

  # Helper: check that at least one failed assertion message contains a substring
  hasFailedAssertionMatching = moduleConfig: substring:
    let
      failed = getFailedAssertions moduleConfig;
    in
      builtins.any (a: lib.hasInfix substring a.message) failed;

in
{
  # Test: missing IOMMU param fires assertion
  assert-missing-iommu = pkgs.runCommand "assert-missing-iommu" {} ''
    ${if hasFailedAssertionMatching (baseConfig // {
        boot = {
          kernelParams = [ "iommu=pt" ];
          initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
        };
        virtualisation.libvirtd = { enable = true; qemu.swtpm.enable = true; };
      }) "intel_iommu=on"
      then "echo 'PASS: missing IOMMU param fires assertion with helpful message'"
      else builtins.throw "FAIL: expected assertion about IOMMU param"}
    touch $out
  '';

  # Test: missing iommu=pt fires assertion
  assert-missing-iommu-pt = pkgs.runCommand "assert-missing-iommu-pt" {} ''
    ${if hasFailedAssertionMatching (baseConfig // {
        boot = {
          kernelParams = [ "intel_iommu=on" ];
          initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
        };
        virtualisation.libvirtd = { enable = true; qemu.swtpm.enable = true; };
      }) "iommu=pt"
      then "echo 'PASS: missing iommu=pt fires assertion'"
      else builtins.throw "FAIL: expected assertion about iommu=pt"}
    touch $out
  '';

  # Test: missing VFIO modules fires assertion
  assert-missing-vfio = pkgs.runCommand "assert-missing-vfio" {} ''
    ${if hasFailedAssertionMatching (baseConfig // {
        boot = {
          kernelParams = [ "intel_iommu=on" "iommu=pt" ];
          initrd.kernelModules = [];
        };
        virtualisation.libvirtd = { enable = true; qemu.swtpm.enable = true; };
      }) "vfio_pci"
      then "echo 'PASS: missing VFIO modules fires assertion'"
      else builtins.throw "FAIL: expected assertion about VFIO modules"}
    touch $out
  '';

  # Test: missing libvirtd fires assertion
  assert-missing-libvirtd = pkgs.runCommand "assert-missing-libvirtd" {} ''
    ${if hasFailedAssertionMatching (baseConfig // {
        boot = {
          kernelParams = [ "intel_iommu=on" "iommu=pt" ];
          initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
        };
        virtualisation.libvirtd = { enable = false; qemu.swtpm.enable = true; };
      }) "libvirtd"
      then "echo 'PASS: missing libvirtd fires assertion'"
      else builtins.throw "FAIL: expected assertion about libvirtd"}
    touch $out
  '';

  # Test: missing swtpm fires assertion
  assert-missing-swtpm = pkgs.runCommand "assert-missing-swtpm" {} ''
    ${if hasFailedAssertionMatching (baseConfig // {
        boot = {
          kernelParams = [ "intel_iommu=on" "iommu=pt" ];
          initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
        };
        virtualisation.libvirtd = { enable = true; qemu.swtpm.enable = false; };
      }) "swtpm"
      then "echo 'PASS: missing swtpm fires assertion'"
      else builtins.throw "FAIL: expected assertion about swtpm"}
    touch $out
  '';

  # Test: all prerequisites met → no assertions fire
  assert-all-met = pkgs.runCommand "assert-all-met" {} ''
    ${let failed = getFailedAssertions fullHostConfig;
      in if failed == []
        then "echo 'PASS: no assertions fire when all prerequisites met'"
        else builtins.throw "FAIL: unexpected assertions fired: ${builtins.toJSON (map (a: a.message) failed)}"}
    touch $out
  '';

  # Test: AMD IOMMU also accepted
  assert-amd-iommu = pkgs.runCommand "assert-amd-iommu" {} ''
    ${let failed = getFailedAssertions (baseConfig // {
        boot = {
          kernelParams = [ "amd_iommu=on" "iommu=pt" ];
          initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
        };
        virtualisation.libvirtd = { enable = true; qemu.swtpm.enable = true; };
      });
      in if failed == []
        then "echo 'PASS: AMD IOMMU param accepted'"
        else builtins.throw "FAIL: AMD IOMMU should be accepted"}
    touch $out
  '';

  # Test: no VFIO assertions fire when gpu.pciId is null (SPICE-only mode)
  assert-no-gpu-no-vfio = pkgs.runCommand "assert-no-gpu-no-vfio" {} ''
    ${let failed = getFailedAssertions {
        windowsVM = {
          enable = true;
          isoPath = "/path/to/Win11.iso";
        };
        virtualisation.libvirtd = { enable = true; qemu.swtpm.enable = true; };
      };
      in if failed == []
        then "echo 'PASS: no VFIO assertions when gpu.pciId is null'"
        else builtins.throw "FAIL: VFIO assertions should not fire without GPU: ${builtins.toJSON (map (a: a.message) failed)}"}
    touch $out
  '';
}
