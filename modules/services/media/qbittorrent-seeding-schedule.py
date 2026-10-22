import argparse
import configparser
from datetime import datetime, time
import fcntl
import json
import os
from pathlib import Path
import sys

import requests


def arguments():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--profile", default=os.environ.get("QBITTORRENT_PROFILE")
    )
    parser.add_argument("--url", default=os.environ.get("QBITTORRENT_URL"))
    parser.add_argument(
        "--enabled", default=os.environ.get("MAINTENANCE_ENABLED")
    )
    parser.add_argument("--start", default=os.environ.get("MAINTENANCE_START"))
    parser.add_argument("--end", default=os.environ.get("MAINTENANCE_END"))
    return parser.parse_args()


def reconcile(args, state):
    profile = configparser.ConfigParser(interpolation=None)
    profile.read(args.profile)
    session = requests.Session()
    session.trust_env = False
    api_key = profile["Preferences"][r"WebUI\APIKey"]
    session.headers["Authorization"] = f"Bearer {api_key}"
    url = args.url + "/api/v2/torrents/"
    stopped = set(json.loads(state.read_text())) if state.exists() else set()

    if os.environ.get("QBITTORRENT_UPDATE_HOOK") == "true":
        command = (
            f'"{sys.argv[0]}" --profile "{args.profile}" --url "{args.url}" '
            f'--enabled {args.enabled} --start {args.start} --end {args.end}'
        )
        response = session.post(
            args.url + "/api/v2/app/setPreferences",
            data={"json": json.dumps({
                "autorun_enabled": True, "autorun_program": command,
            })}, timeout=10,
        )
        response.raise_for_status()

    response = session.get(url + "info", timeout=10)
    response.raise_for_status()
    torrents = {torrent["hash"]: torrent for torrent in response.json()}
    stopped.intersection_update(torrents)
    start = time.fromisoformat(args.start)
    end = time.fromisoformat(args.end)
    now = datetime.now().time()
    inside = start <= now < end if start <= end else now >= start or now < end
    nighttime = args.enabled == "true" and inside

    if nighttime:
        hashes = [
            torrent_hash for torrent_hash in stopped
            if torrents[torrent_hash]["state"] == "stoppedUP"
            and (
                torrents[torrent_hash]["max_ratio"] < 0
                or torrents[torrent_hash]["ratio"]
                < torrents[torrent_hash]["max_ratio"]
            )
            and (
                torrents[torrent_hash]["max_seeding_time"] < 0
                or torrents[torrent_hash]["seeding_time"]
                < torrents[torrent_hash]["max_seeding_time"] * 60
            )
        ]
        action = "start"
    else:
        hashes = [
            torrent_hash for torrent_hash, torrent in torrents.items()
            if torrent["state"] in (
                "uploading", "stalledUP", "queuedUP", "forcedUP"
            ) or (
                torrent.get("progress", 0) == 1
                and torrent["state"] not in (
                    "stoppedUP", "stoppedDL", "error", "missingFiles"
                )
            )
        ]
        stopped.update(hashes)
        action = "stop"

    # Persist ownership before stopping so a restart cannot strand these seeds.
    temporary = state.with_suffix(".tmp")
    temporary.write_text(json.dumps(sorted(stopped)))
    temporary.replace(state)
    if hashes:
        response = session.post(
            url + action, data={"hashes": "|".join(hashes)}, timeout=10
        )
        response.raise_for_status()
        print(f"{action}: {len(hashes)} completed torrents")
    if nighttime:
        temporary.write_text("[]")
        temporary.replace(state)


def main():
    args = arguments()
    directory = Path(args.profile).parents[1]
    with (directory / "seeding-schedule.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        reconcile(args, directory / "seeding-stopped.json")


if __name__ == "__main__":
    main()
