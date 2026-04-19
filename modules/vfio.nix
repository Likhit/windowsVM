{ config, lib, ... }:

let
  cfg = config.windowsVM;
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          builtins.any (p: p == "intel_iommu=on" || p == "amd_iommu=on") config.boot.kernelParams;
        message = ''
          windowsVM requires IOMMU to be enabled in kernel params.
          Add to your NixOS configuration:
            boot.kernelParams = [ "intel_iommu=on" ];  # or "amd_iommu=on" for AMD
        '';
      }
      {
        assertion = builtins.elem "iommu=pt" config.boot.kernelParams;
        message = ''
          windowsVM requires IOMMU passthrough mode.
          Add to your NixOS configuration:
            boot.kernelParams = [ "iommu=pt" ];
        '';
      }
      {
        assertion =
          builtins.elem "vfio_pci" config.boot.initrd.kernelModules
          && builtins.elem "vfio" config.boot.initrd.kernelModules
          && builtins.elem "vfio_iommu_type1" config.boot.initrd.kernelModules;
        message = ''
          windowsVM requires VFIO kernel modules loaded in initrd.
          Add to your NixOS configuration:
            boot.initrd.kernelModules = [ "vfio_pci" "vfio" "vfio_iommu_type1" ];
        '';
      }
    ];
  };
}
