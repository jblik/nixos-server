{ config, lib, ... }:
let
  s = config.services;
  domain = "steenblik.ch";
  internal = "internal.${domain}";
  private = {
    plex = 32400;
    sonarr = s.sonarr.settings.server.port;
    radarr = s.radarr.settings.server.port;
    bazarr = s.bazarr.listenPort;
    jackett = s.jackett.port;
    qbittorrent = s.qbittorrent.webuiPort;
    tdarr = s.tdarr.server.webUIPort;
    cleanuparr = config.host.media.cleanuparrPort;
    pulsarr = config.host.media.pulsarrPort;
    maintainerr = config.host.media.maintainerrPort;
  };
  public = {
    seerr = s.seerr.port;
  };
  proxyTo = port: {
    proxyPass = "http://127.0.0.1:${toString port}";
    proxyWebsockets = true;
  };
in
{
  config = lib.mkIf config.host.media.enable {
    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "jacob@steenblik.ch";
        dnsProvider = "cloudflare";
        environmentFile = "/var/lib/secrets/cloudflare.env";
      };
      certs.${internal} = {
        domain = "*.${internal}";
        group = s.nginx.group;
      };
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedOptimisation = true;
      recommendedGzipSettings = true;

      virtualHosts = {
        "_" = {
          default = true;
          rejectSSL = true;
          locations."/".return = "444";
        };
      }
      // lib.mapAttrs' (
        name: port:
        lib.nameValuePair "${name}.${internal}" {
          forceSSL = true;
          useACMEHost = internal;
          locations."/" = proxyTo port;
          extraConfig = ''
            allow ${config.host.lanCidr};
            allow 100.64.0.0/10;
            allow fd7a:115c:a1e0::/48;
            deny all;
          '';
        }
      ) private
      // lib.mapAttrs' (
        name: port:
        lib.nameValuePair "${name}.${domain}" {
          forceSSL = true;
          enableACME = true;
          locations."/" = proxyTo port;
        }
      ) public;
    };

    networking.firewall.allowedTCPPorts = [ 443 ];

    services.cloudflare-dyndns = {
      enable = true;
      apiTokenFile = "/var/lib/secrets/cloudflare-dyndns.token";
      domains = map (n: "${n}.${domain}") (lib.attrNames public);
    };
  };
}
