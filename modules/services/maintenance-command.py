from datetime import datetime, time
import json
import os
from pathlib import Path
import sys


def active(task, defaults, state, now):
    shared = {
        "Start": defaults["Window"]["start"],
        "End": defaults["Window"]["end"],
    }
    window = defaults["Tasks"][task]
    if window != defaults["Window"]:
        shared = {"Start": window["start"], "End": window["end"]}
    else:
        shared = {key: state.get(key, value) for key, value in shared.items()}
    window = (state.get("TaskWindows") or {}).get(task, shared)
    start = time.fromisoformat(window["Start"])
    end = time.fromisoformat(window["End"])
    inside = start <= now < end if start <= end else now >= start or now < end
    return state.get("Enabled", True) and inside


def main():
    task, command = sys.argv[1:]
    defaults = json.loads(Path(os.environ["MAINTENANCE_DEFAULTS"]).read_text())
    file = Path(os.environ["MAINTENANCE_STATE"])
    state = json.loads(file.read_text()) if file.exists() else {}
    enabled = active(task, defaults, state, datetime.now().time())
    os.environ["MAINTENANCE_ACTIVE"] = str(enabled).lower()
    os.execv(command, [command])


if __name__ == "__main__":
    main()
