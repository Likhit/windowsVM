{ config, lib, ... }:

let
  cfg = config.windowsVM;
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.virtualisation.libvirtd.enable or false;
        message = ''
          windowsVM requires libvirtd to be enabled.
          Add to your NixOS configuration:
            virtualisation.libvirtd.enable = true;
        '';
      }
      {
        assertion = config.virtualisation.libvirtd.qemu.swtpm.enable or false;
        message = ''
          windowsVM requires swtpm for TPM 2.0 emulation.
          Add to your NixOS configuration:
            virtualisation.libvirtd.qemu.swtpm.enable = true;
        '';
      }
    ];
  };
}
