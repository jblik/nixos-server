{ config, ... }:
# Tailnet access, and this machine offered as an exit node (approve it in the
# Tailscale admin console after the first `tailscale up`). `tailscale0` is trusted, so
# every service UI (not just the LAN-only ports) is reachable from the tailnet.
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-exit-node" ];
  };

  networking.firewall.trustedInterfaces = [ config.services.tailscale.interfaceName ];
}
