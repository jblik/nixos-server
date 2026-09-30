{ lib, pkgs, ... }:
# Fan control by fan2go: every fan stays stopped until the CPU, GPU or a disk
# passes its threshold, then ramps linearly to full speed at the curve's `max`.
#
# The board's NCT6798D is reached through ASUS WMI (nct6775 knows this board),
# so no `acpi_enforce_resources=lax` is needed. If fan2go is stopped, it hands
# the fans back to the BIOS curve.
let
  fan2go = pkgs.fan2go.override { enableNVML = true; };

  platform = "nct6798";
  # The only header reporting RPM; the others read 0 even at full PWM.
  fanChannels = [ 5 ];

  disks = {
    hdd-disk1 = {
      device = "ata-ST10000NE0008-2PL103_ZS5072G6";
      min = 45;
      max = 55;
    };
    ssd-sandisk = {
      device = "ata-SanDisk_SSD_PLUS_240GB_1838D3805791";
      min = 55;
      max = 70;
    };
    ssd-peaq = {
      device = "ata-PEAQ_SSD_256GB_67007Y8J3000079";
      min = 55;
      max = 70;
    };
    nvme-root = {
      device = "nvme-ADATA_SX8200NP_2I3920002941";
      min = 60;
      max = 75;
    };
  };

  linear = id: min: max: {
    inherit id;
    linear = {
      sensor = id;
      inherit min max;
    };
  };

  settings = {
    dbPath = "/var/lib/fan2go/fan2go.db";
    # Disk temperatures are SMART reads; the 200ms default would hammer them.
    tempSensorPollingRate = "2s";
    tempRollingWindowSize = 10;

    sensors = [
      {
        id = "cpu";
        # Tdie; Tctl (index 1) carries a +10 °C offset on the 2700X.
        hwmon = {
          platform = "k10temp";
          index = 2;
        };
      }
      {
        id = "gpu";
        nvidia = {
          device = "nvidia";
          index = 1;
        };
      }
    ]
    ++ lib.mapAttrsToList (id: d: {
      inherit id;
      disk.device = d.device;
    }) disks;

    curves = [
      (linear "cpu" 60 80)
      (linear "gpu" 65 80)
    ]
    ++ lib.mapAttrsToList (id: d: linear id d.min d.max) disks
    ++ [
      {
        id = "case";
        function = {
          type = "maximum";
          curves = [
            "cpu"
            "gpu"
          ]
          ++ lib.attrNames disks;
        };
      }
    ];

    fans = map (channel: {
      id = "fan-${toString channel}";
      hwmon = {
        inherit platform;
        rpmChannel = channel;
      };
      neverStop = false;
      curve = "case";
    }) fanChannels;
  };

  configFile = (pkgs.formats.yaml { }).generate "fan2go.yaml" settings;
in
{
  boot.kernelModules = [
    "nct6775"
    "drivetemp"
  ];

  environment.etc."fan2go/fan2go.yaml".source = configFile;
  environment.systemPackages = [ fan2go ];

  systemd.services.fan2go = {
    description = "fan2go fan control";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    restartTriggers = [ configFile ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${lib.getExe fan2go} -c /etc/fan2go/fan2go.yaml --no-style";
      StateDirectory = "fan2go";
      Restart = "always";
      RestartSec = 10;
    };
  };
}
