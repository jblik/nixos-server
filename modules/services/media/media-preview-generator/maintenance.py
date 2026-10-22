import json
import os
from pathlib import Path

import requests


def main():
    active = os.environ["MAINTENANCE_ACTIVE"] == "true"
    session = requests.Session()
    session.trust_env = False
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
