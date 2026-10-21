{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (config.host.storage) bulkMount scratchDir;
  settings = builtins.fromJSON (builtins.readFile ./tdarr-settings.json);
in
{
  config = lib.mkIf config.host.media.enable {

    services.tdarr = {
      enable = true;
      group = "users";
      server = {
        enable = true;
        webUIPort = 8265;
        serverPort = 8266;
      };
      nodes = {
        main = {
          pathTranslators = settings.configs."nodes/main/configs/Tdarr_Node_Config.json".pathTranslators;
          workers.transcodeCPU = 0;
          workers.healthcheckCPU = 0;
          workers.transcodeGPU = 2;
          workers.healthcheckGPU = 1;
        };
      };
    };

    sops.secrets.media-tdarr-settings = {
      sopsFile = ../../../secrets/media-tdarr.yaml;
      key = "settings";
      owner = config.services.tdarr.user;
    };

    # The module never declares nodes/ itself, so tmpfiles creates it as root and then
    # refuses to manage anything under it (unsafe path transition from the tdarr-owned parent).
    systemd.tmpfiles.rules = [
      "d ${config.services.tdarr.dataDir}/nodes 0750 ${config.services.tdarr.user} users -"
      "d ${config.services.tdarr.dataDir}/server/server/Tdarr/Plugins/Local 0750 ${config.services.tdarr.user} users -"
      # Copied rather than symlinked so the server never serves a dangling store path after GC.
      "C+ ${config.services.tdarr.dataDir}/server/server/Tdarr/Plugins/Local/Tdarr_Plugin_nxsv_Keep_Original_Eng_Und.js - - - - ${./tdarr-plugins/Tdarr_Plugin_nxsv_Keep_Original_Eng_Und.js}"
    ];

    # The Tdarr module only lets it write to its own state; it has to replace
    # files in the library and use the cache under scratchDir.
    systemd.services = lib.mkMerge [
      {
        tdarr-server = {
          restartTriggers = [
            ./tdarr-settings.json
            ../../../secrets/media-tdarr.yaml
            ./settings/tdarr-settings.py
          ];
          preStart = lib.mkBefore ''
            ${pkgs.python3}/bin/python3 ${./settings/tdarr-settings.py} \
              ${./tdarr-settings.json} ${config.sops.secrets.media-tdarr-settings.path} \
              ${config.services.tdarr.dataDir} ${config.services.tdarr.server.package.version}
          '';
        };
      }
      (lib.genAttrs
        [
          "tdarr-server"
          "tdarr-node-main"
        ]
        (_: {
          serviceConfig.ReadWritePaths = [
            bulkMount
            scratchDir
          ];
        })
      )
      # The node installs plugin deps (e.g. axios) with pnpm, which keeps its store in
      # $HOME; the user's home (dataDir) is read-only under ProtectSystem=strict.
      { tdarr-node-main.environment.HOME = "${config.services.tdarr.dataDir}/nodes/main"; }
    ];
  };
}
