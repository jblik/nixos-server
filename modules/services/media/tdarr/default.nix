{
  config,
  lib,
  pkgs,
  ...
}:
let
  maintenanceService = import ../../maintenance/service.nix { inherit config lib pkgs; };
  inherit (config.host.storage) bulkMount scratchDir;
  languagePlugin = pkgs.writeText "Tdarr_Plugin_nxsv_Keep_Original_Eng_Und.js" (
    lib.replaceStrings
      [ "@sonarrPort@" "@radarrPort@" ]
      [
        (toString config.services.sonarr.settings.server.port)
        (toString config.services.radarr.settings.server.port)
      ]
      (builtins.readFile ./plugins/Tdarr_Plugin_nxsv_Keep_Original_Eng_Und.js)
  );
in
{
  config = lib.mkIf config.host.media.enable {

    services.tdarr = {
      enable = true;
      group = "users";
      server = {
        enable = true;
        webUIPort = config.host.media.tdarr.port;
        serverPort = config.host.media.tdarr.serverPort;
      };
      nodes = {
        main = {
          startPaused = true;
          workers.transcodeCPU = 0;
          workers.healthcheckCPU = 0;
          workers.transcodeGPU = 1;
          workers.healthcheckGPU = 1;
        };
      };
    };

    # The module never declares nodes/ itself, so tmpfiles creates it as root and then
    # refuses to manage anything under it (unsafe path transition from the tdarr-owned parent).
    systemd.tmpfiles.rules = [
      "d ${config.services.tdarr.dataDir}/nodes 0750 ${config.services.tdarr.user} users -"
      "d ${config.services.tdarr.dataDir}/server/server/Tdarr/Plugins/Local 0750 ${config.services.tdarr.user} users -"
      # Copied rather than symlinked so the server never serves a dangling store path after GC.
      "C+ ${config.services.tdarr.dataDir}/server/server/Tdarr/Plugins/Local/Tdarr_Plugin_nxsv_Keep_Original_Eng_Und.js - - - - ${languagePlugin}"
    ];

    # The Tdarr module only lets it write to its own state; it has to replace
    # files in the library and use the cache under scratchDir.
    systemd.services = lib.mkMerge [
      {
        tdarr-maintenance = maintenanceService {
          task = "tdarr";
          description = "Apply the Tdarr node maintenance window";
          unit = "tdarr-node-main.service";
          script = ./maintenance.py;
          environment = {
            TDARR_URL = "http://127.0.0.1:${toString config.services.tdarr.server.serverPort}";
            TDARR_NODE = config.services.tdarr.nodes.main.name;
          };
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
