{
  config,
  lib,
  pkgs,
  ...
}:
let
  namespace = "qbittorrent";
  interface = "nordvpn";
  namespacePath = "/run/netns/${namespace}";
  resolver = pkgs.writeText "qbittorrent-resolv.conf" ''
    nameserver 103.86.96.100
    nameserver 103.86.99.100
  '';
  nsswitch = pkgs.writeText "qbittorrent-nsswitch.conf" (
    lib.replaceStrings
      [ "hosts:     ${lib.concatStringsSep " " config.system.nssDatabases.hosts}" ]
      [ "hosts:     files dns" ]
      config.environment.etc."nsswitch.conf".text
  );
  profile = "${config.services.qbittorrent.profileDir}/qBittorrent/config/qBittorrent.conf";
in
{
  config = lib.mkIf config.host.media.enable {
    sops.secrets.nordvpn-wireguard-key = {
      restartUnits = [ "qbittorrent-vpn.service" ];
    };

    boot.kernelModules = [ "wireguard" ];

    systemd.services.qbittorrent-vpn = {
      description = "Isolated NordVPN network for qBittorrent";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      before = [ "qbittorrent.service" ];
      path = with pkgs; [
        curl
        iproute2
        jq
        wireguard-tools
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        server=$(curl --fail --silent --show-error --globoff --connect-timeout 10 --max-time 30 \
          'https://api.nordvpn.com/v1/servers/recommendations?filters[country_id]=209&filters[servers_technologies][identifier]=wireguard_udp&limit=1')
        endpoint=$(jq -er '.[0] | select(.locations[0].country.code == "CH") | .station' <<< "$server")
        publicKey=$(jq -er '.[0].technologies[] | select(.identifier == "wireguard_udp") | .metadata[] | select(.name == "public_key") | .value' <<< "$server")
        jq -r '"Using NordVPN server " + .[0].hostname' <<< "$server"
        ip netns add ${namespace}
        # WireGuard's encrypted UDP socket stays in the host namespace after moving the interface.
        ip link add ${interface} type wireguard
        wg set ${interface} private-key ${config.sops.secrets.nordvpn-wireguard-key.path} \
          peer "$publicKey" endpoint "$endpoint:51820" allowed-ips 0.0.0.0/0 persistent-keepalive 25
        ip link set ${interface} netns ${namespace}
        ip -n ${namespace} address add 10.5.0.2/32 dev ${interface}
        ip -n ${namespace} link set lo up
        ip -n ${namespace} link set ${interface} mtu 1420 up
        ip -n ${namespace} route add default dev ${interface}
      '';
      # ExecStopPost also cleans up when setup fails before the interface has moved.
      postStop = ''
        ip -n ${namespace} link delete ${interface} 2>/dev/null || true
        ip link delete ${interface} 2>/dev/null || true
        ip netns delete ${namespace} 2>/dev/null || true
      '';
    };

    systemd.services.qbittorrent = {
      requires = [ "qbittorrent-vpn.service" ];
      after = [ "qbittorrent-vpn.service" ];
      partOf = [ "qbittorrent-vpn.service" ];
      preStart = ''
        ${pkgs.crudini}/bin/crudini --set ${lib.escapeShellArg profile} Preferences 'WebUI\Address' 127.0.0.1
        # The socket proxy connects over loopback; localhost must still require authentication.
        ${pkgs.crudini}/bin/crudini --set ${lib.escapeShellArg profile} Preferences 'WebUI\LocalHostAuth' true
        ${pkgs.crudini}/bin/crudini --set ${lib.escapeShellArg profile} Preferences 'WebUI\AuthSubnetWhitelistEnabled' false
        ${pkgs.crudini}/bin/crudini --set ${lib.escapeShellArg profile} BitTorrent 'Session\Interface' ${interface}
        ${pkgs.crudini}/bin/crudini --set ${lib.escapeShellArg profile} BitTorrent 'Session\InterfaceName' ${interface}
        ${pkgs.crudini}/bin/crudini --set ${lib.escapeShellArg profile} BitTorrent 'Session\InterfaceAddress' ""
        ${pkgs.crudini}/bin/crudini --set ${lib.escapeShellArg profile} Network PortForwardingEnabled false
      '';
      serviceConfig = {
        NetworkNamespacePath = namespacePath;
        BindReadOnlyPaths = [
          "${resolver}:/etc/resolv.conf"
          # The host's NSS resolver modules can use Unix sockets outside the VPN namespace.
          "${nsswitch}:/etc/nsswitch.conf"
        ];
      };
    };

    systemd.sockets.qbittorrent-webui = {
      description = "qBittorrent WebUI on the host";
      wantedBy = [ "sockets.target" ];
      listenStreams = [ (toString config.services.qbittorrent.webuiPort) ];
    };

    systemd.services.qbittorrent-webui = {
      description = "Forward the host WebUI socket into the VPN namespace";
      requires = [ "qbittorrent.service" ];
      after = [ "qbittorrent.service" ];
      partOf = [ "qbittorrent-vpn.service" ];
      serviceConfig = {
        ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd 127.0.0.1:${toString config.services.qbittorrent.webuiPort}";
        NetworkNamespacePath = namespacePath;
        DynamicUser = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ProtectSystem = "strict";
        ProtectHome = true;
      };
    };
  };
}
