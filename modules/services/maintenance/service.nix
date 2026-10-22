{
  config,
  lib,
  pkgs,
}:
{
  task,
  description,
  unit,
  script,
  environment,
}:
let
  maintenance = import ./. { inherit config lib pkgs; };
in
{
  inherit description;
  unitConfig.StartLimitIntervalSec = 0;
  wantedBy = [ unit ];
  after = [ unit ];
  partOf = [ unit ];
  environment = environment // {
    TZ = config.time.timeZone;
  };
  serviceConfig = {
    Type = "oneshot";
    Restart = "on-failure";
    RestartSec = "10s";
    ExecStart = maintenance.command task (maintenance.script "${task}-maintenance" script);
  };
}
