{ config, lib, pkgs, ... }:

let
  cfg = config.windowsVM;
  lgCfg = cfg.lookingGlass;
in
{
  config = lib.mkIf (cfg.enable && lgCfg.enable) {
    boot.kernelModules = [ "kvmfr" ];
    boot.extraModulePackages = [ config.boot.kernelPackages.kvmfr ];
    boot.extraModprobeConfig = "options kvmfr static_size_mb=${toString lgCfg.sharedMemoryMB}";

    services.udev.extraRules = ''
      SUBSYSTEM=="kvmfr", OWNER="root", GROUP="kvm", MODE="0660"
    '';

    environment.systemPackages = [ pkgs.looking-glass-client ];
  };
}
