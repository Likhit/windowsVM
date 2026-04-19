{ config, lib, ... }:

let
  cfg = config.windowsVM;
  kernelParams = config.boot.kernelParams or [];
  initrdModules = config.boot.initrd.kernelModules or [];
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          builtins.any (p: p == "intel_iommu=on" || p == "amd_iommu=on") kernelParams;
        message = ''
          windowsVM requires IOMMU to be enabled in kernel params.
          Add to your NixOS configuration:
            boot.kernelParams = [ "intel_iommu=on" ];  # or "amd_iommu=on" for AMD
        '';
      }
      {
        assertion = builtins.elem "iommu=pt" kernelParams;
        message = ''
          windowsVM requires IOMMU passthrough mode.
          Add to your NixOS configuration:
            boot.kernelParams = [ "iommu=pt" ];
        '';
      }
      {
        assertion =
          builtins.elem "vfio_pci" initrdModules
          && builtins.elem "vfio" initrdModules
          && builtins.elem "vfio_iommu_type1" initrdModules;
        message = ''
          windowsVM requires VFIO kernel modules loaded in initrd.
          Add to your NixOS configuration:
            boot.initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
        '';
      }
    ];
  };
}
