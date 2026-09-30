{
  description = "NixOS GPU/compute server (AI + ML offload + VFIO passthrough VMs)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixpkgs-unstable,
    }:
    let
      system = "x86_64-linux";

      # The server is x86_64-linux, but the config is edited from a Mac — expose
      # the formatter for both so `nix fmt` works wherever you are.
      formatterSystems = [
        "x86_64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
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
