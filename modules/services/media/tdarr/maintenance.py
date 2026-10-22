import os

import requests


def main():
    active = os.environ["MAINTENANCE_ACTIVE"] == "true"
    session = requests.Session()
    session.trust_env = False
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


if __name__ == "__main__":
    main()
