# Every package that doesn't come from the nixos-26.05 nixpkgs. `nix eval .#versions`
# lists each one with the version 26.05 has; README.md says when they can go.
{ pkgs-unstable }:
final: prev:
let
  # Unraid runs 2.91.01 and its database gets imported; unstable only has 2.87.01.
  tdarr =
    component: hash:
    pkgs-unstable."tdarr-${component}".overrideAttrs (
      finalAttrs: _: {
        version = "2.91.01";
        src = prev.fetchzip {
          url = "https://storage.tdarr.io/versions/${finalAttrs.version}/linux_x64/Tdarr_${
            if component == "server" then "Server" else "Node"
          }.zip";
          inherit hash;
          stripRoot = false;
        };
      }
    );
in
{
  # Not older than unraid's, whose databases get imported; a downgrade can't open them.
  plex = pkgs-unstable.plex;
  radarr = pkgs-unstable.radarr;
  bazarr = pkgs-unstable.bazarr;
  tdarr-server = tdarr "server" "sha256-QWXV8a9UJZXD/Obo8xDICAtN2ZndInD5/M/W8e/Xd5M=";
  tdarr-node = tdarr "node" "sha256-IbYyaxeYGVoWN/zadvhrblFRddtRc6ALyBABNzq0Wdc=";
  tdarrPackages = {
    server = final.tdarr-server;
    node = final.tdarr-node;
  };

  # 26.05 only has the end-of-life 2.x, marked insecure; 3.x needs the same vectorchord.
  immich = pkgs-unstable.immich;

  # unraid runs 3.x and the importer needs the same version; 26.05 only has 2.x.
  paperless-ngx = pkgs-unstable.paperless-ngx.override {
    extraPythonPackageOverrides = _final: prev: {
      # Uncached on unstable: its mp3 encoder tests fail against nixpkgs' ffmpeg.
      torchcodec = prev.torchcodec.overridePythonAttrs (old: {
        disabledTests = old.disabledTests ++ [ "test_audio_against_cli" ];
      });
    };
  };
}
