# Windows 11 VM with GPU Passthrough for NixOS

A NixOS flake module that provisions a Windows 11 VM with VFIO GPU passthrough, Looking Glass display, and unattended installation.

## Hardware Prerequisites

- **CPU** with IOMMU support (Intel VT-d or AMD-Vi)
- **Two GPUs**: one for the host, one dedicated to the VM (bound to `vfio-pci` at boot)
- **BIOS/UEFI settings**: enable VT-d (Intel) or IOMMU (AMD) in firmware settings

## Quick Start

### 1. Add the flake input

```nix
# flake.nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    windowsVM.url = "github:Likhit/windowsVM";
  };

  outputs = { nixpkgs, windowsVM, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        windowsVM.nixosModules.default
        ./configuration.nix
      ];
    };
  };
}
```

### 2. Configure host prerequisites

The module asserts that host infrastructure is configured correctly. Add these to your NixOS configuration:

```nix
# IOMMU and VFIO
boot.kernelParams = [
  "amd_iommu=on"   # or "intel_iommu=on" for Intel
  "iommu=pt"
];

boot.initrd.kernelModules = [
  "vfio_pci"
  "vfio"
  "vfio_iommu_type1"
];

# Bind the passthrough GPU to vfio-pci (use your GPU's PCI IDs)
boot.extraModprobeConfig = ''
  options vfio-pci ids=8086:4680,8086:4692
'';

# Libvirt
virtualisation.libvirtd = {
  enable = true;
  qemu.swtpm.enable = true;
};
```

### 3. Configure the VM

```nix
windowsVM = {
  enable = true;
  isoPath = "/var/lib/libvirt/images/Win11.iso";  # runtime path, not copied to Nix store
  gpu.pciId = "0000:00:02.0";                     # PCI address of passthrough GPU
  # gpu.audioFunction = "1";                      # set if GPU has audio device (discrete GPUs)

  # Optional (shown with defaults)
  vcpus = 16;
  memory = 32768;                  # MiB
  diskSize = 128;                  # GiB, qcow2 thin-provisioned
  lookingGlass.enable = true;
  lookingGlass.sharedMemoryMB = 32;  # 32 for <=1440p, 64 for 4K

  # USB passthrough (optional)
  usb.devices = [
    { vendorId = "046d"; productId = "c539"; }  # e.g. Logitech mouse
  ];
};
```

### 4. Download the Windows 11 ISO

Download the official Windows 11 ISO from Microsoft:

1. Go to https://www.microsoft.com/software-download/windows11
2. Under "Download Windows 11 Disk Image (ISO)", select **Windows 11 (multi-edition ISO)**
3. Choose your language and download the ISO
4. Place it at the path you configured in `isoPath`:

```bash
sudo mkdir -p /var/lib/libvirt/images
sudo mv ~/Downloads/Win11_*.iso /var/lib/libvirt/images/Win11.iso
```

The ISO is referenced at runtime by path — it is **not** copied into the Nix store.

### 5. Rebuild

```bash
sudo nixos-rebuild switch --flake .#myhost
```

### 6. Start the VM

```bash
virsh start win11

# Connect via SPICE to watch the install and interact with the VM
virt-viewer win11
```

On first boot, you will need to install Windows manually through the installer. The VirtIO drivers are automatically available on the second CD-ROM (drive `E:`). When the installer asks for a disk driver, browse to `E:\viostor\w11\amd64`.

### 7. Use Looking Glass

After Windows is installed and the Looking Glass host app is running in the guest:

```bash
looking-glass-client
```

## Option Reference

| Option | Type | Default | Description |
|---|---|---|---|
| `windowsVM.enable` | bool | `false` | Enable the Windows 11 VM |
| `windowsVM.isoPath` | string | *required* | Runtime path to Windows 11 ISO |
| `windowsVM.gpu.pciId` | string | *required* | PCI address of GPU to pass through |
| `windowsVM.gpu.audioFunction` | string or null | `null` | PCI function of GPU audio device (e.g. `"1"` for discrete GPUs) |
| `windowsVM.vcpus` | int | `16` | Number of virtual CPUs |
| `windowsVM.memory` | int | `32768` | Memory in MiB |
| `windowsVM.diskSize` | int | `128` | Disk size in GiB (thin-provisioned) |
| `windowsVM.lookingGlass.enable` | bool | `true` | Enable Looking Glass display |
| `windowsVM.lookingGlass.sharedMemoryMB` | int | `32` | IVSHMEM size (32 for <=1440p, 64 for 4K) |
| `windowsVM.usb.devices` | list | `[]` | USB devices to pass through (`{vendorId, productId}`) |

## VM Management

```bash
virsh start win11        # Start the VM
virsh shutdown win11     # Graceful shutdown
virsh destroy win11      # Force stop
virsh list --all         # List all VMs
```

## How It Works

The module generates a libvirt domain XML with:
- Q35 machine type with OVMF (UEFI) firmware
- CPU host-passthrough with Hyper-V enlightenments
- VirtIO disk (qcow2) and network (NAT)
- TPM 2.0 via swtpm
- GPU passthrough via VFIO `<hostdev>`
- IVSHMEM shared memory for Looking Glass
- USB device passthrough
- Two CD-ROMs: Windows ISO, VirtIO drivers

The module asserts host prerequisites (IOMMU, VFIO, libvirt) rather than silently configuring them. If something is missing, you get a clear error message with the exact NixOS config to add.
