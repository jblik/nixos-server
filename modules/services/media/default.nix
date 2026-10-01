{ config, lib, ... }:
# Plex, the *arr stack and Tdarr, plus the shared /data layout they all use:
#
#   /data/torrents/{tv,movies}   qBittorrent downloads
#   /data/media/{tv,movies}      the library (Plex, Sonarr, Radarr, Bazarr)
#   /scratch/incomplete          qBittorrent in-progress downloads (fast storage)
#   /scratch/transcode           Tdarr cache (fast storage)
#
# Downloads and library share one mount so imports are hardlinks, not copies.
let
  inherit (config.host.storage) bulkMount scratchDir;
  s = config.services;
  lan = config.host.lanCidr;
  m = config.host.media;
  mediaServices = [
    "plex"
    "sonarr"
    "radarr"
    "bazarr"
    "qbittorrent"
    "tdarr-server"
    "tdarr-node-main"
  ];
  ports = [
    s.sonarr.settings.server.port
    s.radarr.settings.server.port
    s.bazarr.listenPort
    s.jackett.port
    s.qbittorrent.webuiPort
    s.seerr.port
    s.tdarr.server.webUIPort
    m.cleanuparr.port
    m.pulsarr.port
    m.maintainerr.port
  ];
in
{
  imports = [
    ./arr.nix
    ./containers.nix
    ./plex.nix
    ./tdarr.nix
  ];

  config = lib.mkIf m.enable {
    systemd.tmpfiles.rules =
      map (d: "d ${bulkMount}/${d} 2775 root users -") [
        "torrents"
        "torrents/tv"
        "torrents/movies"
        "media"
        "media/tv"
        "media/movies"
      ]
      ++ map (d: "d ${scratchDir}/${d} 2775 root users -") [
        "incomplete"
        "transcode"
      ];

    # Every service that touches /data runs in the `users` group (gid 100) with
    # umask 002, the same ownership unraid gave these files (99:100), so the
    # unraid disks can be adopted without a chown.
    systemd.services = lib.genAttrs mediaServices (_: {
      unitConfig.RequiresMountsFor = [
        bulkMount
        scratchDir
      ];
      serviceConfig.UMask = lib.mkForce "0002";
    });

    networking.firewall.extraInputRules = ''
      ip saddr ${lan} tcp dport { ${lib.concatMapStringsSep ", " toString ports} } accept
    '';
  };
}
