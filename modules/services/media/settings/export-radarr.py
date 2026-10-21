import json
import sqlite3
import xml.etree.ElementTree as ET

path = "/var/lib/radarr/.config/Radarr"
connection = sqlite3.connect(f"file:{path}/radarr.db?mode=ro", uri=True)
connection.row_factory = sqlite3.Row
names = [
    "Config", "RootFolders", "NamingConfig", "Metadata", "DownloadClients",
    "RemotePathMappings", "DelayProfiles", "Users", "Tags", "QualityDefinitions",
    "Notifications", "QualityProfiles", "Indexers", "CustomFilters", "CustomFormats",
    "ReleaseProfiles", "ImportLists", "AutoTagging", "ImportListExclusions",
]
existing = {row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")}
connection.execute("BEGIN")
print(json.dumps({
    "schema": [row[0] for row in connection.execute(
        "SELECT sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type DESC,name"
    )],
    "version": [dict(row) for row in connection.execute("SELECT * FROM VersionInfo")],
    "tables": {
        name: [dict(row) for row in connection.execute(f'SELECT * FROM "{name}" ORDER BY Id')]
        for name in names if name in existing
    },
    "xml": {element.tag: element.text for element in ET.parse(f"{path}/config.xml").getroot()},
}))
