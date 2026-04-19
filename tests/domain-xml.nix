{ pkgs, module }:

let
  lib = pkgs.lib;

  # Evaluate the module with all required options to get the domain XML
  eval = lib.evalModules {
    modules = [
      module
      {
        windowsVM = {
          enable = true;
          isoPath = "/tmp/Win11.iso";
          gpu.pciId = "0000:00:02.0";
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

  domainXMLFile = eval.config.environment.etc."libvirt/qemu/win11.xml".source;
in
{
  # Validate the domain XML with virt-xml-validate
  domain-xml-valid = pkgs.runCommand "domain-xml-valid" {
    nativeBuildInputs = [ pkgs.libvirt ];
  } ''
    echo "Validating domain XML..."
    cat ${domainXMLFile}
    virt-xml-validate ${domainXMLFile} domain
    echo "PASS: Domain XML is valid"
    touch $out
  '';

  # Check that essential elements are present in the XML
  domain-xml-content = pkgs.runCommand "domain-xml-content" {} ''
    xml="${domainXMLFile}"

    echo "Checking domain XML content..."

    grep -q '<name>win11</name>' "$xml" || (echo "FAIL: missing domain name"; exit 1)
    grep -q 'type="kvm"' "$xml" || (echo "FAIL: missing KVM type"; exit 1)
    grep -q 'machine="pc-q35' "$xml" || (echo "FAIL: missing Q35 machine type"; exit 1)
    grep -q 'host-passthrough' "$xml" || (echo "FAIL: missing host-passthrough CPU"; exit 1)
    grep -q 'type="pflash"' "$xml" || (echo "FAIL: missing UEFI firmware (pflash loader)"; exit 1)
    grep -q 'tpm-crb' "$xml" || (echo "FAIL: missing TPM"; exit 1)
    grep -q '<hyperv' "$xml" || (echo "FAIL: missing Hyper-V enlightenments"; exit 1)
    grep -q 'hypervclock' "$xml" || (echo "FAIL: missing hypervclock"; exit 1)
    grep -q 'localtime' "$xml" || (echo "FAIL: missing localtime clock"; exit 1)
    grep -q 'win11.qcow2' "$xml" || (echo "FAIL: missing qcow2 disk"; exit 1)
    grep -q '/tmp/Win11.iso' "$xml" || (echo "FAIL: missing Windows ISO path"; exit 1)
    grep -q 'virtio-win' "$xml" || (echo "FAIL: missing VirtIO driver ISO"; exit 1)
    grep -q 'model type="virtio"' "$xml" || (echo "FAIL: missing VirtIO NIC"; exit 1)

    echo "PASS: All expected elements present in domain XML"
    touch $out
  '';
}
