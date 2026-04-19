{ pkgs, module }:

let
  lib = pkgs.lib;

  evalWith = usbDevices: lib.evalModules {
    modules = [
      module
      {
        windowsVM = {
          enable = true;
          isoPath = "/tmp/Win11.iso";
          gpu.pciId = "0000:01:00.0";
          usb.devices = usbDevices;
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
          boot.kernelPackages = pkgs.linuxPackages;
        };
      })
    ];
  };

  xmlFor = usbDevices: (evalWith usbDevices).config.environment.etc."libvirt/qemu/win11.xml".source;
in
{
  # XML with no USB devices is valid
  usb-none-valid = pkgs.runCommand "usb-none-valid" {
    nativeBuildInputs = [ pkgs.libvirt ];
  } ''
    virt-xml-validate ${xmlFor []} domain
    echo "PASS: XML with no USB devices is valid"
    touch $out
  '';

  # No USB hostdev elements when no devices configured
  usb-none-absent = pkgs.runCommand "usb-none-absent" {} ''
    xml="${xmlFor []}"

    if grep -q 'hostdev mode="subsystem" type="usb"' "$xml"; then
      echo "FAIL: USB hostdev elements should not be present with no devices"
      exit 1
    fi

    echo "PASS: no USB hostdev elements when no devices configured"
    touch $out
  '';

  # XML with USB devices is valid
  usb-devices-valid = pkgs.runCommand "usb-devices-valid" {
    nativeBuildInputs = [ pkgs.libvirt ];
  } ''
    virt-xml-validate ${xmlFor [
      { vendorId = "046d"; productId = "c539"; }
      { vendorId = "1532"; productId = "007a"; }
    ]} domain
    echo "PASS: XML with USB devices is valid"
    touch $out
  '';

  # USB devices appear with correct vendor/product IDs
  usb-devices-content = pkgs.runCommand "usb-devices-content" {} ''
    xml="${xmlFor [
      { vendorId = "046d"; productId = "c539"; }
      { vendorId = "1532"; productId = "007a"; }
    ]}"

    grep -q 'vendor id="0x046d"' "$xml" || (echo "FAIL: missing vendor 046d"; exit 1)
    grep -q 'product id="0xc539"' "$xml" || (echo "FAIL: missing product c539"; exit 1)
    grep -q 'vendor id="0x1532"' "$xml" || (echo "FAIL: missing vendor 1532"; exit 1)
    grep -q 'product id="0x007a"' "$xml" || (echo "FAIL: missing product 007a"; exit 1)

    # Count USB hostdev elements (should be exactly 2)
    count=$(grep -c 'hostdev mode="subsystem" type="usb"' "$xml")
    [ "$count" -eq 2 ] || (echo "FAIL: expected 2 USB hostdev elements, got $count"; exit 1)

    echo "PASS: USB devices have correct vendor/product IDs"
    touch $out
  '';
}
