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

Add libvirt to your NixOS configuration:

```nix
virtualisation.libvirtd = {
  enable = true;
  qemu.swtpm.enable = true;
};
```

**If using GPU passthrough** (`gpu.pciId` is set), you also need IOMMU and VFIO:

```nix
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
  options vfio-pci ids=10de:2484,10de:228b
'';
```

### 3. Configure the VM

```nix
windowsVM = {
  enable = true;
  isoPath = "/var/lib/libvirt/images/Win11.iso";  # runtime path, not copied to Nix store

  # GPU passthrough (optional — omit for SPICE-only VM)
  # gpu.pciId = "0000:01:00.0";                   # PCI address of passthrough GPU
  # gpu.audioFunction = "1";                       # set if GPU has audio device (discrete GPUs)

  # Optional (shown with defaults)
  vcpus = 16;
  memory = 32768;                  # MiB
  diskSize = 128;                  # GiB, qcow2 thin-provisioned
  # lookingGlass.enable = true;    # auto-enabled when gpu.pciId is set
  # lookingGlass.sharedMemoryMB = 32;  # 32 for <=1440p, 64 for 4K

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

### 6. Launch the VM

The module installs a desktop application (named by `windowsVM.appName`, default "Windows 11") in your app launcher. Click it to start the VM and connect to the display automatically.

The launcher handles:
- Starting the VM if it's not already running
- Re-defining the domain if the XML has changed (e.g. after a flake update)
- Connecting via `looking-glass-client` (with GPU passthrough) or `virt-viewer` (SPICE-only)

You can also launch from the terminal:

```bash
# The launcher script is available as a desktop app, or use virsh directly:
sudo virsh start win11
virt-viewer -c qemu:///system win11
```

### 7. Install Windows

On first boot, you will need to install Windows manually through the installer.

1. The VM boots from the Windows ISO. When you see **"Press any key to boot from CD"**, press a key immediately (the timing window is short).
2. Proceed through language/region selection.
3. At **"Where do you want to install Windows?"**, no disks will be shown — the VirtIO disk driver isn't built into Windows.
4. Click **"Load driver"** → **"Browse"** → navigate to the VirtIO CD-ROM (drive `E:`) → `E:\viostor\w11\amd64` → click OK.
5. Select the **"Red Hat VirtIO SCSI controller"** driver and click **Next**.
6. The disk should now appear as unallocated space. Select it and continue the installation.

### 8. Complete Windows setup

During OOBE (Out-of-Box Experience), Windows will get stuck at **"Let's connect you to a network"** because the VirtIO network driver isn't installed yet.

1. Press **Shift + F10** to open a command prompt.
2. Type `OOBE\BYPASSNRO` and press Enter — the VM will reboot.
3. After reboot, the OOBE will now show an **"I don't have internet"** option. Click it to continue with a local account.

After setup completes, install the VirtIO drivers for networking and other devices:

1. Open the VirtIO CD-ROM (drive `E:`) in File Explorer.
2. Run `virtio-win-guest-tools.exe` — this installs all VirtIO drivers (network, balloon, serial, etc.) at once.
3. Restart the VM. Networking should now work.

## Option Reference

| Option | Type | Default | Description |
|---|---|---|---|
| `windowsVM.enable` | bool | `false` | Enable the Windows 11 VM |
| `windowsVM.appName` | string | `"Windows 11"` | Name of the desktop app launcher |
| `windowsVM.isoPath` | string | *required* | Runtime path to Windows 11 ISO |
| `windowsVM.gpu.pciId` | string or null | `null` | PCI address of GPU to pass through (null for SPICE-only) |
| `windowsVM.gpu.audioFunction` | string or null | `null` | PCI function of GPU audio device (e.g. `"1"` for discrete GPUs) |
| `windowsVM.vcpus` | int | `16` | Number of virtual CPUs |
| `windowsVM.memory` | int | `32768` | Memory in MiB |
| `windowsVM.diskSize` | int | `128` | Disk size in GiB (thin-provisioned) |
| `windowsVM.lookingGlass.enable` | bool | auto | Enable Looking Glass (defaults to `true` when `gpu.pciId` is set) |
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
