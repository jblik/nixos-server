{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (config.host.storage) bulkMount;
  inherit (config.services.paperless) dataDir mediaDir user;
  domain = "documents.steenblik.ch";
  originals = "${bulkMount}/documents/originals";
  mounts = [
    "${mediaDir}/documents/thumbnails"
    "${mediaDir}/documents/originals"
  ];
in
{
  # unraid runs 3.x and the importer needs the same version; 26.05's module only handles 2.x.
  disabledModules = [ "services/misc/paperless.nix" ];
  imports = [ "${inputs.nixpkgs-unstable}/nixos/modules/services/misc/paperless.nix" ];

  config = lib.mkIf config.host.paperless.enable {
    sops.secrets."paperless.env" = { };

    services.paperless = {
      enable = true;
      inherit domain;
      database.createLocally = true;
      configureTika = true;
      environmentFile = config.sops.secrets."paperless.env".path;
      settings = {
        PAPERLESS_APP_TITLE = "Bear Docs";
        PAPERLESS_OCR_LANGUAGE = "eng+deu+ita";
        PAPERLESS_FILENAME_FORMAT = "{{ created }}-{{ correspondent }}-{{ title }}";
        PAPERLESS_TRUSTED_PROXIES = "127.0.0.1";
        PAPERLESS_EMAIL_HOST = "smtp.mail.me.com";
        PAPERLESS_EMAIL_PORT = 587;
        PAPERLESS_EMAIL_FROM = "noreply@steenblik.ch";
        PAPERLESS_EMAIL_USE_TLS = true;
        PAPERLESS_POST_CONSUME_SCRIPT = "${pkgs.writers.writePython3 "paperless-post-consume" {
          libraries = [ pkgs.python3Packages.requests ];
          flakeIgnore = [
            "E241"
            "E501"
          ];
        } (builtins.readFile ./post_consume.py)}";
      };
    };

    # Consumption, and so the post-consume script, runs in the Celery worker.
    systemd.services.paperless-task-queue.environment.POST_CONSUME_API_URL =
      "http://${config.services.paperless.address}:${toString config.services.paperless.port}";

    systemd.tmpfiles.rules = [
      "d ${originals} 0700 ${user} ${config.users.users.${user}.group} -"
    ];

    # The media dir stays on the fast tier so thumbnails and previews (the archived PDFs) leave
    # the disks asleep; only the originals are bound in from the array, as for Immich.
    fileSystems."${mediaDir}/documents/originals" = {
      device = originals;
      fsType = "none";
      options = [
        "bind"
        "nofail"
      ];
      depends = [
        bulkMount
        dataDir
      ];
    };

    # Without the mounts Paperless would write into the folders underneath them. The task queue
    # is not bound to the scheduler like web and consumer, so each unit gets them.
    systemd.services.paperless-scheduler.unitConfig.RequiresMountsFor = mounts;
    systemd.services.paperless-task-queue.unitConfig.RequiresMountsFor = mounts;
    systemd.services.paperless-consumer.unitConfig.RequiresMountsFor = mounts;
    systemd.services.paperless-web.unitConfig.RequiresMountsFor = mounts;

    # Its default 3000 is Forgejo's HTTP port.
    services.gotenberg.port = 3001;

    services.nginx.virtualHosts.${domain}.extraConfig = ''
      client_max_body_size 512M;
    '';
  };
}
