import argparse
import json
import pathlib
import subprocess
import tempfile
import uuid

parser = argparse.ArgumentParser()
parser.add_argument("--write", action="store_true")
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parents[4]
keys = {
    "plexclientidentifier", "rijndaelpassphrase", "hmacpassphrase", "rijndaelsalt", "hmacsalt"
}
snapshot = json.loads((root / "modules/services/media/sonarr-settings.json").read_text())
references = {
    row["Key"]: row["Value"]["$secret"]
    for row in snapshot["tables"]["Config"] if row["Key"] in keys
}
if set(references) != keys:
    raise SystemExit("Expected Sonarr internal keys were not found; no changes made")
print("Internal Sonarr values: " + ", ".join(sorted(references)))
if not args.write:
    print("Preview only. Use --write to rotate the encrypted declaration; rebuild separately.")
    raise SystemExit(0)

try:
    secret_file = "secrets/media-sonarr.yaml"
    decrypted = subprocess.run(
        ["sops", "--decrypt", "--output-type", "json", secret_file],
        cwd=root, capture_output=True, check=True,
    )
    payload = json.loads(decrypted.stdout)
    values = json.loads(payload["settings"])
    for reference in references.values():
        values[reference] = str(uuid.uuid4())
    payload["settings"] = json.dumps(values)
    encrypted = subprocess.run(
        ["sops", "--encrypt", "--input-type", "json", "--output-type", "yaml",
         "--filename-override", secret_file, "/dev/stdin"],
        cwd=root, input=json.dumps(payload).encode(), capture_output=True, check=True,
    )
    with tempfile.NamedTemporaryFile(dir=root / "secrets", suffix=".yaml", delete=False) as temporary:
        temporary.write(encrypted.stdout)
        temporary_path = pathlib.Path(temporary.name)
    temporary_path.replace(root / secret_file)
except Exception as error:
    raise SystemExit(f"Encrypted rotation failed ({type(error).__name__}); secret values omitted") from None
print("Encrypted declaration rotated. Current live settings are unchanged until a rebuild.")
