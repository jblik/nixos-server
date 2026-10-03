{
  config,
  lib,
  pkgs,
  ...
}:
# One Ollama serves every model to everything: Open WebUI at https://ai.steenblik.ch, the
# API for CLIs and IDEs at https://ai.steenblik.ch/v1 (OpenAI and Anthropic shaped, behind
# the `ai-api-key` secret), and Paperless on localhost (modules/services/paperless).
let
  cfg = config.host.ai;
  domain = "ai.steenblik.ch";
  ollama = "http://127.0.0.1:${toString cfg.apiPort}";
in
{
  config = lib.mkIf cfg.enable {
    services.ollama = {
      enable = true;
      package = pkgs.ollama-cuda;
      host = "127.0.0.1";
      port = cfg.apiPort;
      loadModels = lib.attrValues cfg.models;
      syncModels = true;
      environmentVariables = {
        # Its default of 4k is too short for coding agents; flash attention and a q8_0 KV
        # cache keep that context affordable on a card shared with Immich ML and NVENC.
        OLLAMA_CONTEXT_LENGTH = "32768";
        OLLAMA_FLASH_ATTENTION = "1";
        OLLAMA_KV_CACHE_TYPE = "q8_0";
      };
    };

    services.open-webui = {
      enable = true;
      host = "127.0.0.1";
      port = cfg.openWebuiPort;
      environment = {
        WEBUI_URL = "https://${domain}";
        # Settings otherwise stick at their first-start values, and the models come from Nix.
        ENABLE_PERSISTENT_CONFIG = "False";
        # The first account becomes the admin; everyone else is invited from the admin panel.
        ENABLE_SIGNUP = "False";
        OLLAMA_BASE_URL = ollama;
        ENABLE_OPENAI_API = "False";
        DEFAULT_MODELS = cfg.models.chat;
        TASK_MODEL = cfg.models.chat;
        RAG_EMBEDDING_ENGINE = "ollama";
        RAG_EMBEDDING_MODEL = cfg.models.embedding;
        ANONYMIZED_TELEMETRY = "False";
        DO_NOT_TRACK = "True";
        SCARF_NO_ANALYTICS = "True";
      };
    };

    systemd.services.open-webui.unitConfig.RequiresMountsFor = [ "/var/lib/private/open-webui" ];

    sops.secrets.ai-api-key = { };
    # Clients send the key as `Authorization: Bearer` (OpenAI, Claude Code's
    # ANTHROPIC_AUTH_TOKEN) or `x-api-key` (Anthropic's ANTHROPIC_API_KEY).
    sops.templates."ai-api-key.conf" = {
      owner = config.services.nginx.user;
      restartUnits = [ "nginx.service" ];
      content = ''
        map $http_authorization $ai_bearer_ok {
          default 0;
          "Bearer ${config.sops.placeholder.ai-api-key}" 1;
        }
        map $http_x_api_key $ai_api_key_ok {
          default $ai_bearer_ok;
          "${config.sops.placeholder.ai-api-key}" 1;
        }
      '';
    };
    # The map keys hold the full API key, which overflows the default 64-byte bucket.
    services.nginx.mapHashBucketSize = 128;
    services.nginx.appendHttpConfig = ''
      include ${config.sops.templates."ai-api-key.conf".path};
    '';

    services.nginx.virtualHosts.${domain} = {
      locations."/v1/" = {
        proxyPass = ollama;
        extraConfig = ''
          if ($ai_api_key_ok = 0) {
            return 401;
          }
        '';
      };
      extraConfig = ''
        client_max_body_size 100M;
        proxy_buffering off;
        proxy_read_timeout 600s;
      '';
    };
  };
}
