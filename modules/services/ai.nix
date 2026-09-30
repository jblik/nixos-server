{ config, pkgs, ... }:
# Local AI server: Ollama (CUDA) exposing an OpenAI-compatible API to the whole
# LAN, with Open WebUI as a browser frontend.
#
#   API  : http://<nixos>:11434        (and /v1 for OpenAI-compatible clients)
#   WebUI: http://<nixos>:8080
#
# `ollama.service` is one of the units released when the GPU is handed to a VM
# (see host.gpu.hostServices).
let
  inherit (config.host.ai) ollamaPort openWebuiPort;
in
{
  services.ollama = {
    enable = true;
    # CUDA-accelerated build (replaces the removed `acceleration` option).
    package = pkgs.ollama-cuda;
    # Listen on all interfaces so other LAN services can use it.
    host = "0.0.0.0";
    port = ollamaPort;
  };

  services.open-webui = {
    enable = true;
    host = "0.0.0.0";
    port = openWebuiPort;
    environment = {
      OLLAMA_BASE_URL = "http://127.0.0.1:${toString ollamaPort}";
      # Disable outbound telemetry / model auto-download checks.
      ANONYMIZED_TELEMETRY = "False";
      DO_NOT_TRACK = "True";
      SCARF_NO_ANALYTICS = "True";
    };
  };
}
