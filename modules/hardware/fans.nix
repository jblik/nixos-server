{ config, pkgs, ... }:
# Fan control by CoolerControl. Its profiles and channel assignments are state in
# /etc/coolercontrol, edited from its UI (fans.internal.steenblik.ch), its API or
# the dashboard.
#
# The board's NCT6798D is reached through ASUS WMI (nct6775 knows this board), so
# no `acpi_enforce_resources=lax` is needed. Every header controls its fan in PWM
# mode: the driver rejects DC mode on 2-7, and fan1 barely slows in DC.
#   fan1 CHA_FAN1, fan3 CHA_FAN2, fan4 CHA_FAN3 (front), fan6 AIO_PUMP (rear),
#   fan2 CPU_FAN, fan5 chipset, fan7 CPU_OPT (empty)
{
  boot.kernelModules = [
    "nct6775"
    "drivetemp"
  ];

  systemd.packages = [ pkgs.coolercontrol.coolercontrold ];

  systemd.services.coolercontrold = {
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    environment = {
      CC_PORT = toString config.host.fans.port;
      CC_HOST_IP4 = "127.0.0.1";
      CC_HOST_IP6 = "";
      # nginx terminates TLS.
      CC_TLS = "OFF";
    };
  };
}
