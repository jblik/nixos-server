# Native applications from their own nixpkgs inputs. `nix eval .#versions`
# compares their versions with the system's nixpkgs; README.md covers updates.
{ applicationPkgs }:
final: prev:
let
  tdarr =
    component: hash:
    applicationPkgs.tdarr."tdarr-${component}".overrideAttrs (
      finalAttrs: _: {
        version = "2.91.01";
        src = prev.fetchzip {
          url = "https://storage.tdarr.io/versions/${finalAttrs.version}/linux_x64/Tdarr_${
            if component == "server" then "Server" else "Node"
          }.zip";
          inherit hash;
          stripRoot = false;
        };
      }
    );
in
{
  plex = applicationPkgs.plex.plex;
  bazarr = applicationPkgs.bazarr.bazarr;
  sonarr = applicationPkgs.sonarr.sonarr;
  radarr = applicationPkgs.radarr.radarr;
  jackett = applicationPkgs.jackett.jackett;
  flaresolverr = applicationPkgs.flaresolverr.flaresolverr;
  qbittorrent-nox = applicationPkgs.qbittorrent.qbittorrent-nox;
  forgejo-lts = applicationPkgs.forgejo.forgejo-lts;
  forgejo-runner = applicationPkgs.forgejo-runner.forgejo-runner;
  microbin = applicationPkgs.microbin.microbin;
  coolercontrol = applicationPkgs.coolercontrol.coolercontrol;
  prometheus-node-exporter = applicationPkgs.node-exporter.prometheus-node-exporter;
  prometheus = applicationPkgs.prometheus.prometheus;
  prometheus-alertmanager = applicationPkgs.alertmanager.prometheus-alertmanager;
  grafana = applicationPkgs.grafana.grafana;
  tailscale = applicationPkgs.tailscale.tailscale;
  ollama-cuda = applicationPkgs.ollama.ollama-cuda;
  open-webui = applicationPkgs.open-webui.open-webui;
  tika = applicationPkgs.paperless.tika;
  gotenberg = applicationPkgs.paperless.gotenberg;
  postgresql_17 = applicationPkgs.postgresql.postgresql_17;
  redis = applicationPkgs.redis.redis;
  nginxStable = applicationPkgs.nginx.nginxStable;
  cloudflare-dyndns = applicationPkgs.cloudflare-dyndns.cloudflare-dyndns;
  ookla-speedtest = applicationPkgs.speedtest.ookla-speedtest;
  home-assistant = applicationPkgs.home-assistant.home-assistant;
  python-matter-server = applicationPkgs.matter-server.python-matter-server;
  music-assistant = applicationPkgs.music-assistant.music-assistant;
  go-librespot = applicationPkgs.music-assistant.go-librespot;
  sendspin-bt-bridge = applicationPkgs.sendspin.callPackage ./packages/sendspin-bt-bridge.nix { };

  tdarr-server = tdarr "server" "sha256-QWXV8a9UJZXD/Obo8xDICAtN2ZndInD5/M/W8e/Xd5M=";
  tdarr-node = tdarr "node" "sha256-IbYyaxeYGVoWN/zadvhrblFRddtRc6ALyBABNzq0Wdc=";
  tdarrPackages = {
    server = final.tdarr-server;
    node = final.tdarr-node;
  };

  # 26.05 only has the end-of-life 2.x, marked insecure; 3.x needs the same vectorchord.
  immich = applicationPkgs.immich.immich;

  # we run 3.x and the importer needs the same version; 26.05 only has 2.x.
  paperless-ngx = applicationPkgs.paperless.paperless-ngx;
}
