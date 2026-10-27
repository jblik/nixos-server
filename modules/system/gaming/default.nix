{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.host.gaming.enable {
    programs.steam.enable = true;
    hardware.graphics.enable32Bit = true;

    services.xserver = {
      enable = true;
      displayManager.startx = {
        enable = true;
        generateScript = true;
      };
      windowManager.openbox.enable = true;
    };

    security.rtkit.enable = true;
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
    };

    environment.systemPackages = with pkgs; [
      evtest
      pavucontrol
      usbutils
      vulkan-tools
      xterm
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/flight-simulator 0750 jblik users -"
      "d /var/lib/flight-simulator/library 0750 jblik users -"
    ];
  };
}
