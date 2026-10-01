{ config, lib, ... }:
let
  inherit (config.host.storage) bulkMount scratchDir;
in
{
  config = lib.mkIf config.host.media.enable {

    # Drop once https://github.com/NixOS/nixpkgs/issues/557024 is fixed.
    nixpkgs.overlays = [
      (final: prev: {
        ccextractor = prev.ccextractor.overrideAttrs (old: {
          env = old.env // {
            NIX_CFLAGS_COMPILE = "-DGPAC_ALLOW_UNSAFE_STRFUNC";
          };
        });
      })
    ];

    services.tdarr = {
      enable = true;
      group = "users";
      server = {
        enable = true;
        webUIPort = 8265;
        serverPort = 8266;
      };
      nodes.main.workers.transcodeGPU = 1;
    };

    # The Tdarr module only lets it write to its own state; it has to replace
    # files in the library and use the cache under scratchDir.
    systemd.services =
      lib.genAttrs
        [
          "tdarr-server"
          "tdarr-node-main"
        ]
        (_: {
          serviceConfig.ReadWritePaths = [
            bulkMount
            scratchDir
          ];
        });
  };
}
