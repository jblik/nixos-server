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
  home-assistant = applicationPkgs.home-assistant.home-assistant.override {
    packageOverrides = _: prev: {
      caldav = prev.caldav.overridePythonAttrs (_: {
        # The upstream suite took over eight minutes on the server.
        doCheck = false;
      });
      niquests = prev.niquests.overridePythonAttrs (old: {
        # The proxy test resolves an external hostname inside the network sandbox.
        disabledTests = (old.disabledTests or [ ]) ++ [ "test_use_proxy_from_environment" ];
      });
      urllib3-future = prev.urllib3-future.overridePythonAttrs (_: {
        doCheck = false;
      });
    };
  };
  home-assistant-custom-components =
    applicationPkgs.home-assistant.home-assistant-custom-components.extend
      (
        _: _: {
          meteoswiss = applicationPkgs.home-assistant.callPackage ./packages/meteoswiss.nix { };
        }
      );
  home-assistant-custom-lovelace-modules =
    applicationPkgs.home-assistant.home-assistant-custom-lovelace-modules.extend
      (
        _: _: {
          mass-player-card = final.callPackage ./packages/mass-player-card.nix { };
        }
      );
  python-matter-server = applicationPkgs.matter-server.python-matter-server;
  music-assistant = applicationPkgs.music-assistant.music-assistant;
  airplay-cli = applicationPkgs.music-assistant.airplay-cli;
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
  # Until https://github.com/run-llama/llama_index/pull/22468 lands, per-call think=False is dropped.
  paperless-ngx = applicationPkgs.paperless.paperless-ngx.overrideAttrs (old: {
    disabledTests = (old.disabledTests or [ ]) ++ [
      # Took 225 seconds on the server; embeddings use Ollama, not Hugging Face.
      "test_get_embedding_model_huggingface"
    ];
    postPatch = (old.postPatch or "") + ''
      cp ${./modules/services/paperless/custom_fields.py} src/documents/workflows/custom_fields.py
      substituteInPlace src/documents/tasks.py \
        --replace-fail 'from documents import sanity_checker' 'from documents import sanity_checker
      from documents.workflows.custom_fields import populate_document_fields' \
        --replace-fail '    if not apply_ai_suggestions_to_document(action, document):' '    updated_fields = apply_ai_suggestions_to_document(action, document)
          transaction.on_commit(lambda: populate_document_fields.delay(document_id))
          if not updated_fields:'
      substituteInPlace src/paperless_ai/client.py \
        --replace-fail 'return Ollama(' 'return Ollama(thinking=False,'
      substituteInPlace src/paperless_ai/tests/test_client.py \
        --replace-fail 'mock_ollama_llm.assert_called_once_with(' 'mock_ollama_llm.assert_called_once_with(thinking=False,'
    '';
  });
}
