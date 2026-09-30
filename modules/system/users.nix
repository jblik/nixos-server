{ pkgs, ... }:
# Primary admin user. Member of the groups needed to manage VMs and containers.
{
  users.users.jblik = {
    isNormalUser = true;
    description = "jblik";
    extraGroups = [
      "wheel" # sudo
      "networkmanager"
      "libvirtd" # manage VMs without root
      "kvm"
      "podman" # manage the ML offload container
      "video"
      "render"
    ];

    # CHANGE THIS after first boot (`passwd`), or replace with SSH keys below.
    initialPassword = "changeme";

    openssh.authorizedKeys.keys = [
      # "ssh-ed25519 AAAA... you@host"
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
