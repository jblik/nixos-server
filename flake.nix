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

      formatterSystems = [
        "x86_64-linux"
        "aarch64-darwin"
      ];

      pkgs-unstable = import nixpkgs-unstable {
        inherit system;
        config.allowUnfree = true;
      };

      mkHost =
        hostPath: moduleSet:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs pkgs-unstable; };
          modules = [
            {
              nixpkgs.hostPlatform = system;
              system.configurationRevision = self.rev or self.dirtyRev or null;
            }
            moduleSet
            hostPath
          ];
        };

      # Base OS only (MIGRATION phase 2): no NVIDIA/CUDA, storage, services or
      # VMs, so it installs from the binary cache without compiling anything.
      baseModules = {
        imports = [
          ./modules/options.nix
          ./modules/system
        ];
      };
    in
    {
      formatter = nixpkgs.lib.genAttrs formatterSystems (s: nixpkgs.legacyPackages.${s}.nixfmt-tree);

      nixosConfigurations."nixos-server" = mkHost ./hosts/nixos-server ./modules;
      nixosConfigurations."nixos-server-base" = mkHost ./hosts/nixos-server baseModules;
    };
}
