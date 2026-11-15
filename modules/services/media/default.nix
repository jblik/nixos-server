{ config, lib, ... }:
# Plex, the *arr stack and Tdarr, plus the shared /data layout they all use:
#
#   /data/torrents/{tv,movies,sports}   qBittorrent downloads
#   /data/media/{tv,movies,sports}      the library (Plex, Sonarr, Radarr, Sportarr, Bazarr)
#   /scratch/incomplete        qBittorrent in-progress downloads (fast storage)
#   /scratch/usenet            SABnzbd incomplete and completed downloads
#   /scratch/transcode         Tdarr cache (fast storage)
#
# Torrent downloads share the library mount so seeding does not need another copy.
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
    "tdarr-server"
    "tdarr-node-main"
    "podman-sportarr"
  ];
  ports = [
    s.sonarr.settings.server.port
    s.radarr.settings.server.port
    s.bazarr.listenPort
    s.prowlarr.settings.server.port
    s.tdarr.server.webUIPort
    m.cleanuparr.port
    m.pulsarr.port
    m.maintainerr.port
    m.sportarr.port
  ];
in
{
  imports = [
    ./arr.nix
    ./qbittorrent
    ./sabnzbd
    ./sportarr
    ./containers.nix
    ./cleanuparr
    ./media-preview-generator
    ./plex.nix
    ./threadfin
    ./tdarr
  ];

  config = lib.mkIf m.enable {
    systemd.tmpfiles.rules =
      map (d: "d ${bulkMount}/${d} 2775 root users -") [
        "torrents"
        "torrents/tv"
        "torrents/movies"
        "torrents/sports"
        "media"
        "media/tv"
        "media/movies"
        "media/sports"
      ]
      ++ map (d: "d ${scratchDir}/${d} 2775 root users -") [
        "incomplete"
        "usenet"
        "usenet/incomplete"
        "usenet/complete"
        "usenet/complete/tv"
        "usenet/complete/movies"
        "usenet/complete/sports"
        "transcode"
      ];

    # Every service that touches /data runs in the `users` group (gid 100) with umask 002
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
