{ config, lib, pkgs, ... }:

let
  cfg = config.windowsVM;
in
{
  imports = [
    ./vfio.nix
    ./libvirt.nix
    ./looking-glass.nix
    ./vm-domain.nix
  ];

  options.windowsVM = {
    enable = lib.mkEnableOption "Windows 11 VM with GPU passthrough";

    isoPath = lib.mkOption {
      type = lib.types.str;
      description = "Runtime path to the Windows 11 ISO (not copied to the Nix store).";
    };

    gpu.pciId = lib.mkOption {
      type = lib.types.str;
      description = "PCI address of the GPU to pass through (e.g. 0000:00:02.0).";
    };

    gpu.audioFunction = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "PCI function of the GPU audio device (e.g. \"1\"). Set to null if the GPU has no audio device. Discrete GPUs typically have audio on function 1.";
    };

    vcpus = lib.mkOption {
      type = lib.types.int;
      default = 16;
      description = "Number of virtual CPUs for the VM.";
    };

    memory = lib.mkOption {
      type = lib.types.int;
      default = 32768;
      description = "Memory for the VM in MiB.";
    };

    diskSize = lib.mkOption {
      type = lib.types.int;
      default = 128;
      description = "Disk size in GiB (qcow2 thin-provisioned).";
    };

    lookingGlass = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable Looking Glass (IVSHMEM) for display.";
      };

      sharedMemoryMB = lib.mkOption {
        type = lib.types.int;
        default = 32;
        description = "Shared memory size in MiB for Looking Glass (32 for ≤1440p, 64 for 4K).";
      };
    };

    usb.devices = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          vendorId = lib.mkOption {
            type = lib.types.str;
            description = "USB vendor ID (e.g. 046d).";
          };
          productId = lib.mkOption {
            type = lib.types.str;
            description = "USB product ID (e.g. c539).";
          };
        };
      });
      default = [];
      description = "USB devices to pass through to the VM.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Sub-modules provide the actual configuration
  };
}
