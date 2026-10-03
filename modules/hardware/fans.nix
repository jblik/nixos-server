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
  sensors = config.host.sensors;
  board = sensors.motherboard.device;

  # A sensor, found by its device's name (or disk model) and the sensor's key or label.
  source = part: { inherit (part) device sensor; };

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

  caseGraph = uid: part: graph uid "Case: ${part.name}" (source part);

  caseSources = [
    (smoothed (caseGraph "case-cpu" sensors.cpu 65 85))
    (caseGraph "case-gpu" sensors.gpu 60 80)
    (caseGraph "case-hdd" sensors.disk1 45 55)
    (caseGraph "case-sandisk" sensors.sandisk 60 70)
    (caseGraph "case-peaq" sensors.peaq 60 70)
    (caseGraph "case-nvme" sensors.nvme 65 75)
  ];

  # The dashboard calls a sensor warm at the same readings (server-dashboard's Readings.fs).
  warm = {
    Cpu = 75;
    Gpu = 75;
    Board = 60;
    Chipset = 80;
    Hdd = 45;
    Ssd = 55;
    Nvme = 60;
  };

  # Off until the part is warm, then full speed.
  coolGraph = key: part: {
    uid = "cool-${key}";
    name = "Keep cool: ${part.name}";
    p_type = "Graph";
    temp_source = source part;
    function_uid = "calm";
    member_profile_uids = [ ];
    speed_profile = [
      [
        0
        0
      ]
      [
        (warm.${part.kind} - 1)
        0
      ]
      [
        warm.${part.kind}
        100
      ]
      [
        100
        100
      ]
    ];
  };

  coolSources = lib.mapAttrsToList (
    key: part: (if part.kind == "Cpu" then smoothed else lib.id) (coolGraph key part)
  ) sensors;

  # A Mix only combines Graph profiles, so the Case mix is listed by its members.
  quietGraphs = {
    case = map (p: p.uid) caseSources;
    cpu = [ "cpu" ];
    chipset = [ "chipset" ];
  };

  keepCool = lib.mapAttrsToList (
    profile: members:
    mix "keep-cool-${profile}" "Keep cool: ${profile}" (members ++ map (p: p.uid) coolSources)
  ) quietGraphs;

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

    profiles =
      caseSources
      ++ coolSources
      ++ [
        (mix "case" "Case" (map (p: p.uid) caseSources))
        (smoothed (graph "cpu" sensors.cpu.name (source sensors.cpu) 60 85))
        (graph "chipset" sensors.chipset.name (
          source sensors.chipset // { sensor = "Smbusmaster 1"; }
        ) 80 95)
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
        # For when no one is home: quiet until any part is warm, then full.
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
