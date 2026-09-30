{ config, ... }:
# Hostname, wake-on-LAN on the onboard NIC (enp5s0; also needs ErP off and "Power
# On By PCI-E" on in the BIOS) + firewall. SSH is open on all interfaces; service
# modules add their own LAN-only rules via `networking.firewall.extraInputRules`,
# scoped to `host.lanCidr`.
{
  networking = {
    hostName = config.host.hostname;
    networkmanager.enable = true;
    interfaces = {
      enp5s0 = {
        wakeOnLan.enable = true;
      };
    };

    nftables.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      allowedUDPPorts = [ 9 ];
    };
  };
}
