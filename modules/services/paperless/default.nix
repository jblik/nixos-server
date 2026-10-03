{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (config.services.paperless) mediaDir;
  domain = "documents.steenblik.ch";
  thumbnails = "${mediaDir}/documents/thumbnails";
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

    # The media dir, originals included, stays on the fast tier: opening or editing a document
    # stats its original, so nothing of Paperless' may sit on the array or it wakes the disks.
    # Without the thumbnails mount Paperless would write into the folder underneath it. The task
    # queue is not bound to the scheduler like web and consumer, so each unit gets it.
    systemd.services.paperless-scheduler.unitConfig.RequiresMountsFor = [ thumbnails ];
    systemd.services.paperless-task-queue.unitConfig.RequiresMountsFor = [ thumbnails ];
    systemd.services.paperless-consumer.unitConfig.RequiresMountsFor = [ thumbnails ];
    systemd.services.paperless-web.unitConfig.RequiresMountsFor = [ thumbnails ];

    # Its default 3000 is Forgejo's HTTP port.
    services.gotenberg.port = 3001;

    services.nginx.virtualHosts.${domain}.extraConfig = ''
      client_max_body_size 512M;
    '';
  };
}
