{ inputs, ... }:
{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  # Decrypted with the SSH host key (sops-nix's default for age); recipients are in .sops.yaml.
  sops.defaultSopsFile = ../../secrets/secrets.yaml;
}
