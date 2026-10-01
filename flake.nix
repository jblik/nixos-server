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

      mkHost =
        hostPath:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs pkgs-unstable; };
          modules = [
            {
              nixpkgs.hostPlatform = system;
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
    };
}
