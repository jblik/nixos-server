{ ... }:
# Per-host entry point. Imports the machine's generated hardware config and
# sets the site-specific knobs declared in modules/options.nix.
{
  imports = [
    ./hardware-configuration.nix
  ];

  host = {
    hostname = "nixos-server";
    timezone = "Europe/Brussels";

    # Assumed AMD; flip to "intel" if needed (see modules/options.nix).
    cpuVendor = "amd";

    # Tighten to your real subnet.
    lanCidr = "192.168.0.0/16";

    # === FILL IN ON THE REAL MACHINE ===
    # lspci -nn  | grep -i nvidia   -> vendorIds (GPU + HDMI audio)
    # lspci -D   | grep -i nvidia   -> busIds
    gpu = {
      vendorIds = [
        # "10de:XXXX"  # GPU
        # "10de:YYYY"  # GPU HDMI audio
      ];
      busIds = [
        # "0000:01:00.0"  # GPU
        # "0000:01:00.1"  # GPU HDMI audio
      ];
    };
  };

  # Do not change after install unless you know what you're doing.
  system.stateVersion = "26.05";
}
