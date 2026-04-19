{ pkgs, module }:

let
  lib = pkgs.lib;

  evalWith = lgEnable: lib.evalModules {
    modules = [
      module
      {
        windowsVM = {
          enable = true;
          isoPath = "/tmp/Win11.iso";
          gpu.pciId = "0000:01:00.0";
          lookingGlass.enable = lgEnable;
          lookingGlass.sharedMemoryMB = 32;
        };
      }
      ({ lib, ... }: {
        options = {
          boot = lib.mkOption { type = lib.types.anything; default = {}; };
          environment = lib.mkOption { type = lib.types.anything; default = {}; };
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
        config = {
          _module.args = { inherit pkgs; };
          # Provide boot.kernelPackages so looking-glass.nix can resolve kvmfr
          boot.kernelPackages = pkgs.linuxPackages;
        };
      })
    ];
  };

  enabledConfig = evalWith true;
  disabledConfig = evalWith false;

  xmlEnabled = enabledConfig.config.environment.etc."libvirt/qemu/win11.xml".source;
  xmlDisabled = disabledConfig.config.environment.etc."libvirt/qemu/win11.xml".source;
in
{
  # Validate XML with IVSHMEM is still valid
  lg-xml-valid = pkgs.runCommand "lg-xml-valid" {
    nativeBuildInputs = [ pkgs.libvirt ];
  } ''
    virt-xml-validate ${xmlEnabled} domain
    echo "PASS: domain XML with IVSHMEM is valid"
    touch $out
  '';

  # Check shmem element is present when enabled
  lg-shmem-present = pkgs.runCommand "lg-shmem-present" {} ''
    xml="${xmlEnabled}"

    grep -q 'shmem name="looking-glass"' "$xml" || (echo "FAIL: missing shmem element"; exit 1)
    grep -q 'ivshmem-plain' "$xml" || (echo "FAIL: missing ivshmem-plain model"; exit 1)
    grep -q '<size unit="M">32</size>' "$xml" || (echo "FAIL: wrong shmem size"; exit 1)

    echo "PASS: IVSHMEM shmem element present with correct config"
    touch $out
  '';

  # Check shmem element is absent when disabled
  lg-shmem-absent = pkgs.runCommand "lg-shmem-absent" {} ''
    xml="${xmlDisabled}"

    if grep -q 'shmem' "$xml"; then
      echo "FAIL: shmem element should not be present when Looking Glass is disabled"
      exit 1
    fi

    echo "PASS: no shmem element when Looking Glass disabled"
    touch $out
  '';

  # Check kernel module config when enabled
  lg-kernel-config = let
    bootCfg = enabledConfig.config.boot;
    kernelModules = builtins.toJSON (bootCfg.kernelModules or []);
    modprobeConfig = bootCfg.extraModprobeConfig or "";
  in pkgs.runCommand "lg-kernel-config" {} ''
    echo '${kernelModules}' | grep -q 'kvmfr' || (echo "FAIL: kvmfr not in kernelModules"; exit 1)
    echo '${modprobeConfig}' | grep -q 'static_size_mb=32' || (echo "FAIL: wrong modprobe config"; exit 1)

    echo "PASS: kvmfr kernel module configured correctly"
    touch $out
  '';

  # Check udev rule when enabled
  lg-udev-rule = pkgs.runCommand "lg-udev-rule" {} ''
    udev='${enabledConfig.config.services.udev.extraRules}'

    echo "$udev" | grep -q 'SUBSYSTEM=="kvmfr"' || (echo "FAIL: missing kvmfr udev rule"; exit 1)
    echo "$udev" | grep -q 'GROUP="kvm"' || (echo "FAIL: missing kvm group in udev rule"; exit 1)
    echo "$udev" | grep -q 'MODE="0660"' || (echo "FAIL: missing mode in udev rule"; exit 1)

    echo "PASS: kvmfr udev rule configured correctly"
    touch $out
  '';

  # Check looking-glass-client is in system packages when enabled
  lg-client-package = pkgs.runCommand "lg-client-package" {} ''
    packages='${builtins.toJSON (map (p: p.pname or p.name or "unknown") enabledConfig.config.environment.systemPackages)}'

    echo "$packages" | grep -q 'looking-glass-client' || (echo "FAIL: looking-glass-client not in systemPackages"; exit 1)

    echo "PASS: looking-glass-client in system packages"
    touch $out
  '';

  # Check no Looking Glass config when disabled
  lg-disabled-clean = let
    bootCfg = disabledConfig.config.boot;
    kernelModules = builtins.toJSON (bootCfg.kernelModules or []);
    modprobeConfig = bootCfg.extraModprobeConfig or "";
    udev = disabledConfig.config.services.udev.extraRules or "";
    packages = builtins.toJSON (map (p: p.pname or p.name or "unknown") (disabledConfig.config.environment.systemPackages or []));
  in pkgs.runCommand "lg-disabled-clean" {} ''
    if echo '${kernelModules}' | grep -q 'kvmfr'; then
      echo "FAIL: kvmfr should not be in kernelModules when disabled"
      exit 1
    fi

    if echo '${modprobeConfig}' | grep -q 'kvmfr'; then
      echo "FAIL: kvmfr modprobe config should not be present when disabled"
      exit 1
    fi

    if echo '${udev}' | grep -q 'kvmfr'; then
      echo "FAIL: kvmfr udev rule should not be present when disabled"
      exit 1
    fi

    if echo '${packages}' | grep -q 'looking-glass-client'; then
      echo "FAIL: looking-glass-client should not be in packages when disabled"
      exit 1
    fi

    echo "PASS: no Looking Glass config when disabled"
    touch $out
  '';
}
