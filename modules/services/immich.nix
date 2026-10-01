{
  config,
  lib,
  pkgs-unstable,
  ...
}:
let
  inherit (config.host.storage) bulkMount;
  domain = "photos.steenblik.ch";
  mediaLocation = "${bulkMount}/photos";
  mlPort = 3004;
in
{
  config = lib.mkIf config.host.immich.enable {
    services.immich = {
      enable = true;
      # 26.05 only has the end-of-life 2.x, marked insecure; 3.x needs the same vectorchord.
      package = pkgs-unstable.immich;
      # The default "localhost" binds only ::1, while nginx proxies to 127.0.0.1.
      host = "127.0.0.1";
      inherit mediaLocation;
      # nixpkgs has no cached CUDA onnxruntime for 3.x, so the upstream CUDA image runs it instead.
      machine-learning.enable = false;
      environment.IMMICH_MACHINE_LEARNING_URL = lib.mkForce "http://127.0.0.1:${toString mlPort}";
    };

    hardware.nvidia-container-toolkit.enable = true;
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    virtualisation.oci-containers.containers.immich-machine-learning = {
      image = "ghcr.io/immich-app/immich-machine-learning:v${config.services.immich.package.version}-cuda";
      environment = {
        TZ = config.time.timeZone;
        IMMICH_HOST = "127.0.0.1";
        IMMICH_PORT = toString mlPort;
      };
      volumes = [ "/var/cache/immich-machine-learning:/cache" ];
      extraOptions = [
        "--network=host"
        "--device=nvidia.com/gpu=all"
      ];
    };

    systemd.tmpfiles.rules = [
      "d ${mediaLocation} 0700 immich immich -"
      "d /var/cache/immich-machine-learning 0750 root root -"
    ];

    systemd.services.immich-server.unitConfig.RequiresMountsFor = [ bulkMount ];

    services.nginx.virtualHosts.${domain}.extraConfig = ''
      client_max_body_size 50000M;
      proxy_read_timeout 600s;
      proxy_send_timeout 600s;
    '';
  };
}
