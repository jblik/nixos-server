import json
import os
from pathlib import Path

import requests


def main():
    active = os.environ["MAINTENANCE_ACTIVE"] == "true"
    session = requests.Session()
    session.trust_env = False
    if os.environ["TASK"] == "tdarr":
        url = os.environ["TDARR_URL"] + "/api/v2/cruddb"
        data = {
            "collection": "NodeJSONDB",
            "mode": "getById",
            "docID": os.environ["TDARR_NODE"],
        }
        response = session.post(url, json={"data": data}, timeout=10)
        response.raise_for_status()
        node = response.json()
        if not node:
            raise RuntimeError("Tdarr node has not registered yet")
        if node.get("nodePaused") != (not active):
            data.update(mode="update", obj={"nodePaused": not active})
            response = session.post(url, json={"data": data}, timeout=10)
            response.raise_for_status()
    else:
        auth = json.loads(Path(os.environ["PREVIEWS_AUTH"]).read_text())
        session.headers["Authorization"] = f"Bearer {auth['token']}"
        url = os.environ["PREVIEWS_URL"] + "/api/settings"
        response = session.get(url, timeout=10)
        response.raise_for_status()
        count = int(os.environ["PREVIEWS_CPU_WORKERS"]) if active else 0
        if response.json()["cpu_threads"] != count:
            response = session.post(
                url, json={"cpu_threads": count}, timeout=10
            )
            response.raise_for_status()


if __name__ == "__main__":
    main()
