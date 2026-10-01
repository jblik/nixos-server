{
  config,
  lib,
  inputs,
  pkgs-unstable,
  ...
}:
let
  domain = "paperless.internal.steenblik.ch";
in
{
  # unraid runs 3.x and the importer needs the same version; 26.05's module only handles 2.x.
  disabledModules = [ "services/misc/paperless.nix" ];
  imports = [ "${inputs.nixpkgs-unstable}/nixos/modules/services/misc/paperless.nix" ];

  config = lib.mkIf config.host.paperless.enable {
    services.paperless = {
      enable = true;
      package = pkgs-unstable.paperless-ngx;
      inherit domain;
      mediaDir = "${config.host.storage.bulkMount}/documents";
      database.createLocally = true;
      configureTika = true;
    };

    # Its default 3000 is Forgejo's HTTP port.
    services.gotenberg.port = 3001;

    services.nginx.virtualHosts.${domain}.extraConfig = ''
      client_max_body_size 512M;
    '';
  };
}
