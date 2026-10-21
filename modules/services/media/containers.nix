{ config, lib, ... }:
{
  config = lib.mkIf config.host.media.enable {
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";
  };
}
