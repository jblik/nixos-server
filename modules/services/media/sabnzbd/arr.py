import os
from pathlib import Path
import xml.etree.ElementTree as ET

from configobj import ConfigObj
import requests


def main():
    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
    sabnzbd = ConfigObj(str(credentials / "sabnzbd.ini"))
    api_key = ET.parse(credentials / "arr.xml").findtext("ApiKey")
    session = requests.Session()
    session.trust_env = False
    session.headers["X-Api-Key"] = api_key
    base = os.environ["ARR_URL"] + "/api/v3"

    def request(method, path, **kwargs):
        response = session.request(method, base + path, timeout=30, **kwargs)
        response.raise_for_status()
        return response.json()

    clients = request("GET", "/downloadclient")
    client = next((c for c in clients if c["name"] == "SABnzbd"), None)
    if client is None:
        client = next(
            c for c in request("GET", "/downloadclient/schema")
            if c["implementation"] == "Sabnzbd"
        )
    client.update({
        "name": "SABnzbd",
        "enable": True,
        "priority": 1,
        "removeCompletedDownloads": True,
        "removeFailedDownloads": True,
    })
    values = {
        "host": "127.0.0.1",
        "port": int(os.environ["SABNZBD_PORT"]),
        "useSsl": False,
        "apiKey": sabnzbd["misc"]["api_key"],
        os.environ["CATEGORY_FIELD"]: os.environ["CATEGORY"],
    }
    for field in client["fields"]:
        if field["name"] in values:
            field["value"] = values[field["name"]]
    client_id = client.get("id")
    if client_id:
        request("PUT", f"/downloadclient/{client_id}", json=client)
    else:
        request("POST", "/downloadclient", json=client)

    settings = request("GET", "/config/downloadclient")
    settings["enableCompletedDownloadHandling"] = True
    request("PUT", "/config/downloadclient", json=settings)


if __name__ == "__main__":
    main()
