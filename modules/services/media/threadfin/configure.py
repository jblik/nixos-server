import json
import os
from pathlib import Path
import re
import time

from websockets.sync.client import connect


def request(payload):
    with connect(os.environ["THREADFIN_URL"], open_timeout=10,
                 close_timeout=1, ping_interval=None,
                 max_size=32 * 1024 * 1024) as socket:
        socket.send(json.dumps(payload))
        response = json.loads(socket.recv(timeout=600))
    if not response.get("status"):
        raise RuntimeError(response.get("err", "Threadfin request failed"))
    return response


def main():
    mappings = json.loads(Path(os.environ["GUIDE_MAPPING"]).read_text())
    names = {}
    channel_ids = {}
    urls = {}
    for line in Path(os.environ["PLAYLIST_FILE"]).read_text().splitlines():
        if line.startswith("#EXTINF:"):
            name = line.split(",", 1)[1]
            match = re.search(r'tvg-id="([^"]*)"', line)
            channel_ids[name] = match[1] if match else ""
        elif line and not line.startswith("#"):
            names[line] = name
            urls[name] = line
    before = request({"cmd": "getServerConfig"})
    activate = before["settings"]["epgSource"] != "XEPG"
    state = before
    providers = {}
    guide_urls = {
        "SAMSUNG": "https://i.mjh.nz/SamsungTVPlus/all.xml.gz",
        "XMLTVFR": "https://xmltvfr.fr/xmltv/xmltv.xml.gz",
    }
    for source in sorted({m["source"] for m in mappings.values() if m}):
        url = guide_urls.get(source,
                             "https://epgshare01.online/epgshare01/"
                             f"epg_ripper_{source}.xml.gz")
        files = state["settings"]["files"]["xmltv"]
        provider = next((v for v in files.values()
                         if v["file.source"] == url), None)
        if provider is None:
            state = request({
                "cmd": "saveFilesXMLTV",
                "files": {"xmltv": {"-": {
                    "name": (source if source in guide_urls
                             else f"EPGShare01 {source}"),
                    "type": "xmltv",
                    "file.source": url,
                }}},
            })
            files = state["settings"]["files"]["xmltv"]
            provider = next(v for v in files.values()
                            if v["file.source"] == url)
        providers[source] = provider["file.threadfin"]
        print(f"Guide source ready: {source}", flush=True)

    settings = {
        "update": [f"{hour:02d}00" for hour in range(0, 24, 4)],
        "enableNonAscii": True,
    }
    if activate:
        settings["epgSource"] = "XEPG"
    state = request({"cmd": "saveSettings", "settings": settings})
    for _ in range(60):
        channels = (state.get("xepg") or {}).get("epgMapping") or {}
        if channels:
            break
        time.sleep(2)
        state = request({"cmd": "getServerConfig"})
    if not channels:
        raise RuntimeError("Threadfin has not created its channel mappings")

    changed = False
    for channel in channels.values():
        name = channel["name"].replace('"', "’")
        if name not in mappings:
            name = names.get(channel["url"])
        if name not in mappings:
            continue
        # Threadfin retains prior IDs when the playlist changes them.
        if channel_ids[name] and channel["tvg-id"] != channel_ids[name]:
            channel["tvg-id"] = channel_ids[name]
            channel["url"] = urls[name]
            changed = True
        if not activate and channel.get("x-xmltv-file") not in (
                None, "", "-", "Threadfin Dummy"):
            continue
        unmapped = channel.get("x-xmltv-file") in (None, "", "-")
        mapping = mappings[name]
        if mapping:
            channel["x-xmltv-file"] = providers[mapping["source"]]
            channel["x-mapping"] = mapping["id"]
            channel["x-name"] = name
        else:
            channel["x-xmltv-file"] = "Threadfin Dummy"
            channel["x-mapping"] = "240_Minutes"
            channel["x-name"] = f"{name} [No EPG]"
            channel["x-description"] = (
                "No verified programme listings are available for this feed. "
                "This is a placeholder, not a broadcast schedule."
            )
        if activate or unmapped:
            channel["x-active"] = True
        changed = True
    if changed:
        request({"cmd": "saveEpgMapping", "epgMapping": channels})
    print(f"Configured XMLTV for {len(channels)} channels", flush=True)


if __name__ == "__main__":
    main()
