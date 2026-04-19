{ pkgs, module }:

pkgs.testers.nixosTest {
  name = "vm-basic";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ module ];

    windowsVM = {
      enable = true;
      isoPath = "/tmp/Win11.iso";
      gpu.pciId = "0000:00:02.0";
    };

    # Host prerequisites required by windowsVM assertions
    boot.kernelParams = [ "intel_iommu=on" "iommu=pt" ];
    boot.initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];

    virtualisation.libvirtd = {
      enable = true;
      qemu.swtpm.enable = true;
    };

    # Provide a dummy ISO so virsh define doesn't complain about missing files
    system.activationScripts.dummyIso = ''
      mkdir -p /tmp
      touch /tmp/Win11.iso
    '';
  };

  testScript = ''
    machine.start()
    machine.wait_for_unit("libvirtd.service")
    machine.wait_for_unit("windowsvm-disk.service")
    machine.wait_for_unit("windowsvm-define.service")

    # Verify the domain XML file is deployed
    machine.succeed("test -f /etc/libvirt/qemu/win11.xml")

    # Validate the XML
    machine.succeed("virt-xml-validate /etc/libvirt/qemu/win11.xml domain")

    # Domain should already be defined by the systemd service
    result = machine.succeed("virsh list --all")
    assert "win11" in result, f"win11 not found in virsh list output: {result}"
    assert "shut off" in result, f"win11 not in 'shut off' state: {result}"

    # Verify the qcow2 disk image was created
    machine.succeed("test -f /var/lib/libvirt/images/win11.qcow2")
  '';
}
