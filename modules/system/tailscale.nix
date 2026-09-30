{ ... }:
# Tailnet access, and this machine offered as an exit node (approve it in the
# Tailscale admin console after the first `tailscale up`).
{
  services.tailscale = {
    enable = true;
    openFirewall = true;
    useRoutingFeatures = "server";
    extraSetFlags = [ "--advertise-exit-node" ];
  };
}
