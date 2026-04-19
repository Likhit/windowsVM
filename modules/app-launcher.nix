{ config, lib, pkgs, ... }:

let
  cfg = config.windowsVM;

  virsh = "sudo ${pkgs.libvirt}/bin/virsh";

  viewerCmd = if cfg.lookingGlass.enable
    then "${pkgs.looking-glass-client}/bin/looking-glass-client"
    else "${pkgs.virt-viewer}/bin/virt-viewer -c qemu:///system --wait win11";

  launcherScript = pkgs.writeShellScript "windowsvm-launch" ''
    set -euo pipefail

    DOMAIN_XML="/etc/libvirt/qemu/win11.xml"

    # Re-define the domain if the XML has changed (e.g. after a flake update)
    if ${virsh} dominfo win11 &>/dev/null; then
      live_xml=$(${virsh} dumpxml --inactive win11 2>/dev/null | grep -v '<uuid>' | grep -v '</uuid>')
      deployed_xml=$(grep -v '<uuid>' "$DOMAIN_XML" 2>/dev/null | grep -v '</uuid>' || true)
      if [ "$live_xml" != "$deployed_xml" ]; then
        echo "Domain XML changed, re-defining..."
        state=$(${virsh} domstate win11 2>/dev/null || true)
        if [ "$state" = "running" ]; then
          ${virsh} destroy win11
        fi
        ${virsh} undefine win11 --nvram 2>/dev/null || ${virsh} undefine win11
        ${virsh} define "$DOMAIN_XML"
      fi
    else
      ${virsh} define "$DOMAIN_XML"
    fi

    # Start the VM if it's not already running
    state=$(${virsh} domstate win11 2>/dev/null || true)
    if [ "$state" != "running" ]; then
      ${virsh} start win11
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
