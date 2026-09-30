{ pkgs, ... }:
{
  users.users.jblik = {
    isNormalUser = true;
    description = "jblik";
    extraGroups = [
      "wheel" # sudo
      "networkmanager"
      "video"
      "render"
    ];

    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIBfHf/iYhriCr1edvZcQZD+vdxjNwBzOqrh/k7zZlgi jblik@Mac.lan"
    ];
  };

  # Allow wheel members to sudo.
  security.sudo.wheelNeedsPassword = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    pciutils # lspci — needed to find GPU PCI IDs
    nvtopPackages.nvidia # GPU monitoring
  ];
}
