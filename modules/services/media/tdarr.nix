{ config, lib, ... }:
let
  inherit (config.host.storage) bulkMount scratchDir;
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
          workers.transcodeCPU = 0;
          workers.healthcheckCPU = 0;
          workers.transcodeGPU = 2;
          workers.healthcheckGPU = 1;
        };
      };
    };

    # The module never declares nodes/ itself, so tmpfiles creates it as root and then
    # refuses to manage anything under it (unsafe path transition from the tdarr-owned parent).
    systemd.tmpfiles.rules = [
      "d ${config.services.tdarr.dataDir}/nodes 0750 ${config.services.tdarr.user} users -"
    ];

    # The Tdarr module only lets it write to its own state; it has to replace
    # files in the library and use the cache under scratchDir.
    systemd.services = lib.mkMerge [
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
