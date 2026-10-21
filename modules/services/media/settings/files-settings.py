import argparse
import datetime
import json
import os
import pathlib
import shutil
import sys
import tempfile


def resolve(value, secrets):
    if isinstance(value, dict):
        if set(value) == {"__sops"}:
            return secrets[value["__sops"]]
        return {key: resolve(item, secrets) for key, item in value.items()}
    if isinstance(value, list):
        return [resolve(item, secrets) for item in value]
    return value


def read(path):
    text = path.read_text()
    if path.suffix in (".yaml", ".yml"):
        import yaml

        return yaml.safe_load(text)
    return json.loads(text)


def preserve(path, directory):
    backup = directory / "declarative-backups"
    backup.mkdir(mode=0o700, exist_ok=True)
    os.chmod(backup, 0o700)
    timestamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    destination = backup / f"{path.name}.{timestamp}"
    descriptor = os.open(destination, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    with os.fdopen(descriptor, "wb") as output, path.open("rb") as source:
        shutil.copyfileobj(source, output)
    return destination


def reconcile(snapshot, directory, check=False):
    changed = []
    for name, value in snapshot["files"].items():
        target = directory / name
        if target.exists():
            actual = read(target)
            ignored = snapshot.get("ignored_field_ids", {}).get(name, [])
            if ignored:
                actual = [item for item in actual if item.get("id") not in ignored]
            if actual == value:
                continue
        changed.append(name)
        if check:
            continue
        target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        if target.exists():
            preserve(target, directory)
        descriptor, temporary = tempfile.mkstemp(dir=target.parent, prefix=".declarative-")
        with os.fdopen(descriptor, "w") as output:
            json.dump(value, output, indent=2, ensure_ascii=False)
            output.write("\n")
        os.replace(temporary, target)
    for pattern in snapshot.get("managed_globs", []):
        for target in sorted(directory.glob(pattern)):
            name = str(target.relative_to(directory))
            if name in snapshot["files"]:
                continue
            changed.append(name)
            if not check:
                destination = preserve(target, directory)
                os.replace(target, destination)
                os.chmod(destination, 0o600)
    print("Settings match" if not changed else "Settings differ" if check else "Settings restored")
    return int(check and bool(changed))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("snapshot", type=pathlib.Path)
    parser.add_argument("secrets", type=pathlib.Path)
    parser.add_argument("directory", type=pathlib.Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    snapshot = resolve(json.loads(args.snapshot.read_text()), json.loads(args.secrets.read_text()))
    return reconcile(snapshot, args.directory, args.check)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as error:
        print(f"Settings reconciliation failed ({type(error).__name__}); no values logged", file=sys.stderr)
        sys.exit(1)
