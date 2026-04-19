{ config, lib, pkgs, ... }:

let
  cfg = config.windowsVM;

  viewerCmd = if cfg.lookingGlass.enable
    then "${pkgs.looking-glass-client}/bin/looking-glass-client"
    else "${pkgs.virt-viewer}/bin/virt-viewer -c qemu:///system --wait win11";

  launcherScript = pkgs.writeShellScript "windowsvm-launch" ''
    # Start the VM if it's not already running
    state=$(sudo ${pkgs.libvirt}/bin/virsh domstate win11 2>/dev/null)
    if [ "$state" != "running" ]; then
      sudo ${pkgs.libvirt}/bin/virsh start win11
    fi

    # Connect to the display
    exec ${viewerCmd}
  '';

  desktopItem = pkgs.makeDesktopItem {
    name = "windowsvm";
    desktopName = cfg.appName;
    exec = "${launcherScript}";
    icon = "computer";
    comment = "Launch the Windows 11 VM";
    categories = [ "System" "Emulator" ];
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      desktopItem
      pkgs.virt-viewer
    ];
  };
}
