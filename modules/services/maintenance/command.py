import os
from pathlib import Path
import sys


def main():
    state = Path(os.environ["MAINTENANCE_STATE"])
    os.environ["MAINTENANCE_ACTIVE"] = (
        "true" if os.environ["MAINTENANCE_ENABLED"] == "true"
        and state.exists() and state.read_text().strip() == "true" else "false"
    )
    command = sys.argv[1]
    os.execv(command, [command])


if __name__ == "__main__":
    main()
