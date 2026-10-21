import json
import pathlib
import sqlite3

root = pathlib.Path("/var/lib/tdarr")
connection = sqlite3.connect(
    f"file:{root}/server/server/Tdarr/DB2/SQL/database.db?mode=ro", uri=True
)
connection.row_factory = sqlite3.Row
connection.execute("BEGIN")
names = {
    "LibrarySettingsJSONDB", "SettingsGlobalJSONDB", "NodeJSONDB", "FlowsJSONDB",
    "VariablesJSONDB", "UsersJSONDB", "ApiKeysJSONDB", "AutomationsJSONDB",
    "sso_provider_configs",
}
existing = {
    row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")
}
selected = sorted(name for name in existing if name.lower() in {item.lower() for item in names})
if not selected:
    raise SystemExit("No Tdarr settings tables matched; export stopped")
configs = [
    root / "server/configs/Tdarr_Server_Config.json",
    root / "nodes/main/configs/Tdarr_Node_Config.json",
]
print(json.dumps({
    "schema": [row[0] for row in connection.execute(
        "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type DESC,name"
    )],
    "tableColumns": {
        name: [dict(row) for row in connection.execute(f'PRAGMA table_info("{name}")')]
        for name in existing if not name.startswith("sqlite_")
    },
    "tables": {
        name: [dict(row) for row in connection.execute(f'SELECT * FROM "{name}"')]
        for name in selected
    },
    "configs": {str(path.relative_to(root)): json.loads(path.read_text()) for path in configs},
}))
