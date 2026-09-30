{ ... }:
# Nix daemon settings + housekeeping.
{
  nix.settings = {
    experimental-features = [
      "nix-command"
      "flakes"
    ];
    auto-optimise-store = true;
  };

  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 14d";
  };

  # Required for the NVIDIA driver, Plex and CUDA.
  nixpkgs.config.allowUnfree = true;
}
