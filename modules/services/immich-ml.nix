{ config, ... }:
# Offloaded Immich machine-learning (face detection + CLIP smart search) on the
# GPU. The Immich *server* and PostgreSQL stay on unraid; point that server at
# this host with:
#
#   IMMICH_MACHINE_LEARNING_URL=http://<nixos>:3003
#
# Runs as a rootless-capable podman container so it can use the NVIDIA CDI
# device. Its unit (`podman-immich-machine-learning.service`) is released when
# the GPU is handed to a VM (see host.gpu.hostServices).
let
  port = config.host.immich.machineLearningPort;
in
{
  virtualisation.podman.enable = true;

  virtualisation.oci-containers = {
    backend = "podman";
    containers.immich-machine-learning = {
      image = "ghcr.io/immich-app/immich-machine-learning:release-cuda";
      autoStart = true;
      ports = [ "${toString port}:3003" ];
      volumes = [ "immich-ml-cache:/cache" ];
      # Expose the GPU via the NVIDIA container toolkit (CDI).
      extraOptions = [ "--device=nvidia.com/gpu=all" ];
    };
  };
}
