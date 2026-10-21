import argparse
import datetime
import json
import os
import pathlib
import sqlite3
import tempfile
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument("snapshot", type=pathlib.Path)
parser.add_argument("secrets", type=pathlib.Path)
parser.add_argument("database", type=pathlib.Path)
parser.add_argument("xml", type=pathlib.Path)
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
os.umask(0o077)
bootstrap_path = None


def run():
    global bootstrap_path
    secrets = json.loads(args.secrets.read_text())


    def resolve(value):
        if isinstance(value, dict):
            if set(value) == {"$secret"}:
                return secrets[value["$secret"]]
            return {key: resolve(item) for key, item in value.items()}
        if isinstance(value, list):
            return [resolve(item) for item in value]
        return value


    snapshot = resolve(json.loads(args.snapshot.read_text()))
    fresh = not args.database.exists()
    if args.check and fresh:
        raise SystemExit("Settings differ: database does not exist")
    database = args.database
    if fresh:
        with tempfile.NamedTemporaryFile(prefix=args.database.name + ".", dir=args.database.parent, delete=False) as temporary:
            database = pathlib.Path(temporary.name)
        bootstrap_path = database
    elif not args.check:
        args.database.chmod(0o600)
    connection = sqlite3.connect(database)
    connection.row_factory = sqlite3.Row
    if fresh:
        with connection:
            for statement in snapshot["schema"]:
                if not statement.startswith("CREATE TABLE sqlite_"):
                    connection.execute(statement)
            rows = snapshot["version"]
            columns = list(rows[0])
            connection.executemany(
                'INSERT INTO VersionInfo (' + ','.join('"' + column + '"' for column in columns)
                + ') VALUES (' + ','.join('?' for column in columns) + ')',
                [[row[column] for column in columns] for row in rows],
            )

    versions = [dict(row) for row in connection.execute("SELECT * FROM VersionInfo")]
    if versions != snapshot["version"]:
        raise SystemExit("Database migration version differs; recapture settings before applying")
    expected_schema = sqlite3.connect(":memory:")
    for statement in snapshot["schema"]:
        if not statement.startswith("CREATE TABLE sqlite_"):
            expected_schema.execute(statement)
    for table in snapshot["tables"]:
        if [tuple(row) for row in connection.execute(f'PRAGMA table_info("{table}")')] != list(
            expected_schema.execute(f'PRAGMA table_info("{table}")')
        ):
            raise SystemExit(f"Settings schema differs: {table}")

    differences = [
        table for table, rows in snapshot["tables"].items()
        if [dict(row) for row in connection.execute(f'SELECT * FROM "{table}" ORDER BY Id')] != rows
    ]
    xml_differs = not args.xml.exists() or {
        element.tag: element.text for element in ET.parse(args.xml).getroot()
    } != snapshot["xml"]
    if args.check:
        if differences or xml_differs:
            raise SystemExit("Settings differ: " + ", ".join(differences + (["config.xml"] if xml_differs else [])))
        print("Settings exactly match: " + str(len(snapshot["tables"])) + " tables and config.xml")
        raise SystemExit(0)

    if differences or xml_differs:
        if not fresh:
            backup = args.database.parent / "declarative-backups" / datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
            backup.mkdir(parents=True, mode=0o700)
            with sqlite3.connect(backup / args.database.name) as target:
                connection.backup(target)
            if args.xml.exists():
                (backup / "config.xml").write_bytes(args.xml.read_bytes())
                (backup / "config.xml").chmod(0o600)
        with connection:
            for table in differences:
                connection.execute(f'DELETE FROM "{table}"')
                for row in snapshot["tables"][table]:
                    columns = list(row)
                    connection.execute(
                        f'INSERT INTO "{table}" (' + ','.join('"' + column + '"' for column in columns)
                        + ') VALUES (' + ','.join('?' for column in columns) + ')',
                        [row[column] for column in columns],
                    )
        if xml_differs:
            root = ET.Element("Config")
            for key, value in snapshot["xml"].items():
                ET.SubElement(root, key).text = value
            temporary = args.xml.with_suffix(".xml.declarative")
            ET.ElementTree(root).write(temporary, encoding="utf-8", xml_declaration=True)
            temporary.chmod(0o600)
            temporary.replace(args.xml)
    connection.close()
    if fresh:
        database.replace(args.database)


try:
    run()
except Exception as error:
    raise SystemExit(f"Declarative arr settings failed ({type(error).__name__}); secret values omitted") from None
finally:
    if bootstrap_path is not None and bootstrap_path.exists():
        bootstrap_path.unlink()
