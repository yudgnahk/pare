# Phase 8 — Productivity & System Health

Productivity app caches, orphaned launch agents, and the Maintenance tab.

## Productivity caches — `ProductivityCachesRule`

`.safe` caches (confidence 0.92), skipped when the app is not installed:

- Slack: `Application Support/Slack/Cache`, `CachedData`, `Library/Caches/com.tinyspeck.slackmacgap`
- Zoom `us.zoom.xos`, Google Drive `com.google.drivefs.finderext`, Dropbox `com.dropbox.client2`
- Microsoft: Teams (`Application Support/Microsoft/Teams/Cache`, `teams`, `teams2`), OneDrive,
  Word, Excel, PowerPoint, Outlook under `Library/Caches`

`~/Documents/Zoom` (cloud recordings) is `.review`: the user may want to keep them.

## Orphaned launch agents — `OrphanedLaunchAgentsRule`

Reports `~/Library/LaunchAgents/*.plist` whose `Program` (or first `ProgramArguments`) binary no
longer exists. Category `.launchAgents`, `.advanced` (report-only), confidence 0.85.

- Report-only because the binary may have moved or live on an unmounted volume, and a user may have
  disabled the agent on purpose. `CleanupEngine` has no allow-marker for `LaunchAgents`.
- Skipped: plists under 30 days old, paths needing shell expansion (`$`, `~`), plists with no program.
- `/Library/LaunchAgents` and `/Library/LaunchDaemons` are out of scope (admin, more false positives).
- `AppUninstaller` removes an app's own agents during a Pare uninstall; this rule catches the rest.

## Maintenance tab

One-shot repair actions (`MaintenanceCatalog`), streamed into a per-card log. No sudo.

| Action | Command |
|---|---|
| Flush DNS cache | `dscacheutil -flushcache; killall -HUP mDNSResponder` |
| Restart Finder | `killall Finder` |
| Vacuum SQLite databases | Mail `Envelope Index` (every `V*`) and Safari `History.db` |
| Docker system prune | `docker system prune -f`, never `--volumes`; shown only while Docker runs |
| Docker build cache > 7 days / > 1 day | `docker builder prune -f --filter until=168h` / `until=24h` |

**Removed: Rebuild Launch Services.** `lsregister -kill -r …` dropped active VPN tunnels and forced a
Spotlight reindex.

### Vacuum safety

Per database, one `sqlite3 <path> -init /dev/null <sql>` per step: `PRAGMA quick_check` (must print
`ok`), `wal_checkpoint(TRUNCATE)`, `VACUUM`, `wal_checkpoint(TRUNCATE)`. The checkpoints stop a
WAL-mode database from keeping a database-sized `-wal` file.

- Skipped when the owning app runs, `quick_check` fails, the database is busy, or free space is
  below 2 × (database + WAL). One skipped database never stops the others.
- `-init /dev/null` keeps a user's `~/.sqliterc` from changing the parsed output.
- A checkpoint busy before `VACUUM` skips the database; busy after it logs a warning, never a ✓.
- Messages `chat.db` is never vacuumed: a system daemon keeps it open even when Messages is quit.
