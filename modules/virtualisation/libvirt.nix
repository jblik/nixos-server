{ pkgs, ... }:
# QEMU/KVM via libvirt. UEFI (OVMF) + swtpm so modern guests (SteamOS, Windows)
# install cleanly. GPU passthrough is wired up in gpu-passthrough.nix.
{
  virtualisation.libvirtd = {
    enable = true;
    onBoot = "ignore"; # don't auto-start VMs (they'd grab the GPU on boot)
    onShutdown = "shutdown";
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = true;
      swtpm.enable = true;
      ovmf = {
        enable = true;
        packages = [ pkgs.OVMFFull.fd ];
      };
    };
  };

  # GUI manager (use over SSH X-forward or from another machine).
  programs.virt-manager.enable = true;

  environment.systemPackages = with pkgs; [
    virt-manager
    looking-glass-client # low-latency display from the passthrough VM
  ];
}
