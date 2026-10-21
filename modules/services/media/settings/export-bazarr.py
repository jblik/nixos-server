import json
import pathlib
import sqlite3
import sys


directory = pathlib.Path("/var/lib/bazarr")
database = sqlite3.connect((directory / "db/bazarr.db").as_uri() + "?mode=ro", uri=True)
database.row_factory = sqlite3.Row
database.execute("BEGIN")
tables = {}
for table in (
    "table_languages_profiles",
    "table_settings_languages",
    "table_settings_notifier",
):
    tables[table] = [dict(row) for row in database.execute(f'SELECT * FROM "{table}"')]
json.dump(
    {
        "config_yaml": (directory / "config/config.yaml").read_text(),
        "tables": tables,
    },
    sys.stdout,
)
database.close()
