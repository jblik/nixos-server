import argparse
import fcntl
import json
import os
from pathlib import Path
from urllib.parse import quote

import requests


def reconcile(state):
    active = os.environ["MAINTENANCE_ACTIVE"] == "true"
    starting = active and not state.get("active", False)
    finishing = not active and state.get("scheduled_on", False)
    if not starting and not finishing:
        state["active"] = active
        return

    session = requests.Session()
    session.trust_env = False
    token = Path(os.environ["CREDENTIALS_DIRECTORY"], "coolercontrol-token")
    session.headers["Authorization"] = f"Bearer {token.read_text().strip()}"
    url = os.environ["COOLERCONTROL_URL"]
    response = session.get(url + "/modes-active", timeout=10)
    response.raise_for_status()
    current = response.json().get("current_mode_uid")
    response = session.get(url + "/modes", timeout=10)
    response.raise_for_status()
    modes = {mode["name"]: mode["uid"] for mode in response.json()["modes"]}
    on = modes["Keep cool"]
    off = modes["Quiet"]
    target = on if starting else off
    if (starting and current != on) or (finishing and current == on):
        response = session.post(
            url + "/modes-active/" + quote(target, safe=""), timeout=10
        )
        response.raise_for_status()

    if starting:
        # A mode already enabled by hand remains owned by the user.
        state["scheduled_on"] = (
            state.get("scheduled_on", False) or current != on
        )
    else:
        state["scheduled_on"] = False
    state["active"] = active


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manual", action="store_true")
    args = parser.parse_args()
    directory = Path(os.environ["STATE_DIRECTORY"])
    with (directory / "maintenance.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        path = directory / "state.json"
        state = json.loads(path.read_text()) if path.exists() else {}
        if args.manual:
            state["scheduled_on"] = False
        else:
            reconcile(state)
        temporary = path.with_suffix(".tmp")
        temporary.write_text(json.dumps(state))
        temporary.replace(path)


if __name__ == "__main__":
    main()
