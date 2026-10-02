{
  description = "NixOS home server (storage array, media stack, local AI)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
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
      nixpkgs-unstable,
      ...
    }:
    let
      system = "x86_64-linux";

      formatterSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };

      overlay = import ./packages.nix { inherit pkgs-unstable; };

      mkHost =
        hostPath:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs pkgs-unstable; };
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
