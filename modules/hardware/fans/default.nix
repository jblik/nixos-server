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
#   fan1 CHA_FAN1 (top), fan3 CHA_FAN2 (middle), fan4 CHA_FAN3 (bottom),
#   fan6 AIO_PUMP (rear exhaust),
#   fan2 CPU_FAN, fan5 chipset, fan7 CPU_OPT (empty)
# The GPU fans keep the card's own zero-rpm curve.
let
  maintenance = import ../../services/maintenance { inherit config lib pkgs; };
  maintenanceService = import ../../services/maintenance/service.nix { inherit config lib pkgs; };
  keepCoolMaintenance = maintenance.script "coolercontrol-maintenance" ./maintenance.py;
  maintenanceConfig = {
    StateDirectory = "coolercontrol-maintenance";
    StateDirectoryMode = "0700";
    UMask = "0077";
  };
  api = "http://127.0.0.1:${toString config.host.fans.port}";
  stateDir = "/var/lib/coolercontrol-defaults";
  gpuExhaustFile = "/run/coolercontrol-gpu-exhaust/temperature";
  sensors = config.host.sensors;
  board = sensors.motherboard.device;

  # A sensor, found by its device's name (or disk model) and the sensor's key or label.
  source = part: { inherit (part) device sensor; };

  # Temperature keys keep the editable curves separate from the API's nested arrays.
  curve =
    points:
    map (temp: [
      (lib.toInt temp)
      points.${temp}
    ]) (lib.sort (a: b: lib.toInt a < lib.toInt b) (lib.attrNames points));

  graph = uid: name: source: points: {
    inherit uid name;
    p_type = "Graph";
    temp_source = source;
    function_uid = "calm";
    member_profile_uids = [ ];
    speed_profile = curve points;
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

  # 4.3 has no startup boost: stop-capable curves need restart duties, not running minima.
  # The probe sustained top/middle/bottom/rear at 19/27/23/17%, but restarted at 37/73/53/33%.
  caseFans = {
    front-top = {
      name = "Front top";
      channel = "fan1";
      start = 39;
      night = 45;
      sources = [
        "cpu"
        "motherboard"
        "nvme"
      ];
    };
    front-middle = {
      name = "Front middle";
      channel = "fan3";
      start = 75;
      night = 80;
      sources = [
        "gpu"
        "chipset"
        "motherboard"
        "nic"
      ];
    };
    front-bottom = {
      name = "Front bottom";
      channel = "fan4";
      start = 55;
      night = 60;
      sources = [
        "disk1"
        "disk2"
        "sandisk"
        "peaq"
        "gpu"
      ];
    };
    rear = {
      name = "Rear exhaust";
      channel = "fan6";
      start = 40;
      night = 45;
      sources = lib.attrNames caseCurves;
    };
  };

  # Keys are °C; values are PWM %. Quiet has no always-on baseline.
  curves = {
    # The probe restarted at 31%; 33% leaves a small margin after stopping.
    cpu = {
      "0" = 0;
      "60" = 0;
      "61" = 33;
      "65" = 40;
      "70" = 50;
      "75" = 70;
      "80" = 100;
      "100" = 100;
    };
    # 15% can sustain rotation but stalls on restart; the probe needed 23% to start.
    chipset = {
      "0" = 0;
      "75" = 0;
      "76" = 25;
      "80" = 25;
      "85" = 45;
      "90" = 100;
      "100" = 100;
    };
    caseCpu = {
      "0" = 0;
      "65" = 0;
      "66" = 35;
      "70" = 45;
      "75" = 65;
      "80" = 100;
      "100" = 100;
    };
    caseGpu = {
      "0" = 0;
      "60" = 0;
      "61" = 35;
      "70" = 50;
      "75" = 70;
      "80" = 100;
      "100" = 100;
    };
    rearGpu = {
      "0" = 0;
      "1" = 35;
      "60" = 35;
      "65" = 35;
      "70" = 50;
      "75" = 70;
      "80" = 100;
      "100" = 100;
    };
    caseBoard = {
      "0" = 0;
      "50" = 0;
      "51" = 35;
      "60" = 60;
      "70" = 100;
      "100" = 100;
    };
    caseChipset = {
      "0" = 0;
      "80" = 0;
      "81" = 35;
      "85" = 65;
      "90" = 100;
      "100" = 100;
    };
    caseHdd = {
      "0" = 0;
      "40" = 0;
      "41" = 35;
      "45" = 50;
      "50" = 100;
      "100" = 100;
    };
    caseSsd = {
      "0" = 0;
      "50" = 0;
      "51" = 35;
      "55" = 50;
      "65" = 100;
      "100" = 100;
    };
    caseNvme = {
      "0" = 0;
      "55" = 0;
      "56" = 35;
      "60" = 50;
      "70" = 100;
      "100" = 100;
    };
    caseNic = {
      "0" = 0;
      "69" = 0;
      "70" = 35;
      "75" = 50;
      "80" = 70;
      "85" = 100;
      "100" = 100;
    };
  };

  caseCurves = {
    cpu = curves.caseCpu;
    gpu = curves.caseGpu;
    motherboard = curves.caseBoard;
    chipset = curves.caseChipset;
    disk1 = curves.caseHdd;
    disk2 = curves.caseHdd;
    sandisk = curves.caseSsd;
    peaq = curves.caseSsd;
    nvme = curves.caseNvme;
    nic = curves.caseNic;
  };

  # The only exhaust must start with component cooling, before the intake triggers.
  rearCurves = caseCurves // {
    cpu = curves.cpu;
    chipset = curves.chipset;
    gpu = curves.rearGpu;
  };

  caseGraphs = lib.mapAttrs (
    uid: fan:
    map (
      key:
      let
        temperatureCurve = (if uid == "rear" then rearCurves else caseCurves).${key};
        points = lib.mapAttrs (_: duty: if duty == 0 then 0 else lib.max fan.start duty) temperatureCurve;
        tempSource =
          if uid == "rear" && key == "gpu" then
            {
              device = "Custom Sensors";
              sensor = "gpu-exhaust";
            }
          else
            source sensors.${key};
        profile = graph "case-${uid}-${key}" "${fan.name}: ${sensors.${key}.name}" tempSource points;
      in
      (if key == "cpu" then smoothed else lib.id) profile
    ) fan.sources
  ) caseFans;

  quietGraphs = lib.mapAttrs (_: profiles: map (p: p.uid) profiles) caseGraphs // {
    cpu = [ "cpu" ];
    chipset = [ "chipset" ];
  };

  nightDuty = lib.mapAttrs (_: fan: fan.night) caseFans // {
    cpu = 40;
    chipset = 25;
  };

  baselineGraphs = lib.mapAttrsToList (
    uid: duty:
    graph "baseline-${uid}" "Night baseline: ${uid}" (source sensors.cpu) {
      "0" = duty;
      "100" = duty;
    }
  ) nightDuty;

  # The dashboard calls a sensor warm at the same readings (server-dashboard's Readings.fs).
  warm = {
    Cpu = 75;
    Gpu = 75;
    Board = 60;
    Nic = 75;
    Chipset = 80;
    Hdd = 45;
    Ssd = 55;
    Nvme = 60;
  };

  coolSources = lib.mapAttrsToList (
    key: part:
    (if part.kind == "Cpu" then smoothed else lib.id) (
      graph "cool-${key}" "Keep cool: ${part.name}" (source part) {
        "0" = 0;
        "${toString (warm.${part.kind} - 1)}" = 0;
        "${toString warm.${part.kind}}" = 100;
        "100" = 100;
      }
    )
  ) sensors;

  keepCool = lib.mapAttrsToList (
    uid: members:
    mix "keep-cool-${uid}" "Keep cool: ${uid}" (
      members ++ [ "baseline-${uid}" ] ++ map (p: p.uid) coolSources
    )
  ) quietGraphs;

  defaults = {
    custom_sensors = [
      {
        id = "gpu-exhaust";
        cs_type = "File";
        mix_function = "Min";
        sources = [ ];
        file_path = gpuExhaustFile;
      }
    ];

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
        # Hysteresis keeps small temperature fluctuations from repeatedly slowing a fan.
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
        sample_window = 8;
        threshold_hopping = true;
        bypass_min_at_extremes = true;
      }
    ];

    profiles =
      lib.concatLists (lib.attrValues caseGraphs)
      ++ coolSources
      ++ baselineGraphs
      ++ lib.mapAttrsToList (uid: fan: mix uid fan.name quietGraphs.${uid}) caseFans
      ++ [
        (smoothed (graph "cpu" sensors.cpu.name (source sensors.cpu) curves.cpu))
        (graph "chipset" sensors.chipset.name (source sensors.chipset) curves.chipset)
        {
          uid = "full";
          name = "Full";
          p_type = "Fixed";
          speed_fixed = 100;
          function_uid = "0";
          member_profile_uids = [ ];
        }
      ]
      ++ keepCool;

    # The first mode is the one activated after applying.
    modes =
      let
        quiet = lib.mapAttrs' (uid: fan: lib.nameValuePair fan.channel uid) caseFans // {
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
        # Night airflow stays on; any warm component retains the full-speed override.
        {
          name = "Keep cool";
          channels = lib.mapAttrs (_: profile: "keep-cool-${profile}") quiet;
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

  gpuExhaust = pkgs.writeShellApplication {
    name = "coolercontrol-gpu-exhaust";
    runtimeInputs = with pkgs; [
      curl
      jq
    ];
    text = builtins.readFile ./coolercontrol-gpu-exhaust.sh;
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

  systemd.tmpfiles.rules = [
    "d /run/coolercontrol-gpu-exhaust 0755 root root -"
    "f ${gpuExhaustFile} 0644 root root - 0"
  ];

  systemd.services.coolercontrol-gpu-exhaust = {
    description = "Report GPU temperature while its fans are running";
    wantedBy = [ "multi-user.target" ];
    requires = [ "coolercontrol-defaults.service" ];
    after = [ "coolercontrol-defaults.service" ];
    partOf = [ "coolercontrold.service" ];
    environment = {
      API = api;
      GPU_DEVICE = sensors.gpu.device;
      GPU_SENSOR = sensors.gpu.sensor;
      TEMP_FILE = gpuExhaustFile;
      TOKEN_FILE = "${stateDir}/dashboard-token";
    };
    serviceConfig = {
      ExecStart = lib.getExe gpuExhaust;
      Restart = "on-failure";
      RestartSec = 2;
    };
  };

  systemd.services.coolercontrol-maintenance = lib.mkMerge [
    (maintenanceService {
      task = "keep-cool";
      description = "Apply the keep cool maintenance window";
      unit = "coolercontrol-defaults.service";
      script = ./maintenance.py;
      environment.COOLERCONTROL_URL = api;
    })
    {
      serviceConfig = maintenanceConfig // {
        LoadCredential = "coolercontrol-token:${stateDir}/dashboard-token";
      };
    }
  ];

  systemd.services.coolercontrol-maintenance-manual = {
    description = "Preserve a manual fan mode beyond the maintenance window";
    serviceConfig = maintenanceConfig // {
      Type = "oneshot";
      ExecStart = "${keepCoolMaintenance} --manual";
    };
  };

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
