import argparse
import datetime
import json
import os
import pathlib
import sqlite3
import sys


def quote(name):
    return '"' + name.replace('"', '""') + '"'


def resolve(value, secrets):
    if isinstance(value, dict):
        if set(value) == {"__sops"}:
            return secrets[value["__sops"]]
        return {key: resolve(item, secrets) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve(item, secrets) for item in value]
    return value


def rows(connection, table, columns, where=None):
    condition = f" WHERE {where}" if where else ""
    return [dict(row) for row in connection.execute(
        f"SELECT {', '.join(map(quote, columns))} FROM {quote(table)}{condition}"
    )]


def identity(row, keys):
    return tuple(row[key] for key in keys)


def difference(connection, snapshot):
    changes = {}
    for table, spec in snapshot["tables"].items():
        desired = {identity(row, spec["key"]): row for row in spec["rows"]}
        actual = {identity(row, spec["key"]): row for row in rows(
            connection, table, spec["columns"], spec.get("where")
        )}
        if not spec.get("prune", True):
            actual = {key: row for key, row in actual.items() if key in desired}
        if len(desired) != len(spec["rows"]):
            raise ValueError(f"Duplicate declared keys in {table}")
        if desired != actual:
            changes[table] = {
                "upsert": [row for key, row in desired.items() if actual.get(key) != row],
                "delete": [row for key, row in actual.items() if key not in desired],
            }
    return changes


def verify_migrations(connection, snapshot):
    for table, expected in snapshot["migrations"].items():
        actual = [dict(row) for row in connection.execute(f"SELECT * FROM {quote(table)}")]
        canonical = lambda values: sorted(json.dumps(row, sort_keys=True) for row in values)
        if canonical(actual) != canonical(expected):
            raise ValueError(f"Database migrations changed in {table}; recapture settings before upgrading")


def verify_deletions(connection, snapshot, changes):
    tables = [row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table'")]
    for child in tables:
        foreign_keys = {}
        for foreign_key in connection.execute(f"PRAGMA foreign_key_list({quote(child)})"):
            foreign_keys.setdefault(foreign_key[0], []).append(foreign_key)
        for group in foreign_keys.values():
            parent = group[0][2]
            for removed in changes.get(parent, {}).get("delete", []):
                parent_keys = snapshot["tables"][parent]["key"]
                referenced = [foreign_key[4] or parent_keys[index] for index, foreign_key in enumerate(group)]
                if not all(column in removed for column in referenced):
                    raise ValueError(f"Cannot verify references from {child} to {parent}")
                condition = " AND ".join(f"{quote(foreign_key[3])} = ?" for foreign_key in group)
                matches = connection.execute(
                    f"SELECT * FROM {quote(child)} WHERE {condition}",
                    [removed[column] for column in referenced],
                )
                for match in matches:
                    spec = snapshot["tables"].get(child)
                    allowed = changes.get(child, {}).get("delete", [])
                    if not spec or identity(match, spec["key"]) not in {
                        identity(row, spec["key"]) for row in allowed
                    }:
                        raise ValueError(f"Removing a setting in {parent} would affect retained rows in {child}")


def upsert(connection, table, row, keys, insert_defaults=None):
    inserted = {**(insert_defaults or {}), **row}
    columns = list(inserted)
    values = [inserted[column] for column in columns]
    updates = [column for column in row if column not in keys]
    conflict = "DO UPDATE SET " + ", ".join(
        f"{quote(column)} = excluded.{quote(column)}" for column in updates
    ) if updates else "DO NOTHING"
    connection.execute(
        f"INSERT INTO {quote(table)} ({', '.join(map(quote, columns))}) "
        f"VALUES ({', '.join('?' for _ in columns)}) "
        f"ON CONFLICT ({', '.join(map(quote, keys))}) {conflict}", values,
    )


def backup(database):
    directory = database.parent / "declarative-backups"
    directory.mkdir(mode=0o700, exist_ok=True)
    os.chmod(directory, 0o700)
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    target = directory / f"{database.name}.{timestamp}"
    descriptor = os.open(target, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(descriptor)
    with sqlite3.connect(database.as_uri() + "?mode=ro", uri=True) as source:
        with sqlite3.connect(target) as destination:
            source.backup(destination)


def reconcile(snapshot, database, check=False):
    existed = database.exists()
    if check and not existed:
        print("Settings differ: database does not exist")
        return 1
    if not check:
        database.parent.mkdir(parents=True, exist_ok=True)
    uri = database.as_uri() + ("?mode=ro" if check else "?mode=rwc")
    connection = sqlite3.connect(uri, uri=True)
    connection.row_factory = sqlite3.Row
    connection.execute("PRAGMA foreign_keys=ON")
    try:
        if not check:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("PRAGMA defer_foreign_keys=ON")
        if not existed:
            for statement in snapshot["schema"]:
                connection.execute(statement)
            for table, entries in snapshot["migrations"].items():
                for row in entries:
                    upsert(connection, table, row, [next(iter(row))])
        verify_migrations(connection, snapshot)
        changes = difference(connection, snapshot)
        if check:
            print("Settings match" if not changes else "Settings differ: " + ", ".join(changes))
            return int(bool(changes))
        if existed and changes:
            verify_deletions(connection, snapshot, changes)
            backup(database)
        for table, change in changes.items():
            keys = snapshot["tables"][table]["key"]
            for row in change["upsert"]:
                upsert(connection, table, row, keys, snapshot["tables"][table].get("insert_defaults"))
        for table, change in reversed(list(changes.items())):
            keys = snapshot["tables"][table]["key"]
            condition = " AND ".join(f"{quote(key)} = ?" for key in keys)
            for row in change["delete"]:
                connection.execute(f"DELETE FROM {quote(table)} WHERE {condition}", identity(row, keys))
        if connection.execute("PRAGMA foreign_key_check").fetchone():
            raise ValueError("Settings would violate database foreign keys")
        if difference(connection, snapshot):
            raise ValueError("Settings did not converge")
        connection.commit()
        print("Settings match" if not changes else "Settings restored: " + ", ".join(changes))
        return 0
    except Exception:
        connection.rollback()
        raise
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("snapshot", type=pathlib.Path)
    parser.add_argument("secrets", type=pathlib.Path)
    parser.add_argument("database", type=pathlib.Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    snapshot = resolve(json.loads(args.snapshot.read_text()), json.loads(args.secrets.read_text()))
    return reconcile(snapshot, args.database.resolve(), args.check)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, sqlite3.Error, KeyError, OSError) as error:
        print(f"Settings reconciliation failed ({type(error).__name__}); no values logged", file=sys.stderr)
        sys.exit(1)
