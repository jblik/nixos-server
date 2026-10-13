{
  description = "NixOS home server (storage array, media stack, local AI)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-plex.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-bazarr.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-tdarr.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-immich.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-paperless.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nixpkgs-sonarr.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-radarr.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-jackett.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-flaresolverr.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-qbittorrent.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-forgejo.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-microbin.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-coolercontrol.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-node-exporter.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-prometheus.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-alertmanager.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-grafana.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-tailscale.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-ollama.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-open-webui.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-postgresql.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-redis.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-nginx.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-cloudflare-dyndns.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-speedtest.url = "github:NixOS/nixpkgs/nixos-26.05";
    server-dashboard = {
      url = "git+ssh://forgejo@git.steenblik.ch:2222/jblik/server-dashboard.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      ...
    }:
    let
      system = "x86_64-linux";

      formatterSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      applicationPkgs = nixpkgs.lib.mapAttrs' (
        name: input:
        nixpkgs.lib.nameValuePair (nixpkgs.lib.removePrefix "nixpkgs-" name) (
          import input {
            inherit system;
            config.allowUnfree = true;
          }
        )
      ) (nixpkgs.lib.filterAttrs (name: _: nixpkgs.lib.hasPrefix "nixpkgs-" name) inputs);

      overlay = import ./packages.nix { inherit applicationPkgs; };

      mkHost =
        hostPath:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            {
              nixpkgs.hostPlatform = system;
              nixpkgs.overlays = [ overlay ];
              system.configurationRevision = self.rev or self.dirtyRev or null;
            }
            ./modules
            hostPath
          ];
        };
    in
    {
      formatter = nixpkgs.lib.genAttrs formatterSystems (s: nixpkgs.legacyPackages.${s}.nixfmt-tree);

      nixosConfigurations."nixos-server" = mkHost ./hosts/nixos-server;

      versions =
        let
          inherit (self.nixosConfigurations."nixos-server") pkgs;
          stable = import nixpkgs {
            inherit system;
            config.allowUnfree = true;
          };
        in
        nixpkgs.lib.mapAttrs (name: _: {
          here = pkgs.${name}.version;
          nixpkgs = stable.${name}.version;
        }) (nixpkgs.lib.filterAttrs (_: nixpkgs.lib.isDerivation) (overlay pkgs pkgs));
    };
}
