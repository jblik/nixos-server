{ config, ... }:
# Service modules add their own LAN-only rules via
# `networking.firewall.extraInputRules`, scoped to `host.lanCidr`.
{
  networking = {
    hostName = config.host.hostname;
    networkmanager.enable = true;
    interfaces = {
      enp5s0 = {
        wakeOnLan.enable = true;
      };
    };

    networkmanager.appendNameservers = [
      "1.1.1.1"
      "9.9.9.9"
    ];

    nftables.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [ 9 ];
    };
  };
}
