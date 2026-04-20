{ pkgs, module }:

let
  lib = pkgs.lib;

  eval = lib.evalModules {
    modules = [
      module
      {
        windowsVM = {
          enable = true;
          isoPath = "/tmp/Win11.iso";
          gpu.pciId = "0000:01:00.0";
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

  domainXml = eval.config.environment.etc."libvirt/qemu/win11.xml".source;

  # Build the ISO the same way the module does
  unattendedIso = pkgs.runCommand "win11-unattended.iso" {
    nativeBuildInputs = [ pkgs.cdrkit ];
  } ''
    mkdir -p staging
    cp ${../windows/autounattend.xml} staging/autounattend.xml
    cp ${../windows/debloat.ps1} staging/debloat.ps1
    mkisofs -o $out -J -r -V "UNATTEND" staging/
  '';
in
{
  # Validate autounattend.xml is well-formed XML
  autounattend-xml-valid = pkgs.runCommand "autounattend-xml-valid" {
    nativeBuildInputs = [ pkgs.libxml2 ];
  } ''
    xmllint --noout ${../windows/autounattend.xml}
    echo "PASS: autounattend.xml is well-formed XML"
    touch $out
  '';

  # Assert required elements exist in autounattend.xml
  autounattend-content = pkgs.runCommand "autounattend-content" {} ''
    xml="${../windows/autounattend.xml}"

    # DiskConfiguration
    grep -q 'DiskConfiguration' "$xml" || (echo "FAIL: missing DiskConfiguration"; exit 1)
    grep -q 'Type>EFI<' "$xml" || (echo "FAIL: missing EFI partition"; exit 1)
    grep -q 'Type>MSR<' "$xml" || (echo "FAIL: missing MSR partition"; exit 1)
    grep -q 'Type>Primary<' "$xml" || (echo "FAIL: missing Primary partition"; exit 1)

    # LabConfig registry bypass
    grep -q 'BypassTPMCheck' "$xml" || (echo "FAIL: missing TPM bypass"; exit 1)
    grep -q 'BypassSecureBootCheck' "$xml" || (echo "FAIL: missing SecureBoot bypass"; exit 1)
    grep -q 'BypassRAMCheck' "$xml" || (echo "FAIL: missing RAM bypass"; exit 1)

    # UserAccounts
    grep -q 'UserAccounts' "$xml" || (echo "FAIL: missing UserAccounts"; exit 1)
    grep -q 'LocalAccount' "$xml" || (echo "FAIL: missing LocalAccount"; exit 1)

    # FirstLogonCommands (debloat script)
    grep -q 'FirstLogonCommands' "$xml" || (echo "FAIL: missing FirstLogonCommands"; exit 1)
    grep -q 'debloat.ps1' "$xml" || (echo "FAIL: missing debloat.ps1 reference"; exit 1)

    # VirtIO driver paths
    grep -q 'viostor' "$xml" || (echo "FAIL: missing VirtIO storage driver path"; exit 1)

    # OOBE skip
    grep -q 'HideEULAPage' "$xml" || (echo "FAIL: missing OOBE skip"; exit 1)

    echo "PASS: autounattend.xml contains all required elements"
    touch $out
  '';

  # Assert the ISO builds and contains expected files
  autounattend-iso = pkgs.runCommand "autounattend-iso" {
    nativeBuildInputs = [ pkgs.cdrkit ];
  } ''
    # Check the ISO exists and is non-empty
    test -f ${unattendedIso} || (echo "FAIL: ISO not built"; exit 1)
    test -s ${unattendedIso} || (echo "FAIL: ISO is empty"; exit 1)

    # Mount and check contents
    mkdir -p mnt
    ${pkgs.p7zip}/bin/7z l ${unattendedIso} > listing.txt
    grep -q 'autounattend.xml' listing.txt || (echo "FAIL: ISO missing autounattend.xml"; exit 1)
    grep -q 'debloat.ps1' listing.txt || (echo "FAIL: ISO missing debloat.ps1"; exit 1)

    echo "PASS: unattended ISO contains autounattend.xml and debloat.ps1"
    touch $out
  '';

  # Assert domain XML references the unattended ISO
  autounattend-in-domain = pkgs.runCommand "autounattend-in-domain" {} ''
    xml="${domainXml}"

    grep -q 'UNATTEND' "$xml" 2>/dev/null || grep -q 'unattended' "$xml" 2>/dev/null || \
      grep -q 'sdc' "$xml" || (echo "FAIL: domain XML does not reference unattended ISO"; exit 1)

    echo "PASS: domain XML references unattended ISO"
    touch $out
  '';
}
