# Media settings handoff — 2026-10-21

User requested this handoff before terminating the session. The overall task is
nearly implemented but **not yet finished**: final Tdarr comparisons and complete
host checks remain. Nothing has been deployed, pushed, or rotated on the server.

## User requirements and decisions

- All existing *arr and qBittorrent settings should live in code and reproduce
  current settings on rebuild, with comparisons against live settings/exports.
- Each application gets its own Nix file, replacing the shared `arr.nix`.
- User explicitly requested subworkers; delegation is authorized for this task.
- Authoritative replacement of settings is approved, with private backups first;
  preserve media libraries, history, downloads and runtime counters/state.
- Never push. Use frequent conventional one-line `jj commit` messages. Do not
  amend, rebase, abandon or otherwise rewrite history without explicit permission.
- User explicitly authorized committing **SOPS-encrypted** files as an exception
  to AGENTS' prohibition on committing secrets. Plaintext is forbidden in Git.
- User rejected broad root/Python sudoers permissions. Use specific reviewable
  export commands when protected settings are needed. SSH works as `jblik` at
  `nixos-server`, but `sudo -n` needs a password. No sudoers rule was installed.
- Maintainerr must have an **empty configuration placeholder and instructions**.
  `maintainerr-settings.json` is `{}`; restoration and secret declaration are off
  until populated. Its existing live data has not been erased.
- Cleanuparr **login/auth migration is deliberately pending**. Do not capture its
  users.db, JWT/DataProtection or login TOTP/OIDC/Plex auth material. Its normal
  integration credentials and cleanup settings are captured and encrypted.
- Pin numbered image versions, not `latest` or digest-only references. Verified
  registry version tags resolve to the exact user-supplied running hashes:
  - Cleanuparr `2.10.8`: `sha256:ec444338a67e429a20f6eef938e1ed771ce357ed4831765026096061a09bbbb7`
  - Pulsarr `0.19.7`: `sha256:3032ba2bd4ed26e06ce812c896a599febcd8843f64a31b1d9d63c99fb46c130b`
  - Maintainerr `3.29.0`: `sha256:7487d374290e59add65407ec295629e489f9057dbf18e2a9dff70d6201ffb6f9`
- Document retaining UI changes **including secret rotation**, SOPS entries and
  copies in consumers. This is implemented in `modules/services/media/README.md`.

## Important: confirmed local secret exposure

During initial Sonarr capture, five internal values briefly entered a public
working file. A concurrent jj snapshot persisted them in **local history**:

- Snapshot commit: `5e8673e`
- Git blob: `2180500335e3d0eeb57a4d2138c6de1ee59401af`
- Affected names: `plexclientidentifier`, `rijndaelpassphrase`,
  `hmacpassphrase`, `rijndaelsalt`, `hmacsalt`.
- Values were never printed, sent to chat, or pushed. No Sonarr API/provider
  credentials were found in that exposed public snapshot.
- Current files and named implementation commits encrypt these values. The old
  local snapshot still exists. **Do not claim history is clean.**
- User was promptly informed of the precise names and local-history scope.
- Exact SOPS references are `Config/2/Value` through `Config/6/Value` inside the
  JSON-string `settings` entry of `secrets/media-sonarr.yaml`.
- `settings/rotate-sonarr-crypto.py` is a tested preview-first boilerplate. Default
  previews names only; `--write` generates UUID4 replacements in SOPS, preserving
  other entries, without applying to live services. It has NOT been run on the
  actual declaration. Plex client identity rotation can require Plex relinking.
- No permission has been given for history rewriting/purging or live rotation.
  Respect the user's exact-current-settings requirement until rotation is chosen.

## Completed application work and comparisons

All paths below are relative to `modules/services/media/` unless stated otherwise.

| Application | Implementation and evidence |
| --- | --- |
| qBittorrent | `qbittorrent.nix`, native files in `qbittorrent/`, SOPS password verifier. All 57 preferences, 3 categories, watched folders, RSS and encrypted password verified equal to live. Runtime torrent/transfer state excluded. Private backups before replacement. |
| Sonarr | `sonarr.nix`, `sonarr-settings.json`, `secrets/media-sonarr.yaml`. All 19 settings tables + config.xml match direct live DB/XML, including secrets. User's backup also exactly matches. |
| Radarr | `radarr.nix`, `radarr-settings.json`, `secrets/media-radarr.yaml`. 19 settings tables + XML equal supplied backup and latest live backup (2026-10-21 06:00:23Z). Current live APIs matched 1,022 public scalar settings across 17 endpoints and all 17 XML fields. Eight provider credentials are masked by API; those and Users/internal crypto are backup-verified, not independently readable live. |
| Bazarr | `bazarr.nix`, `settings/bazarr.json`, `settings/bazarr-database.json`, SOPS. Full config, 3 profiles, 187 language rows and 129 notifier rows captured. Private archive equality; current live profile/language/notifier APIs match. Fresh bootstrap verified. |
| Jackett | `jackett.nix`, `settings/jackett.json`, SOPS. Full ServerConfig + 8 active indexers match exported files; transient lasterror/.bak excluded. Admin API denied authentication, so no additional live API check. |
| FlareSolverr | `flaresolverr.nix`; stateless runtime, actual PORT=8191 matches declaration. |
| Pulsarr | `pulsarr.nix`, `settings/pulsarr.json`, SOPS. 12 settings tables. Actual generic restorer --check against deployed live DB reports Settings match, including decrypted secrets and strict schema/migrations. Newly synced users and builtin genres retained; captured settings authoritative. |
| Cleanuparr | `cleanuparr.nix`, `cleanuparr-settings.json`, SOPS. 28 settings tables and 10 encrypted integration values verified equal live. Single SOPS JSON string handles arbitrary password quotes/backslashes safely. Auth migration excluded by explicit user request. |
| Maintainerr | `maintainerr.nix`, empty `maintainerr-settings.json`. No current credential file. `settings/capture-maintainerr.py` + `export-maintainerr.py` and docs explain populating it later. |
| Tdarr | `tdarr.nix`, `tdarr-settings.json`, `settings/tdarr-settings.py`, SOPS captured and implementation written; final checks pending below. |

Bazarr's UI backup currently fails due to its old `/config` backup destination.
That value was intentionally preserved for exact parity. Docs explain changing
`files["config/config.yaml"].backup.folder` in `settings/bazarr.json` to
`/var/lib/bazarr/backup` deliberately. Do not silently change it during parity work.

## Tdarr: precise remaining work

Worker reports implementation/tests completed, committing the verified unit now.
Check `jj status` and recent log in the next session to see final commit state.

Final worker update received during handoff: rotation example committed as
`8f8dcc96`, verified Tdarr implementation as `c3f01869`. Working copy was empty
after the handoff commit. No unfinished implementation files need salvaging.

- Captured 9 settings tables, 2 libraries, 2 flows, 1 stable node
  `nixos-server-main`, 1 global document. Auth/API/vars/SSO/automations tables empty.
- 15 sensitive fields encrypted, including flow plugin API keys/webhook and
  server `authSecretKey`/`seededApiKey`.
- JSON-record database has lowercase table names. Initial exporter mistakenly
  selected zero rows; it was corrected and the user reran it successfully.
  The CURRENT `~/tdarr-settings.json` on the server is the corrected full export.
- Exporter: `settings/export-tdarr.py`, uploaded at
  `/tmp/export-tdarr-settings.py`. It is read-only, fixed-path, no generic sudoers.
- Helper restores settings offline before server starts, preserving library scan/
  transcode counters and runtime statistics/history. Guards Tdarr version 2.91.01
  and captured schema. Private backups and atomic fresh database installation.
- Exported native node config has exactly one field, `pathTranslators`; this is
  wired through native module's node option. Worker verified that complete file.
- Worker passed: fresh schema/bootstrap integrity, exact --check/idempotence,
  runtime scan/transcode/statistics sentinel preservation, DB backup mode600,
  full Nix host-context evaluation and generated preStart version/path checks.
- STILL NEEDED: compare current live Tdarr settings API against the resolved
  declaration, and independently confirm import/export semantic equality.
- STILL NEEDED: test fresh-bootstrap failure/retry and sanitized errors for the
  Tdarr-specific helper (other helpers already tested for these failures).
- Finish full host checks and docs verification summary after those pass.

Live API comparison route: POST `http://127.0.0.1:8265/api/v2/cruddb` with JSON
`{"collection":"LibrarySettingsJSONDB","mode":"getAll","docID":"","obj":{}}`;
repeat for SettingsGlobalJSONDB, NodeJSONDB, FlowsJSONDB, VariablesJSONDB and
AutomationsJSONDB. Strip the snapshot's ignoredFields, match document `_id`,
compare against resolved snapshot json_data and print equality only. A previous
automatic approval review rejected UsersJSONDB/ApiKeysJSONDB read queries as
authentication-material access; do not retry those without resolving that block.
Those auth tables were confirmed empty by the user's specific privileged export.

## Shared restore helpers and verification

- `settings/arr-settings.py`: Sonarr/Radarr selected settings only, captured full
  schema and VersionInfo for fresh databases, private backups, preserved runtime,
  umask0077/mode600, atomic bootstrap, sanitized errors.
- `settings/sqlite-settings.py`: other SQLite apps, explicit managed columns,
  migration + full-schema checks, foreign-key safety, upsert without REPLACE,
  optional mixed-runtime preservation, private backups, recovery from failed empty
  initial database creation, --check uses read-only connections.
- `settings/files-settings.py`: JSON/YAML file configs; backups mode600/dir700,
  JSON-safe secret resolution and retired indexer files archived instead of lost.
- Fresh restore, drift correction, idempotence, runtime preservation, backup
  permissions, schema mismatch refusal and relevant privacy failures were tested
  for completed apps. A second worker reviewed startup/sandbox/dependency behavior.
- Full toplevel evaluation and `nix flake check --no-build` passed BEFORE the latest
  Tdarr edits. Need final checks on the final tree. Native Linux services were not
  actually built/run on this Mac. No production restart/deployment was attempted.
- Existing unrelated Nix warning: storage data disks have no parity configured.
- Current public-file scan compared 30 credential-like values in RAM and found no
  plaintext occurrences. Repeat after final Tdarr edits if useful. Do not confuse
  current-tree cleanliness with the confirmed historical Sonarr exposure.
- Avoid committing `__pycache__`/pyc. A generated file was moved outside the repo
  into `/private/tmp/nixos-media-generated-*`; use PYTHONDONTWRITEBYTECODE=1 for
  import-based verification.

## Resume commands

```sh
jj status
jj log -r 'ancestors(@, 12)'
nix fmt
nix eval --raw .#nixosConfigurations.nixos-server.config.system.build.toplevel.drvPath
nix flake check --no-build --all-systems
```

Use tools with sandbox escalation where needed: Nix writes
`/Users/jblik/.cache/nix/`, and jj writes `.git/objects`; default sandbox may deny
these despite workspace files being writable. SSH also needs tool escalation.
Do not redeploy or push as part of resuming verification.

## Source exports and important files

- User-provided local folders:
  `/Users/jblik/Downloads/sonarr_backup_v4-2/` and
  `/Users/jblik/Downloads/radarr_backup_v6-2/`.
- Server user's home: `bazarr-settings.tar.gz`, `jackett-settings.tar.gz`,
  `tdarr-settings.json` contain private exports. Retrieve without printing values.
  Bazarr archive contains a consistent SQLite backup made with SQLite's .backup,
  not a raw running DB copy; includes `config.yaml` and `bazarr.db`.
- Some private working archives are mode600 under `/private/tmp`; do not commit
  or print them. No broad sudo access exists.
- Server existing tools:
  `/nix/store/3gzjs8czrk47y7cpmr44jc568vqpb2p5-python3-3.13.15/bin/python3`,
  `/nix/store/iy2zkfn4l0w24xabv6ryi0vh7bpjvqm6-sqlite-3.53.3-bin/bin/sqlite3`.
- Root README links to `modules/services/media/README.md`, which contains UI
  retention/rotation workflow, capture methods, consumers, Maintainerr population,
  Cleanuparr login setup, known exposure details, and rotation example commands.
- Last parent integration commit at handoff: `dde2e9e0` (individual modules,
  numbered version pins, empty Maintainerr and requested docs). Other relevant
  recent commits include `8cce2cc4` Bazarr/Jackett, `88362012` Cleanuparr escaping,
  `50780180` arr security, `cc328cf1` generic schema/bootstrap fixes. Consult jj
  for worker commits arriving during handoff; don't rewrite any of them.
