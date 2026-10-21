import json
import pathlib
import re
import subprocess

root = pathlib.Path(__file__).resolve().parents[4]
media = root / "modules/services/media"
result = subprocess.run(
    [
        "ssh", "nixos-server",
        "/nix/store/3gzjs8czrk47y7cpmr44jc568vqpb2p5-python3-3.13.15/bin/python3", "-",
    ],
    input=(media / "settings/export-maintainerr.py").read_bytes(),
    capture_output=True,
    check=True,
)
snapshot = json.loads(result.stdout)
secrets = {}
for table, spec in snapshot["tables"].items():
    for row in spec["rows"]:
        identity = "-".join(str(row[column]) for column in spec["key"])
        for column, value in list(row.items()):
            if value is not None and re.search(
                "pass|token|secret|api.?key|client.?id|options|url|hostname", column, re.I
            ):
                name = f"{table}-{identity}-{column}"
                secrets[name] = value
                row[column] = {"__sops": name}
encrypted = subprocess.run(
    [
        "sops", "--encrypt", "--filename-override", "secrets/media-maintainerr.yaml",
        "--input-type", "json", "--output-type", "yaml", "/dev/stdin",
    ],
    input=json.dumps({"settings": json.dumps(secrets)}).encode(),
    capture_output=True,
    check=True,
    cwd=root,
)
(root / "secrets/media-maintainerr.yaml").write_bytes(encrypted.stdout)
(media / "maintainerr-settings.json").write_text(json.dumps(snapshot, indent=2) + "\n")
print("Captured Maintainerr settings; credentials encrypted with SOPS.")
