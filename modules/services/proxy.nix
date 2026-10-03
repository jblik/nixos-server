{ config, lib, ... }:
let
  s = config.services;
  publicDomain = "steenblik.ch";
  internalDomain = "internal.${publicDomain}";

  publicServices =
    lib.optionalAttrs config.host.forgejo.enable {
      git = s.forgejo.settings.server.HTTP_PORT;
    }
    // lib.optionalAttrs config.host.immich.enable {
      photos = s.immich.port;
    }
    // lib.optionalAttrs config.host.microbin.enable {
      notes = s.microbin.settings.MICROBIN_PORT;
    }
    // lib.optionalAttrs config.host.dashboard.enable {
      server = s.server-dashboard.publicPort;
    }
    // lib.optionalAttrs config.host.paperless.enable {
      documents = s.paperless.port;
    }
    // lib.optionalAttrs config.host.ai.enable {
      ai = config.host.ai.openWebuiPort;
    };

  privateServices =
    lib.optionalAttrs config.host.media.enable {
      plex = config.host.media.plex.port;
      sonarr = s.sonarr.settings.server.port;
      radarr = s.radarr.settings.server.port;
      bazarr = s.bazarr.listenPort;
      jackett = s.jackett.port;
      qbittorrent = s.qbittorrent.webuiPort;
      tdarr = s.tdarr.server.webUIPort;
      cleanuparr = config.host.media.cleanuparr.port;
      pulsarr = config.host.media.pulsarr.port;
      maintainerr = config.host.media.maintainerr.port;
    }
    // lib.optionalAttrs config.host.dashboard.enable {
      server = s.server-dashboard.internalPort;
      grafana = s.grafana.settings.server.http_port;
    }
    // {
      fans = config.host.fans.port;
    };
  proxyTo = port: {
    proxyPass = "http://127.0.0.1:${toString port}";
    proxyWebsockets = true;
  };
in
{
  config = {
    sops.secrets.cloudflare-dns-token = { };
    sops.templates."cloudflare.env".content =
      "CF_DNS_API_TOKEN=${config.sops.placeholder.cloudflare-dns-token}";

    security.acme = {
      acceptTerms = true;
      defaults = {
        email = "jacob@steenblik.ch";
        dnsProvider = "cloudflare";
        environmentFile = config.sops.templates."cloudflare.env".path;

        # todo: check this
        # The network drops DNS to Cloudflare's authoritative nameservers, so check
        # propagation through Cloudflare's public resolver instead.
        extraLegoFlags = [
          "--dns.propagation-disable-ans"
          "--dns.resolvers=1.1.1.1:53"
        ];
      };
      certs.${internalDomain} = {
        domain = "*.${internalDomain}";
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
        serviceName: port:
        lib.nameValuePair "${serviceName}.${internalDomain}" {
          forceSSL = true;
          useACMEHost = internalDomain;
          locations."/" = proxyTo port;
          extraConfig = ''
            allow ${config.host.lanCidr};
            allow 100.64.0.0/10;
            allow fd7a:115c:a1e0::/48;
            deny all;
          '';
        }
      ) privateServices
      // lib.mapAttrs' (
        serviceName: port:
        lib.nameValuePair "${serviceName}.${publicDomain}" {
          forceSSL = true;
          enableACME = true;
          acmeRoot = null; # Otherwise nginx sets a webroot and lego tries HTTP-01, which needs port 80 forwarded.
          locations."/" = proxyTo port;
        }
      ) publicServices;
    };

    networking.firewall.allowedTCPPorts = [ 443 ];

    services.cloudflare-dyndns = {
      enable = true;
      apiTokenFile = config.sops.secrets.cloudflare-dns-token.path;
      domains = map (serviceName: "${serviceName}.${publicDomain}") (lib.attrNames publicServices);
    };
  };
}
