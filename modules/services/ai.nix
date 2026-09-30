{
  config,
  lib,
  pkgs,
  ...
}:
# Local AI server. Whichever backend is selected serves the same
# OpenAI-compatible API on the same port, so clients never have to care:
#
#   API  : http://<nixos>:11434        (/v1 for OpenAI-compatible clients)
#   WebUI: http://<nixos>:8080
#
# `host.ai.backend` picks between:
#
#   "llama-swap"  upstream llama.cpp (CUDA) behind llama-swap, which starts a
#                 llama-server per model on demand and stops it after its TTL.
#                 Explicit -ngl / context / KV-cache control, which is what this
#                 box needs: the GPU is shared with Immich ML and NVENC, so the
#                 LLM only gets whatever VRAM is left over.
#
#   "ollama"      the simpler option — model registry, no GGUF wrangling — at the
#                 cost of an opaque VRAM heuristic and a vendored llama.cpp fork.
let
  cfg = config.host.ai;
  inherit (cfg) apiPort openWebuiPort;

  # CUDA build of upstream llama.cpp. NOTE: this is not in the official binary
  # cache — add the CUDA community cache before the first rebuild or it compiles
  # locally, which takes hours on a 2700X.
  llama-cpp-cuda = pkgs.llama-cpp.override { cudaSupport = true; };
  llama-server = lib.getExe' llama-cpp-cuda "llama-server";

  modelPath = file: if lib.hasPrefix "/" file then file else "${cfg.modelsDir}/${file}";

  # Flags applied to every model. Flash attention and a q8_0 KV cache are the
  # cheapest VRAM wins available on Ampere, and are often the difference between
  # a useful context length fitting on the card and not.
  commonFlags = [
    "--flash-attn"
    "--cache-type-k q8_0"
    "--cache-type-v q8_0"
    "--no-webui" # Open WebUI is the frontend; llama-server's own UI is dead weight
  ];

  mkModel =
    _name: m:
    {
      cmd = lib.concatStringsSep " " (
        [
          llama-server
          "--port \${PORT}"
          "-m ${modelPath m.file}"
          "-ngl ${toString m.gpuLayers}"
          "-c ${toString m.contextSize}"
        ]
        ++ commonFlags
        ++ m.extraFlags
      );
      ttl = m.ttl;
    }
    // lib.optionalAttrs (m.aliases != [ ]) { inherit (m) aliases; };
in
{
  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      # --- Backend: llama.cpp behind llama-swap -------------------------------
      (lib.mkIf (cfg.backend == "llama-swap") {
        services.llama-swap = {
          enable = true;
          listenAddress = "0.0.0.0"; # reachable from the LAN; firewall scopes it
          port = apiPort;
          settings = {
            # A cold llama-server has to load weights from disk before it answers.
            healthCheckTimeout = 120;
            models = lib.mapAttrs mkModel cfg.models;
          };
        };

        # llama-swap runs as a DynamicUser, so the weights must be readable by it.
        systemd.tmpfiles.rules = [ "d ${cfg.modelsDir} 0755 root root -" ];

        environment.systemPackages = [ llama-cpp-cuda ];

        warnings = lib.optional (cfg.models == { }) ''
          host.ai.backend is "llama-swap" but host.ai.models is empty: the API will
          start and serve no models. Drop GGUF files in ${cfg.modelsDir} and declare
          them in host.ai.models.
        '';
      })

      # --- Backend: Ollama ----------------------------------------------------
      (lib.mkIf (cfg.backend == "ollama") {
        services.ollama = {
          enable = true;
          package = pkgs.ollama-cuda;
          host = "0.0.0.0";
          port = apiPort;
        };
      })

      # --- Frontend, shared by both backends ----------------------------------
      {
        networking.firewall.extraInputRules = ''
          ip saddr ${config.host.lanCidr} tcp dport { ${toString apiPort}, ${toString openWebuiPort} } accept
        '';

        services.open-webui = {
          enable = true;
          host = "0.0.0.0";
          port = openWebuiPort;
          environment = {
            # Both backends speak the OpenAI API on the same port, so this is the
            # one setting that would otherwise need to change with the backend.
            OPENAI_API_BASE_URL = "http://127.0.0.1:${toString apiPort}/v1";
            OPENAI_API_KEY = "sk-no-key-required";
            # Disable outbound telemetry / model auto-download checks.
            ANONYMIZED_TELEMETRY = "False";
            DO_NOT_TRACK = "True";
            SCARF_NO_ANALYTICS = "True";
          }
          // lib.optionalAttrs (cfg.backend == "ollama") {
            OLLAMA_BASE_URL = "http://127.0.0.1:${toString apiPort}";
          };
        };
      }
    ]
  );
}
