from datetime import datetime
import json
import os
from pathlib import Path
import sys
from urllib.error import URLError
from urllib.request import ProxyHandler, build_opener

from maintenance import active


def main():
    task, command = sys.argv[1:]
    defaults = json.loads(Path(os.environ["MAINTENANCE_DEFAULTS"]).read_text())
    window = dict(defaults["Tasks"][task], enabled=True)
    if os.environ.get("MAINTENANCE_URL"):
        try:
            with build_opener(ProxyHandler({})).open(
                os.environ["MAINTENANCE_URL"], timeout=5
            ) as response:
                window = json.load(response)[task]
        except URLError:
            # Application startup can precede the dashboard's listener.
            pass
    os.environ["MAINTENANCE_ENABLED"] = str(window["enabled"]).lower()
    os.environ["MAINTENANCE_START"] = window["start"]
    os.environ["MAINTENANCE_END"] = window["end"]
    os.environ["MAINTENANCE_ACTIVE"] = str(
        active(window, datetime.now().time())
    ).lower()
    os.execv(command, [command])


if __name__ == "__main__":
    main()
