{ config, lib, ... }:
# *arr helpers that have no NixOS module. Host networking so they reach Plex and
# the *arr apps on localhost; all run as 99:100
let
  m = config.host.media;
  uid = "99";
  gid = "100";
  containers = {
    pulsarr = {
      image = "lakker/pulsarr:0.19.7";
      environment = {
        PUID = uid;
        PGID = gid;
        listenPort = toString m.pulsarr.port;
      };
      volumes = [ "/var/lib/pulsarr:/app/data" ];
    };

    maintainerr = {
      image = "ghcr.io/maintainerr/maintainerr:3.31.0";
      user = "${uid}:${gid}";
      environment.UI_PORT = toString m.maintainerr.port;
      volumes = [ "/var/lib/maintainerr:/opt/data" ];
    };
  };
in
{
  config = lib.mkIf m.enable {
    virtualisation.podman.enable = true;
    virtualisation.oci-containers.backend = "podman";

    systemd.tmpfiles.rules = map (d: "d /var/lib/${d} 0750 ${uid} ${gid} -") (lib.attrNames containers);

    virtualisation.oci-containers.containers = lib.mapAttrs (
      _: c:
      lib.recursiveUpdate c {
        environment.TZ = config.time.timeZone;
        extraOptions = [ "--network=host" ];
      }
    ) containers;

    # Podman fails with exit 125 if the bind-mount source is missing, and an unmounted state
    # dataset would leave the container running on the empty directory underneath.
    systemd.services = lib.mapAttrs' (
      name: _:
      lib.nameValuePair "podman-${name}" {
        unitConfig.RequiresMountsFor = [
          "/var/lib/${name}"
        ];
      }
    ) containers;
  };
}
