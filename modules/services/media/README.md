# Declarative media settings

Each application has its own Nix module, imported by `default.nix`. Public settings
are JSON or application-native configuration files beside the module. Credentials
are in the corresponding `secrets/media-<application>.yaml`, encrypted with SOPS.
Do not commit downloaded backups or plaintext exports.

On service startup, settings in code replace the managed application settings.
Differing existing settings are backed up before replacement. Application libraries,
download state and history remain runtime data; keep their existing storage backups.
UI changes to managed settings are temporary and are replaced at the next start.
Cleanuparr 2.10.8, Pulsarr 0.19.7 and Maintainerr 3.29.0 are pinned to numbered
container releases. Each version tag was checked against the running image hash.

The SQLite restorers create a fresh database from the captured schema, then insert
only settings and migration metadata. On an existing database they preserve runtime
tables and runtime columns. They refuse incompatible migration versions; recapture
settings when upgrading an application that changes its database schema.
The shared restorer refuses settings deletion that would affect retained runtime
records. Pulsarr retains newly discovered Plex users and built-in genres; settings
for captured users and custom genres are managed explicitly.

## Retaining UI changes, including secret rotation

Code is authoritative. A UI save changes the running application only; the next
service restart, reboot or deployment restores the declaration. To retain a UI
change:

1. Export the changed settings **before restarting or deploying**. Keep the export
   outside this repository with restricted permissions. For a small change to an
   existing value, you can instead mirror that value directly into its declaration.
2. Update the application's public snapshot and its SOPS file together. Preserve
   object IDs and references when adding or removing profiles, indexers, rules or
   integrations. Exclude runtime history, media records, counters and transient
   errors. Do not replace a public snapshot with an unredacted backup or raw export.
3. If a password, API key, cookie or token changed, capture its new value into SOPS
   and update every consumer listed below. Keep the public secret reference; only
   the encrypted value should change. When an API masks a password, obtain the
   real value from the private export or the credential provider rather than
   saving the mask. qBittorrent's verifier and its clients' plaintext password are
   different representations of the same credential.
4. Compare the resolved declaration with the export or live settings. The
   restorers' `--check` mode compares without applying; it needs the public snapshot,
   decrypted secret file and state path indicated in the application's Nix module.
   Use the service's Python environment (Bazarr additionally needs PyYAML), and run
   checks where those paths are readable. Do not copy decrypted credentials to Git
   or print them to the terminal. Schema or migration changes need a new schema
   capture as well; UI-only changes normally do not.
5. Run the Nix checks below, review the diff for plaintext credentials, then
   `jj commit -m 'feat: retain <application> settings changes'`. Commit the public
   snapshot and SOPS ciphertext in the same change. Deploy producer and consumer
   updates together using the root README's deployment command.
6. Verify service startup and integration connection tests after deployment.
   Verify that restarting retains the intended settings. For rotated credentials,
   check that the new credential works and revoke the previous credential at its
   issuing service when applicable. Existing configuration backups and local
   history can still contain older credentials; rotation does not erase them.

| Application | Capture method | Public declaration |
| --- | --- | --- |
| Sonarr | System → Backup → Backup Now; download ZIP | `sonarr-settings.json` |
| Radarr | System → Backup → Backup Now; download ZIP | `radarr-settings.json` |
| Bazarr | System → Backups → Backup Now; click filename, or `settings/export-bazarr.py` | `settings/bazarr.json`, `settings/bazarr-database.json` |
| Jackett | Private archive of `ServerConfig.json` and active `Indexers/*.json` under `/var/lib/jackett/.config/Jackett` | `settings/jackett.json` |
| qBittorrent | Private copies of its stopped-service config, categories, watched-folder and RSS files | `qbittorrent/` |
| Cleanuparr | `settings/export-cleanuparr.py public` and `secrets` modes; read-only SQLite capture | `cleanuparr-settings.json` |
| Pulsarr | Consistent SQLite settings-only capture from `/var/lib/pulsarr/db/pulsarr.db` | `settings/pulsarr.json` |
| Tdarr | `settings/export-tdarr.py`; run the specific exporter with sudo for protected settings | See `tdarr.nix` |
| Maintainerr | `settings/capture-maintainerr.py` from the Mac | `maintainerr-settings.json` |

Most exports need conversion into the existing public/SOPS format; they are not
automatic import commands. Maintainerr's capture script performs that conversion.
The Cleanuparr exporter deliberately stops on unfamiliar columns, new tables, or
newly populated previously empty settings tables: review/redact those fields before
extending its allowlist. If using an assistant to convert an export, provide its
private local file path instead of pasting its contents into chat.

Bazarr currently has an old `/config` backup destination, which fails under the
native service. It was preserved for settings parity. To fix it deliberately, set
`files["config/config.yaml"].backup.folder` in `settings/bazarr.json` to
`/var/lib/bazarr/backup`, check, commit and deploy. Its current capture was made
with SQLite's backup API to obtain a consistent database despite the UI failure.

| Rotated credential | Consumer copies to update in SOPS |
| --- | --- |
| qBittorrent WebUI password | Sonarr and Radarr download-client settings, Cleanuparr download client, Maintainerr if later configured |
| Sonarr/Radarr API key | Bazarr integration, Cleanuparr instances, Pulsarr instances, Maintainerr if later configured |
| Jackett API key | Sonarr/Radarr indexer settings |
| Indexer, subtitle provider, Plex or notification-service credential | Every configured integration using that provider; locate its public secret references in each snapshot |

To locate references without showing values, search public snapshots with `rg`.
Use `sops` to edit encrypted files; its editor is the place for plaintext. Keep the
new credentials out of shell arguments, commit messages, logs and issue text.

## Editing and secrets

Edit the public settings file and, when necessary, the encrypted credentials:

```sh
nix shell nixpkgs#sops -c sops secrets/media-sonarr.yaml
```

For most applications the YAML `settings` value is a JSON object encoded as a
string. Edit individual entries in that object and retain the other entries.
References in the public snapshot identify their exact keys. Sonarr/Radarr use
`{"$secret": "entry-name"}`; other SQLite snapshots use
`{"__sops": "entry-name"}`. Provider settings containing credentials may be
encrypted as a complete JSON string.

For example, this is the shape of an API-key entry inside the existing SOPS editor
document; merge it into the existing map rather than replacing the entire map:

```yaml
settings: |
  {
    "xml/ApiKey": "<replacement-api-key>"
  }
```

Rotate a service API key together with its copies in consumers' SOPS files
(Sonarr, Radarr, Bazarr, Cleanuparr, Pulsarr or Jackett as applicable).
The qBittorrent WebUI password verifier is the top-level
`qbittorrent-webui-password` entry in `secrets/media-qbittorrent.yaml`.
Its value must use qBittorrent's native password-verifier format, rather than a
plaintext password. Update download clients' plaintext passwords separately.

Before committing, run `nix fmt` and
`nix eval --raw .#nixosConfigurations.nixos-server.config.system.build.toplevel.drvPath`.
Commit locally and deploy using the root README's deployment command when ready.
The encrypted files are intentionally committed; plaintext credentials are not.

## Maintainerr: empty configuration

`maintainerr-settings.json` is deliberately `{}`. This disables configuration
restoration and declares no credentials. The service retains its existing data;
a fresh installation starts with Maintainerr's defaults.

To populate it later, configure Maintainerr once or migrate an existing instance,
then run this from the repository root on the Mac:

```sh
nix shell nixpkgs#sops -c python3 modules/services/media/settings/capture-maintainerr.py
```

The script reads only settings from the server, excludes library/history state,
writes `maintainerr-settings.json`, and streams sensitive fields directly into
`secrets/media-maintainerr.yaml` through SOPS. It does not change the server.
The SSH user needs read access to `/var/lib/maintainerr/maintainerr.sqlite`.
The exporter currently uses the server's installed Python store path; update that
path in `capture-maintainerr.py` if that interpreter has been garbage-collected.

Check the resulting diff, run the Nix checks above, commit the JSON and encrypted
YAML, then deploy. A nonempty snapshot enables restoration automatically. The
restorer verifies settings after applying them and creates a restricted database
backup before changing an existing configuration.

## Cleanuparr: login migration pending

Cleanuparr's integration and cleanup settings are managed. Its login database,
JWT signing key and DataProtection keys are deliberately not captured.
Existing login state is retained on the current server.

On a fresh installation, open Cleanuparr and complete its initial administrator
account setup. To also reproduce login state later, separately back up and encrypt
`/var/lib/cleanuparr/users.db`, `jwt-key.bin` and `DataProtection-Keys/` with the
service stopped or SQLite's backup API. Configure their restoration before service
startup, preserving their existing owner `99:100` and restricting access. Include
any enabled TOTP/OIDC/Plex authentication material in that migration. Do not rotate
the signing/encryption keys independently of their associated authentication data.

## Capture handling

During the initial Sonarr capture, internal crypto values entered a local
Jujutsu snapshot, commit `5e8673e`, in Git blob
`2180500335e3d0eeb57a4d2138c6de1ee59401af`. Their values were never printed or
pushed. The current settings files and named implementation commits encrypt them
in `secrets/media-sonarr.yaml`, but that earlier local snapshot still contains
plaintext:

| Sonarr setting | Entry inside the SOPS `settings` JSON |
| --- | --- |
| `plexclientidentifier` | `Config/2/Value` |
| `rijndaelpassphrase` | `Config/3/Value` |
| `hmacpassphrase` | `Config/4/Value` |
| `rijndaelsalt` | `Config/5/Value` |
| `hmacsalt` | `Config/6/Value` |

The following entries belong inside the existing encrypted `settings` JSON map;
preserve all its other entries:

```json
{
  "Config/2/Value": "<replacement-plexclientidentifier>",
  "Config/3/Value": "<replacement-rijndaelpassphrase>",
  "Config/4/Value": "<replacement-hmacpassphrase>",
  "Config/5/Value": "<replacement-rijndaelsalt>",
  "Config/6/Value": "<replacement-hmacsalt>"
}
```

These internal encryption values may protect stored data; migrate that data with
the application before replacing the values. Rotation intentionally changes the
captured settings. The API key is the separate `xml/ApiKey` entry. No rotation or
history rewrite was performed automatically.

There is also a preview-first rotation example for these five internal values:

```sh
python3 modules/services/media/settings/rotate-sonarr-crypto.py
```

After reviewing the effect on Plex authorization and any encrypted application
data, explicitly add `--write` to update only their encrypted declarations:

```sh
nix shell nixpkgs#sops -c python3 modules/services/media/settings/rotate-sonarr-crypto.py --write
```

It preserves unrelated secrets, prints no values and does not change the running
service. Follow the checks, commit, deployment and connectivity verification in
the UI-change workflow above. Changing Plex's client identity may require relinking
its integration. History cleanup requires a separate explicit history-rewrite
instruction; it has not been performed.
