{ pkgs, module }:

let
  lib = pkgs.lib;

  evalWithGpu = { pciId, audioFunction ? null }: lib.evalModules {
    modules = [
      module
      {
        windowsVM = {
          enable = true;
          isoPath = "/tmp/Win11.iso";
          gpu = {
            inherit pciId audioFunction;
          };
        };
      }
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
        config = {
          _module.args = { inherit pkgs; };
          boot.kernelPackages = pkgs.linuxPackages;
        };
      })
    ];
  };

  xmlFor = args: (evalWithGpu args).config.environment.etc."libvirt/qemu/win11.xml".source;
in
{
  # Validate GPU-inclusive XML (no audio)
  gpu-xml-valid = pkgs.runCommand "gpu-xml-valid" {
    nativeBuildInputs = [ pkgs.libvirt ];
  } ''
    virt-xml-validate ${xmlFor { pciId = "0000:01:00.0"; }} domain
    echo "PASS: GPU-inclusive domain XML is valid"
    touch $out
  '';

  # Check PCI address is correctly parsed: 0000:01:00.0
  gpu-pci-address = pkgs.runCommand "gpu-pci-address" {} ''
    xml="${xmlFor { pciId = "0000:01:00.0"; }}"

    # GPU device
    grep -q 'domain="0x0000"' "$xml" || (echo "FAIL: wrong PCI domain"; exit 1)
    grep -q 'bus="0x01"' "$xml" || (echo "FAIL: wrong PCI bus"; exit 1)
    grep -q 'slot="0x00"' "$xml" || (echo "FAIL: wrong PCI slot"; exit 1)
    grep -q 'function="0x0"' "$xml" || (echo "FAIL: wrong PCI function"; exit 1)

    # No audio device by default
    if grep -c 'hostdev mode="subsystem" type="pci"' "$xml" | grep -q '^2$'; then
      echo "FAIL: should only have 1 PCI hostdev when audioFunction is null"
      exit 1
    fi

    # Multifunction flag
    grep -q 'multifunction="on"' "$xml" || (echo "FAIL: missing multifunction"; exit 1)

    echo "PASS: PCI address correctly parsed for 0000:01:00.0"
    touch $out
  '';

  # Test with different PCI address: 0000:0a:00.0
  gpu-pci-address-alt = pkgs.runCommand "gpu-pci-address-alt" {} ''
    xml="${xmlFor { pciId = "0000:0a:00.0"; }}"

    grep -q 'bus="0x0a"' "$xml" || (echo "FAIL: wrong PCI bus for 0a"; exit 1)

    echo "PASS: PCI address correctly parsed for 0000:0a:00.0"
    touch $out
  '';

  # Validate XML with GPU audio function
  gpu-audio-valid = pkgs.runCommand "gpu-audio-valid" {
    nativeBuildInputs = [ pkgs.libvirt ];
  } ''
    virt-xml-validate ${xmlFor { pciId = "0000:01:00.0"; audioFunction = "1"; }} domain
    echo "PASS: GPU + audio domain XML is valid"
    touch $out
  '';

  # Check audio device appears with correct function
  gpu-audio-present = pkgs.runCommand "gpu-audio-present" {} ''
    xml="${xmlFor { pciId = "0000:01:00.0"; audioFunction = "1"; }}"

    grep -q 'function="0x1"' "$xml" || (echo "FAIL: missing GPU audio device"; exit 1)

    # Should have 2 PCI hostdev entries
    count=$(grep -c 'hostdev mode="subsystem" type="pci"' "$xml")
    [ "$count" -eq 2 ] || (echo "FAIL: expected 2 PCI hostdev, got $count"; exit 1)

    echo "PASS: GPU audio device present at function 0x1"
    touch $out
  '';
}
