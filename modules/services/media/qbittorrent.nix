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
  profile = "${config.services.qbittorrent.profileDir}/qBittorrent/config";
in
{
  config = lib.mkIf config.host.media.enable {
    services.qbittorrent = {
      enable = true;
      group = "users";
      webuiPort = 8080;
    };

    sops.secrets.nordvpn-wireguard-key = {
      restartUnits = [ "qbittorrent-vpn.service" ];
    };

    sops.secrets.qbittorrent-webui-password = {
      sopsFile = ../../../secrets/media-qbittorrent.yaml;
      restartUnits = [ "qbittorrent.service" ];
    };

    sops.templates.qbittorrent-config = {
      content =
        lib.replaceStrings [ "@webui-password@" ] [ config.sops.placeholder.qbittorrent-webui-password ]
          (builtins.readFile ./qbittorrent/qBittorrent.conf);
      owner = config.services.qbittorrent.user;
      mode = "0400";
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
      unitConfig.RequiresMountsFor = [
        config.services.qbittorrent.profileDir
        config.host.storage.bulkMount
        config.host.storage.scratchDir
      ];
      requires = [ "qbittorrent-vpn.service" ];
      after = [ "qbittorrent-vpn.service" ];
      partOf = [ "qbittorrent-vpn.service" ];
      restartTriggers = [
        ./qbittorrent/qBittorrent.conf
        ./qbittorrent/categories.json
        ./qbittorrent/watched_folders.json
        ./qbittorrent/feeds.json
      ];
      preStart = ''
        backupDir=""
        install_config() {
          target=${lib.escapeShellArg profile}/"$2"
          if [ -e "$target" ] && ! cmp -s "$1" "$target"; then
            if [ -z "$backupDir" ]; then
              backupDir=$(mktemp -d ${lib.escapeShellArg "${profile}/declarative-backup.XXXXXXXX"})
            fi
            install -Dm600 "$target" "$backupDir/$2"
          fi
          install -Dm600 "$1" "$target"
        }
        install_config ${config.sops.templates.qbittorrent-config.path} qBittorrent.conf
        install_config ${./qbittorrent/categories.json} categories.json
        install_config ${./qbittorrent/watched_folders.json} watched_folders.json
        install_config ${./qbittorrent/feeds.json} rss/feeds.json
      '';
      serviceConfig = {
        UMask = lib.mkForce "0002";
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

    networking.firewall.extraInputRules = ''
      ip saddr ${config.host.lanCidr} tcp dport ${toString config.services.qbittorrent.webuiPort} accept
    '';
  };
}
