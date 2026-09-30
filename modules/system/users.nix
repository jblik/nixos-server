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

  # Deploys pass the password with `nixos-rebuild --ask-sudo-password` (README).
  security.sudo.wheelNeedsPassword = true;

  environment.systemPackages = with pkgs; [
    ghostty.terminfo # fix for ssh sessions from ghostty: `'xterm-ghostty': unknown terminal type.`
    git
    htop
    nvtopPackages.nvidia # GPU monitoring
    pciutils # lspci
    vim
  ];
}
