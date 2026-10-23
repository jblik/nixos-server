import os

import requests


def main():
    active = os.environ["MAINTENANCE_ACTIVE"] == "true"
    session = requests.Session()
    session.trust_env = False
    url = os.environ["TDARR_URL"] + "/api/v2"
    response = session.get(url + "/get-nodes", timeout=10)
    response.raise_for_status()
    for node_id, node in response.json().items():
        if node["nodeName"] == os.environ["TDARR_NODE"]:
            break
    else:
        raise RuntimeError("Tdarr node has not registered yet")
    if node.get("nodePaused") != (not active):
        data = {
            "nodeID": node_id,
            "nodeUpdates": {"nodePaused": not active},
        }
        response = session.post(
            url + "/update-node", json={"data": data}, timeout=10
        )
        response.raise_for_status()


if __name__ == "__main__":
    main()
