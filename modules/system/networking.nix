{ config, ... }:
# Hostname + firewall. SSH is open on all interfaces; service modules add their
# own LAN-only rules via `networking.firewall.extraInputRules`, scoped to
# `host.lanCidr`.
{
  networking = {
    hostName = config.host.hostname;
    networkmanager.enable = true;

    nftables.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
    };
  };
}
