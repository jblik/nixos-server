from collections import Counter
import configparser
import json
import os
from pathlib import Path
import time

import requests


def main():
    profile = configparser.ConfigParser(interpolation=None)
    profile.read(os.environ["QBITTORRENT_PROFILE"])
    session = requests.Session()
    session.trust_env = False
    api_key = profile["Preferences"][r"WebUI\APIKey"]
    session.headers["Authorization"] = f"Bearer {api_key}"
    response = session.get(
        os.environ["QBITTORRENT_URL"] + "/api/v2/sync/maindata",
        params={"rid": 0}, timeout=10,
    )
    response.raise_for_status()
    data = response.json()
    server = data["server_state"]
    torrents = data.get("torrents", {}).values()
    metrics = {
        "download_bytes_per_second": server["dl_info_speed"],
        "upload_bytes_per_second": server["up_info_speed"],
        "session_download_bytes": server["dl_info_data"],
        "session_upload_bytes": server["up_info_data"],
        "downloaded_bytes_total": server["alltime_dl"],
        "uploaded_bytes_total": server["alltime_ul"],
        "peers": server["total_peer_connections"],
        "dht_nodes": server["dht_nodes"],
        "free_space_bytes": server["free_space_on_disk"],
        "torrents": len(torrents),
        "remaining_bytes": sum(torrent["amount_left"] for torrent in torrents),
        "timestamp_seconds": time.time(),
    }
    lines = [f"qbittorrent_{name} {value}" for name, value in metrics.items()]
    states = Counter(torrent["state"] for torrent in torrents)
    lines.extend(
        f'qbittorrent_torrents_by_state{{state={json.dumps(state)}}} {count}'
        for state, count in sorted(states.items())
    )
    status = server["connection_status"]
    lines.extend(
        f'qbittorrent_connection_status{{status="{value}"}} '
        f"{int(status == value)}"
        for value in ("connected", "firewalled", "disconnected")
    )
    output = Path(os.environ["METRICS_DIRECTORY"]) / "qbittorrent.prom"
    temporary = output.with_suffix(".prom.tmp")
    temporary.write_text("\n".join(lines) + "\n")
    temporary.replace(output)


if __name__ == "__main__":
    main()
