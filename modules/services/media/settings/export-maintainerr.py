import json
import sqlite3

connection = sqlite3.connect(
    "file:/var/lib/maintainerr/maintainerr.sqlite?mode=ro", uri=True
)
connection.row_factory = sqlite3.Row
tables = [
    "settings",
    "radarr_settings",
    "sonarr_settings",
    "sportarr_settings",
    "log_settings",
    "notification",
    "notification_rulegroup",
    "overlay_settings",
    "overlay_templates",
    "collection",
    "rule_group",
    "rules",
    "exclusion",
]
runtime = {
    "collection": {
        "addDate", "handledMediaAmount", "lastDurationInSeconds", "totalSizeBytes",
        "handledMediaSizeBytes",
    },
    "overlay_templates": {"createdAt", "updatedAt"},
}
connection.execute("BEGIN")
snapshot = {
    "schema": [
        row[0] for row in connection.execute(
            "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL "
            "AND name NOT LIKE 'sqlite_%' ORDER BY type DESC,name"
        )
    ],
    "migrations": {
        "migrations": [dict(row) for row in connection.execute("SELECT * FROM migrations ORDER BY id")]
    },
    "tables": {},
}
for table in tables:
    info = list(connection.execute(f'PRAGMA table_info("{table}")'))
    columns = [row[1] for row in info if row[1] not in runtime.get(table, set())]
    key = [row[1] for row in sorted(info, key=lambda row: row[5]) if row[5]]
    names = ",".join(f'"{column}"' for column in columns)
    order = ",".join(f'"{column}"' for column in key)
    snapshot["tables"][table] = {
        "key": key,
        "columns": columns,
        "rows": [dict(row) for row in connection.execute(f'SELECT {names} FROM "{table}" ORDER BY {order}')],
    }
print(json.dumps(snapshot))
