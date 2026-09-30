{ config, lib, ... }:
# Plex and Tdarr, plus the shared /data layout the whole media stack uses:
#
#   /data/torrents/{tv,movies}   qBittorrent downloads
#   /data/media/{tv,movies}      the library (Plex, Sonarr, Radarr, Bazarr)
#   /data/transcode              Tdarr cache (excluded from SnapRAID)
#
# Downloads and library share one mount so imports are hardlinks, not copies.
let
  inherit (config.host.storage) bulkMount;
  lan = config.host.lanCidr;
  mediaServices = [
    "plex"
    "sonarr"
    "radarr"
    "bazarr"
    "qbittorrent"
    "tdarr-server"
    "tdarr-node-main"
  ];
in
{
  config = lib.mkIf config.host.media.enable {
    systemd.tmpfiles.rules = map (d: "d ${bulkMount}/${d} 2775 root users -") [
      "torrents"
      "torrents/tv"
      "torrents/movies"
      "media"
      "media/tv"
      "media/movies"
      "transcode"
    ];

    # Every service that touches /data runs in the `users` group (gid 100) with
    # umask 002, the same ownership unraid gave these files (99:100), so the
    # unraid disks can be adopted without a chown.
    systemd.services = lib.mkMerge [
      (lib.genAttrs mediaServices (_: {
        unitConfig.RequiresMountsFor = [ bulkMount ];
        serviceConfig.UMask = lib.mkForce "0002";
      }))
      # The Tdarr module only lets it write to its own state; it has to replace
      # files in the library and use the cache under /data.
      {
        tdarr-server.serviceConfig.ReadWritePaths = [ bulkMount ];
        tdarr-node-main.serviceConfig.ReadWritePaths = [ bulkMount ];
      }
    ];

    services.plex = {
      enable = true;
      group = "users";
      # Remote access needs 32400 reachable from outside the LAN.
      openFirewall = true;
    };

    services.tdarr = {
      enable = true;
      group = "users";
      server.enable = true;
      nodes.main.workers.transcodeGPU = 1;
    };

    networking.firewall.extraInputRules = ''
      ip saddr ${lan} tcp dport ${toString config.services.tdarr.server.webUIPort} accept
    '';
  };
}
