{ config, ... }:
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-exit-node" ];
  };

  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
}
