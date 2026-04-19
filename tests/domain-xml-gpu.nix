{ pkgs, module }:

let
  lib = pkgs.lib;

  evalWithGpu = pciId: lib.evalModules {
    modules = [
      module
      {
        windowsVM = {
          enable = true;
          isoPath = "/tmp/Win11.iso";
          gpu.pciId = pciId;
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
        config._module.args = { inherit pkgs; };
      })
    ];
  };

  xmlFor = pciId: (evalWithGpu pciId).config.environment.etc."libvirt/qemu/win11.xml".source;
in
{
  # Validate GPU-inclusive XML
  gpu-xml-valid = pkgs.runCommand "gpu-xml-valid" {
    nativeBuildInputs = [ pkgs.libvirt ];
  } ''
    virt-xml-validate ${xmlFor "0000:01:00.0"} domain
    echo "PASS: GPU-inclusive domain XML is valid"
    touch $out
  '';

  # Check PCI address is correctly parsed: 0000:01:00.0
  gpu-pci-address = pkgs.runCommand "gpu-pci-address" {} ''
    xml="${xmlFor "0000:01:00.0"}"

    # GPU device
    grep -q 'domain="0x0000"' "$xml" || (echo "FAIL: wrong PCI domain"; exit 1)
    grep -q 'bus="0x01"' "$xml" || (echo "FAIL: wrong PCI bus"; exit 1)
    grep -q 'slot="0x00"' "$xml" || (echo "FAIL: wrong PCI slot"; exit 1)
    grep -q 'function="0x0"' "$xml" || (echo "FAIL: wrong PCI function"; exit 1)

    # Audio device (function 1)
    grep -q 'function="0x1"' "$xml" || (echo "FAIL: missing GPU audio device"; exit 1)

    # Multifunction flag
    grep -q 'multifunction="on"' "$xml" || (echo "FAIL: missing multifunction"; exit 1)

    echo "PASS: PCI address correctly parsed for 0000:01:00.0"
    touch $out
  '';

  # Test with different PCI address: 0000:0a:00.0
  gpu-pci-address-alt = pkgs.runCommand "gpu-pci-address-alt" {} ''
    xml="${xmlFor "0000:0a:00.0"}"

    grep -q 'bus="0x0a"' "$xml" || (echo "FAIL: wrong PCI bus for 0a"; exit 1)

    echo "PASS: PCI address correctly parsed for 0000:0a:00.0"
    touch $out
  '';
}
