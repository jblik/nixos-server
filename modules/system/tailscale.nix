{ config, ... }:
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraSetFlags = [
      "--advertise-exit-node"
      # The tailnet's DNS is the Pi-hole; the server must still resolve when it is down.
      "--accept-dns=false"
    ];
  };

  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
}
