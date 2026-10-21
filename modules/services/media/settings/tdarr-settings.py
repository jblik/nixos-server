import argparse
import datetime
import json
import os
import pathlib
import sqlite3
import sys
import tempfile


def resolve(value, secrets):
    if isinstance(value, dict):
        if set(value) == {"$secret"}:
            return secrets[value["$secret"]]
        return {key: resolve(item, secrets) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve(item, secrets) for item in value]
    return value


def records(connection, table, ignored):
    if table == "sso_provider_configs":
        return [dict(row) for row in connection.execute(f'SELECT * FROM "{table}" ORDER BY provider')]
    result = []
    for row in connection.execute(f'SELECT id,json_data FROM "{table}" ORDER BY id'):
        document = json.loads(row["json_data"])
        for field in ignored:
            document.pop(field, None)
        result.append({"id": row["id"], "json_data": document})
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("snapshot", type=pathlib.Path)
    parser.add_argument("secrets", type=pathlib.Path)
    parser.add_argument("directory", type=pathlib.Path)
    parser.add_argument("version")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    snapshot = resolve(json.loads(args.snapshot.read_text()), json.loads(args.secrets.read_text()))
    if snapshot["version"] != args.version:
        raise ValueError("Tdarr version changed; recapture settings before upgrading")
    database = args.directory / "server/server/Tdarr/DB2/SQL/database.db"
    fresh = not database.exists()
    if args.check and fresh:
        print("Settings differ: database does not exist")
        return 1
    temporary = None
    connection = None
    try:
        path = database
        if fresh:
            database.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=database.parent, prefix=".declarative-", delete=False) as output:
                temporary = pathlib.Path(output.name)
                path = temporary
        elif not args.check:
            database.chmod(0o600)
        connection = sqlite3.connect(path.as_uri() + ("?mode=ro" if args.check else "?mode=rwc"), uri=True)
        connection.row_factory = sqlite3.Row
        if fresh:
            order = {"TABLE": 0, "INDEX": 1, "TRIGGER": 2}
            for statement in sorted(snapshot["schema"], key=lambda sql: order[sql.split()[1]]):
                connection.execute(statement)
            connection.commit()
        for table, columns in snapshot["tableColumns"].items():
            if [dict(row) for row in connection.execute(f'PRAGMA table_info("{table}")')] != columns:
                raise ValueError("Tdarr settings schema changed; recapture settings before upgrading")
        changes = [
            table for table, expected in snapshot["tables"].items()
            if records(connection, table, snapshot["ignoredFields"].get(table, [])) != expected
        ]
        files = {
            name: value for name, value in snapshot["configs"].items()
            if not name.startswith("nodes/") or args.check
        }
        changed_files = [
            name for name, value in files.items()
            if not (args.directory / name).exists() or json.loads((args.directory / name).read_text()) != value
        ]
        if args.check:
            print("Settings match" if not changes and not changed_files else "Settings differ: " + ", ".join(changes + changed_files))
            return int(bool(changes or changed_files))
        if not fresh and (changes or changed_files):
            timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
            backup = args.directory / "server/declarative-backups" / timestamp
            backup.mkdir(mode=0o700, parents=True)
            with sqlite3.connect(backup / "database.db") as target:
                connection.backup(target)
            for name in changed_files:
                source = args.directory / name
                if source.exists():
                    target = backup / name
                    target.parent.mkdir(parents=True, mode=0o700)
                    target.write_bytes(source.read_bytes())
        with connection:
            for table in changes:
                expected = snapshot["tables"][table]
                if table == "sso_provider_configs":
                    connection.execute(f'DELETE FROM "{table}"')
                    for row in expected:
                        connection.execute(
                            f'INSERT INTO "{table}" (provider,enabled,credentials_json) VALUES (?,?,?)',
                            [row["provider"], row["enabled"], row["credentials_json"]],
                        )
                    continue
                current = {
                    row["id"]: json.loads(row["json_data"])
                    for row in connection.execute(f'SELECT id,json_data FROM "{table}"')
                }
                desired = {row["id"] for row in expected}
                for identifier in current.keys() - desired:
                    connection.execute(f'DELETE FROM "{table}" WHERE id=?', [identifier])
                for row in expected:
                    actual = {
                        field: value for field, value in current.get(row["id"], {}).items()
                        if field not in snapshot["ignoredFields"].get(table, [])
                    }
                    if row["id"] in current and actual == row["json_data"]:
                        continue
                    retained = {
                        field: value for field, value in current.get(row["id"], {}).items()
                        if field in snapshot["ignoredFields"].get(table, [])
                    }
                    document = json.dumps({**retained, **row["json_data"]})
                    connection.execute(
                        f'INSERT INTO "{table}" (id,timestamp,json_data) VALUES (?,0,?) '
                        'ON CONFLICT(id) DO UPDATE SET json_data=excluded.json_data',
                        [row["id"], document],
                    )
        for name in changed_files:
            target = args.directory / name
            target.parent.mkdir(parents=True, exist_ok=True)
            with tempfile.NamedTemporaryFile(dir=target.parent, prefix=".declarative-", mode="w", delete=False) as output:
                json.dump(files[name], output, indent=2)
                output.write("\n")
                generated = pathlib.Path(output.name)
            generated.replace(target)
        connection.close()
        connection = None
        if fresh:
            temporary.replace(database)
        print("Tdarr settings restored" if changes or changed_files else "Tdarr settings match")
        return 0
    finally:
        if connection is not None:
            connection.close()
        if temporary is not None and temporary.exists():
            temporary.unlink()


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"Tdarr settings reconciliation failed ({type(error).__name__}); no values logged", file=sys.stderr)
        sys.exit(1)
