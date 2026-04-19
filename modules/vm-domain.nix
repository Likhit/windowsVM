{ config, lib, pkgs, ... }:

let
  cfg = config.windowsVM;

  virtioIso = pkgs.virtio-win.src;

  # Parse PCI address "0000:00:02.0" into components
  pciParts = builtins.match "([0-9a-fA-F]+):([0-9a-fA-F]+):([0-9a-fA-F]+)\\.([0-9a-fA-F]+)" cfg.gpu.pciId;
  pciDomain = "0x${builtins.elemAt pciParts 0}";
  pciBus = "0x${builtins.elemAt pciParts 1}";
  pciSlot = "0x${builtins.elemAt pciParts 2}";
  pciFunction = "0x${builtins.elemAt pciParts 3}";
  # Audio function is typically .1 on the same device
  pciAudioFunction = "0x1";

  # IVSHMEM shared memory for Looking Glass (conditional)
  shmemConfig = if cfg.lookingGlass.enable then ''
    <!-- Looking Glass IVSHMEM -->
    <shmem name="looking-glass">
      <model type="ivshmem-plain"/>
      <size unit="M">${toString cfg.lookingGlass.sharedMemoryMB}</size>
    </shmem>'' else "";

  domainXML = pkgs.replaceVars ../resources/win11-domain.xml.in {
    memory = toString cfg.memory;
    vcpus = toString cfg.vcpus;
    ovmfCode = "${pkgs.OVMFFull.fd}/FV/OVMF_CODE.ms.fd";
    ovmfVars = "${pkgs.OVMFFull.fd}/FV/OVMF_VARS.ms.fd";
    qemuBin = "${pkgs.qemu}/bin/qemu-system-x86_64";
    isoPath = cfg.isoPath;
    inherit virtioIso pciDomain pciBus pciSlot pciFunction pciAudioFunction shmemConfig;
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.etc."libvirt/qemu/win11.xml".source = domainXML;

    systemd.services.windowsvm-disk = {
      description = "Create Windows VM disk image";
      wantedBy = [ "libvirtd.service" ];
      before = [ "libvirtd.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if [ ! -f /var/lib/libvirt/images/win11.qcow2 ]; then
          mkdir -p /var/lib/libvirt/images
          ${pkgs.qemu}/bin/qemu-img create -f qcow2 /var/lib/libvirt/images/win11.qcow2 ${toString cfg.diskSize}G
        fi
      '';
    };

    systemd.services.windowsvm-define = {
      description = "Define Windows VM in libvirt";
      requires = [ "libvirtd.service" ];
      after = [ "libvirtd.service" "windowsvm-disk.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        ${pkgs.libvirt}/bin/virsh define /etc/libvirt/qemu/win11.xml || true
      '';
    };
  };
}
