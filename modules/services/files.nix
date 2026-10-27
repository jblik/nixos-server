{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.host.files;
  domain = "files.steenblik.ch";
  share = "/srv/files";
  dataset = "${config.host.storage.fastPool}/files";
  authFile = config.sops.secrets."files.htpasswd".path;
  closure = pkgs.closureInfo { rootPaths = [ pkgs.rclone ]; };
  # A read-only host root would still let the process read unrelated datasets.
  root = pkgs.runCommand "files-root" { } ''
    mkdir -p "$out"/{nix/store,srv/files,run/user,dev,proc,sys,tmp,var/tmp,home,root,etc}
    touch "$out/run/files.htpasswd"
    while IFS= read -r storePath; do
      cp -a "$storePath" "$out/nix/store/"
    done < ${closure}/store-paths
  '';
  initialize = pkgs.writeShellScript "files-initialize" ''
    set -eu
    ${pkgs.util-linux}/bin/mountpoint --quiet ${share}
    ${pkgs.util-linux}/bin/findmnt --noheadings --mountpoint ${share} \
      --source ${lib.escapeShellArg dataset} --types zfs > /dev/null
    ${pkgs.coreutils}/bin/chown files:files ${share}
    ${pkgs.coreutils}/bin/chmod 0700 ${share}
  '';
in
{
  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.host.storage.fastDatasets.snapshot.files or null == share;
        message = "WebDAV requires host.storage.fastDatasets.snapshot.files = /srv/files.";
      }
    ];

    users.groups.files = { };
    users.users.files = {
      isSystemUser = true;
      group = "files";
      home = "/var/empty";
      shell = "${pkgs.shadow}/bin/nologin";
    };

    sops.secrets."files.htpasswd" = {
      owner = "files";
      group = "files";
      mode = "0400";
      restartUnits = [ "files.service" ];
    };

    systemd.services.files = {
      description = "Files WebDAV";
      wantedBy = [ "multi-user.target" ];
      after = [ "srv-files.mount" ];
      bindsTo = [ "srv-files.mount" ];
      unitConfig.RequiresMountsFor = [ share ];
      serviceConfig = {
        User = "files";
        Group = "files";
        UMask = "0077";
        # Mount identity must be checked on the host before entering the private root.
        ExecStartPre = [ "+${initialize}" ];
        ExecStart = lib.escapeShellArgs [
          "${pkgs.rclone}/bin/rclone"
          "serve"
          "webdav"
          share
          "--addr=127.0.0.1:${toString cfg.port}"
          "--htpasswd=/run/files.htpasswd"
          "--realm=Files"
          "--config=/dev/null"
          "--copy-links=false"
          "--links=false"
          "--vfs-links=false"
          "--local-links=false"
          "--vfs-cache-mode=off"
          "--dir-perms=0700"
          "--file-perms=0600"
          "--server-read-timeout=0"
          "--server-write-timeout=0"
          "--log-level=ERROR"
        ];
        Restart = "on-failure";
        RestartSec = "5s";
        RootDirectory = root;
        RootDirectoryStartOnly = true;
        BindPaths = [ share ];
        BindReadOnlyPaths = [ "${authFile}:/run/files.htpasswd" ];
        ProtectSystem = "strict";
        ReadWritePaths = [ share ];
        ProtectHome = true;
        PrivateDevices = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        CapabilityBoundingSet = "";
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
        ];
      };
    };

    services.nginx.virtualHosts.${domain} = {
      locations."/".extraConfig = ''
        proxy_set_header Authorization $http_authorization;
        proxy_request_buffering off;
        proxy_buffering off;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
      '';
      extraConfig = ''
        access_log off;
        client_max_body_size 0;
        client_body_timeout 3600s;
        send_timeout 3600s;
      '';
    };
  };
}
