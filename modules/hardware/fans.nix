{
  config,
  lib,
  pkgs,
  ...
}:
# Fan control by CoolerControl, with its UI at fans.internal.steenblik.ch.
#
# The curves below are defaults: coolercontrol-defaults writes them through the API
# whenever they change here, and otherwise leaves alone what the UI changed. It also
# keeps a write token for the dashboard in /var/lib/coolercontrol-defaults. The UI
# password is the `coolercontrol-password` secret; change it there, not in the UI.
#
# The board's NCT6798D is reached through ASUS WMI (nct6775 knows this board), so
# no `acpi_enforce_resources=lax` is needed. Every header controls its fan in PWM
# mode: the driver rejects DC mode on 2-7, and fan1 barely slows in DC.
#   fan1 CHA_FAN1, fan3 CHA_FAN2, fan4 CHA_FAN3 (front), fan6 AIO_PUMP (rear),
#   fan2 CPU_FAN, fan5 chipset, fan7 CPU_OPT (empty)
# The GPU fans keep the card's own zero-rpm curve.
let
  api = "http://127.0.0.1:${toString config.host.fans.port}";
  stateDir = "/var/lib/coolercontrol-defaults";
  board = "nct6798";

  # A sensor, found by its device's name (or disk model) and the sensor's label.
  sensor = device: label: { inherit device label; };

  # Lower duties may not start a stopped fan.
  startDuty = 35;

  # Off up to `off` °C, then `startDuty` up to full speed at `full` °C.
  graph = uid: name: source: off: full: {
    inherit uid name;
    p_type = "Graph";
    temp_source = source;
    function_uid = "calm";
    member_profile_uids = [ ];
    speed_profile = [
      [
        0
        0
      ]
      [
        off
        0
      ]
      [
        (off + 1)
        startDuty
      ]
      [
        full
        100
      ]
      [
        100
        100
      ]
    ];
  };

  # Tdie jumps by ~10 °C every few seconds even at idle.
  smoothed = profile: profile // { function_uid = "smooth"; };

  mix = uid: name: members: {
    inherit uid name;
    p_type = "Mix";
    function_uid = "0";
    member_profile_uids = members;
    mix_function_type = "Max";
  };

  cpuTemp = sensor "AMD Ryzen 7 2700X Eight-Core Processor" "CPU Temp Tdie";

  caseSources = [
    (smoothed (graph "case-cpu" "Case: CPU" cpuTemp 65 85))
    (graph "case-gpu" "Case: GPU" (sensor "NVIDIA GeForce RTX 3060" "GPU Temp") 60 80)
    (graph "case-hdd" "Case: disk1" (sensor "ST10000NE0008-2P" "Temp1") 45 55)
    (graph "case-sandisk" "Case: SanDisk" (sensor "SanDisk SSD PLUS" "Temp1") 60 70)
    (graph "case-peaq" "Case: PEAQ" (sensor "PEAQ    SSD_256G" "Temp1") 60 70)
    (graph "case-nvme" "Case: NVMe" (sensor "ADATA SX8200NP" "Composite") 65 75)
  ];

  defaults = {
    settings = {
      # disk1 spins down; reading its temperature must not wake it.
      drivetemp_suspend = true;
      protocol_header = "X-Forwarded-Proto";
    };

    functions = [
      {
        uid = "calm";
        name = "Calm";
        f_type = "Standard";
        duty_minimum = 2;
        duty_maximum = 100;
        step_size_min_decreasing = 0;
        step_size_max_decreasing = 0;
        response_delay = 3;
        # Hysteresis: a fan only slows once it is 3 °C cooler, so it does not flap at `off`.
        deviance = 3;
        only_downward = true;
        threshold_hopping = true;
        bypass_min_at_extremes = true;
      }
      {
        uid = "smooth";
        name = "Smooth";
        f_type = "ExponentialMovingAvg";
        duty_minimum = 2;
        duty_maximum = 100;
        step_size_min_decreasing = 0;
        step_size_max_decreasing = 0;
        sample_window = 20;
        threshold_hopping = true;
        bypass_min_at_extremes = true;
      }
    ];

    profiles = caseSources ++ [
      (mix "case" "Case" (map (p: p.uid) caseSources))
      (smoothed (graph "cpu" "CPU" cpuTemp 60 85))
      (graph "chipset" "Chipset" (sensor board "Smbusmaster 1") 80 95)
      {
        uid = "full";
        name = "Full";
        p_type = "Fixed";
        speed_fixed = 100;
        function_uid = "0";
        member_profile_uids = [ ];
      }
    ];

    # The first mode is the one activated after applying.
    modes =
      let
        quiet = {
          fan1 = "case";
          fan3 = "case";
          fan4 = "case";
          fan6 = "case";
          fan2 = "cpu";
          fan5 = "chipset";
        };
      in
      [
        {
          name = "Quiet";
          channels = quiet;
        }
        {
          name = "Full";
          channels = lib.mapAttrs (_: _: "full") quiet;
        }
      ];

    device = board;
  };

  defaultsFile = pkgs.writeText "coolercontrol-defaults.json" (builtins.toJSON defaults);

  applyDefaults = pkgs.writeShellApplication {
    name = "coolercontrol-defaults";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = builtins.readFile ./coolercontrol-defaults.sh;
  };
in
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

  sops.secrets.coolercontrol-password = { };

  systemd.services.coolercontrol-defaults = {
    description = "Apply the CoolerControl defaults";
    wantedBy = [ "multi-user.target" ];
    requires = [ "coolercontrold.service" ];
    after = [ "coolercontrold.service" ];
    partOf = [ "coolercontrold.service" ];
    restartTriggers = [ defaultsFile ];
    environment = {
      API = api;
      DEFAULTS = defaultsFile;
      PASSWORD_FILE = config.sops.secrets.coolercontrol-password.path;
      STATE_DIR = stateDir;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = lib.getExe applyDefaults;
      StateDirectory = "coolercontrol-defaults";
      StateDirectoryMode = "0700";
      RuntimeDirectory = "coolercontrol-defaults";
    };
  };
}
