{ config, lib, ... }:
# Hostname + firewall. AI/ML endpoints are reachable from the LAN only;
# SSH is open on all interfaces (lock down further via router/VPN if desired).
let
  inherit (config.host) lanCidr;
  lanPorts = [
    config.host.ai.apiPort
    config.host.ai.openWebuiPort
    config.host.immich.machineLearningPort
  ];
  portSet = lib.concatMapStringsSep ", " toString lanPorts;
in
{
  networking = {
    hostName = config.host.hostname;
    networkmanager.enable = true;

    nftables.enable = true;
    firewall = {
      enable = true;
      allowedTCPPorts = [ 22 ];
      # Restrict the compute endpoints to the LAN subnet.
      extraInputRules = ''
        ip saddr ${lanCidr} tcp dport { ${portSet} } accept
      '';
    };
  };
}
