import configparser
import json
import os
from pathlib import Path
import xml.etree.ElementTree as ET

from configobj import ConfigObj
import requests


def request(session, method, url, **kwargs):
    response = session.request(method, url, timeout=30, **kwargs)
    response.raise_for_status()
    return response


def session(headers):
    client = requests.Session()
    client.trust_env = False
    client.headers.update(headers)
    return client


def upsert(client, url, values):
    entries = request(client, "GET", url).json()
    entry = next((e for e in entries if e["name"] == values["name"]), {})
    entry.update(values)
    if entry.get("id"):
        result = request(client, "PUT", f"{url}/{entry['id']}", json=entry)
        return result.json()
    return request(client, "POST", url, json=entry).json()


def configure_downloads(sportarr, base, credentials):
    profile = configparser.ConfigParser(interpolation=None)
    profile.read(credentials / "qbittorrent.conf")
    qbit_key = profile["Preferences"][r"WebUI\APIKey"]
    qbit = session({"Authorization": f"Bearer {qbit_key}"})
    qbit_url = os.environ["QBITTORRENT_URL"] + "/api/v2/torrents"
    categories = request(qbit, "GET", qbit_url + "/categories").json()
    action = "editCategory" if "sports" in categories else "createCategory"
    request(qbit, "POST", qbit_url + "/" + action, data={
        "category": "sports",
        "savePath": os.environ["SPORTS_TORRENTS"],
    })
    sabnzbd = ConfigObj(str(credentials / "sabnzbd.ini"))
    for name, kind, port, api_key, priority, remove in [
        ("qBittorrent", 0, "QBITTORRENT_PORT", qbit_key, 2, False),
        ("SABnzbd", 5, "SABNZBD_PORT",
         sabnzbd["misc"]["api_key"], 1, True),
    ]:
        client = upsert(sportarr, base + "/downloadclient", {
            "name": name,
            "type": kind,
            "host": "127.0.0.1",
            "port": int(os.environ[port]),
            "apiKey": api_key,
            "category": "sports",
            "enabled": True,
            "useSsl": False,
            "priority": priority,
            "directory": os.environ["SPORTS_TORRENTS"] if not remove else None,
            "removeCompletedDownloads": remove,
            "removeFailedDownloads": True,
            "postImportMode": 0,
        })
        request(sportarr, "POST", base + "/downloadclient/test", json=client)


def configure_prowlarr(credentials, api_key):
    key = ET.parse(credentials / "prowlarr.xml").findtext("ApiKey")
    prowlarr = session({"X-Api-Key": key})
    base = os.environ["PROWLARR_URL"] + "/api/v1"
    apps = request(prowlarr, "GET", base + "/applications").json()
    app = next((a for a in apps if a["name"] == "Sportarr"), None)
    if app is None:
        app = next(
            a for a in request(
                prowlarr, "GET", base + "/applications/schema"
            ).json()
            if a["implementation"] == "Sonarr"
        )
    app.update({"name": "Sportarr", "syncLevel": "fullSync"})
    values = {
        "prowlarrUrl": os.environ["PROWLARR_URL"],
        "baseUrl": os.environ["SPORTARR_URL"],
        "apiKey": api_key,
        "syncCategories": [5000],
        "animeSyncCategories": [],
    }
    for field in app["fields"]:
        if field["name"] in values:
            field["value"] = values[field["name"]]
    request(prowlarr, "POST", base + "/applications/test", json=app)
    if app.get("id"):
        request(prowlarr, "PUT", base + f"/applications/{app['id']}", json=app)
    else:
        request(prowlarr, "POST", base + "/applications", json=app)
    request(prowlarr, "POST", base + "/command", json={
        "name": "ApplicationIndexerSync",
    })


def configure_plex(sportarr, base, credentials):
    preferences = ET.parse(credentials / "plex.xml").getroot()
    token = preferences.attrib["PlexOnlineToken"]
    plex = session({
        "X-Plex-Token": token, "Accept": "application/json",
        "X-Plex-Pms-Api-Version": "1.2.0",
    })
    plex_url = os.environ["PLEX_URL"]
    providers_url = plex_url + "/media/providers/metadata"
    providers = request(plex, "GET", providers_url).json()["MediaContainer"]
    provider_uri = "https://sportarr.net/plex"
    provider = next(
        (p for p in providers.get("MetadataAgentProvider", [])
         if p["uri"] == provider_uri), None,
    )
    if provider is None:
        result = request(plex, "POST", providers_url, params={
            "uri": provider_uri,
        })
        provider = result.json()["MediaContainer"]["MetadataAgentProvider"][0]
    groups_url = providers_url + "/group"
    groups = request(plex, "GET", groups_url).json()["MediaContainer"]
    group = next(
        (g for g in groups.get("MetadataAgentProviderGroup", [])
         if g["primaryIdentifier"] == provider["identifier"]), None,
    )
    if group is None:
        result = request(plex, "POST", groups_url, params={
            "title": "Sportarr", "primaryIdentifier": provider["identifier"],
        })
        container = result.json()["MediaContainer"]
        group = container["MetadataAgentProviderGroup"][0]
    libraries_url = plex_url + "/library/sections"
    libraries = request(plex, "GET", libraries_url).json()["MediaContainer"]
    root = os.environ["SPORTS_ROOT"]
    library = next(
        (s for s in libraries.get("Directory", [])
         if any(p["path"] == root for p in s.get("Location", []))), None,
    )
    if library is None:
        request(plex, "POST", libraries_url + "/all", params={
            "name": "Sports", "type": 2,
            "scanner": "Plex TV Series", "agent": "tv.plex.agents.series",
            "metadataAgentProviderGroupId": group["id"],
            "language": "en", "locations": root,
        })
    notification = upsert(sportarr, base + "/notification", {
        "name": "Plex", "implementation": "Plex", "enabled": True,
        "configJson": json.dumps({
            "host": plex_url, "apiKey": token,
            "updateLibrary": True, "usePartialScan": True,
            "onDownload": True, "onUpgrade": True, "onRename": True,
        }),
    })
    request(sportarr, "POST", base + "/notification/test", json=notification)


def main():
    credentials = Path(os.environ["CREDENTIALS_DIRECTORY"])
    api_key = ET.parse(credentials / "sportarr.xml").findtext("ApiKey")
    sportarr = session({"X-Api-Key": api_key})
    base = os.environ["SPORTARR_URL"] + "/api"
    roots = request(sportarr, "GET", base + "/rootfolder").json()
    if not any(r["path"] == os.environ["SPORTS_ROOT"] for r in roots):
        request(sportarr, "POST", base + "/rootfolder", json={
            "path": os.environ["SPORTS_ROOT"],
            "defaultDownloadClientCategory": "sports",
        })
    settings = request(sportarr, "GET", base + "/settings").json()
    media = json.loads(settings["mediaManagementSettings"])
    media.update({
        "renameEvents": True, "renameFiles": True, "useHardlinks": True,
    })
    settings["mediaManagementSettings"] = json.dumps(media)
    request(sportarr, "PUT", base + "/settings", json=settings)
    configure_downloads(sportarr, base, credentials)
    configure_prowlarr(credentials, api_key)
    configure_plex(sportarr, base, credentials)
    print("Sportarr download clients, Prowlarr and Plex configured and tested")


if __name__ == "__main__":
    main()
