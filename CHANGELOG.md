# Changelog

All notable changes to Pare are documented here.

---

## [Unreleased]

These are open pull requests from 2026-10-07, pending review and merge; nothing below is on `master` yet.

### Safety
- Build, `dist` and `target` folders are reclaimed only when git ignores them and tracks nothing inside, checked again at cleanup time (#41).
- Go build and module caches are reported as a working set and never cleaned; Go trims them itself (#46).
- The Launch Services rebuild is gone, and orphaned launch agents are report-only (#47).
- Database maintenance vacuums SQLite safely: integrity check first, WAL truncated, enough free space required, apps that own the database must be quit (#48).
- OpenCode sessions, database and credentials, and Google identity caches, are never cleaned (#49).
- Cleanup skips anything another process has open, and says so when the open-file check is unavailable (#50).
- Caches that grow straight back after cleaning are no longer proposed for Quick Clean (#63).
- PareCore resources load without crashing when the bundle is misplaced; one locked database no longer stops the rest of maintenance; dev builds keep Full Disk Access across rebuilds (#42).

### Scan coverage
- Package-manager and toolchain trees (Go modules, Cargo, pub cache, Flutter SDKs, runner toolchains) no longer count as projects (#38).
- Totals count each path once when rules overlap; the CLI no longer lists Chrome IndexedDB twice (#39).
- A scan that hits its time limit says which part is incomplete instead of reporting nothing (#40).
- SwiftPM `.build` and other hidden build caches are reclaimed when their project manifest sits beside them (#44).
- Project discovery refreshes daily or on Rescan, and finds Node, Flutter and PHP projects (#45).
- Old upgrade backups are offered for review once the app has moved on (#56).
- Old app versions kept side by side are offered for review; the newest two and any running version are kept (#57).
- Folder sizing has a deadline; slow folders show "at least" instead of a guess (#58).
- Abandoned Codex marketplace staging folders can be cleaned while Codex is not running (#59).
- pnpm store versions the current pnpm no longer uses are offered for review (#61).

### Diagnostics
- Deleted-but-open files and swap usage are explained, with how to get the space back (#51).
- Crash loops and runaway logs are reported, explain-only (#52).
- Pare says when the Mac recently ran out of memory and which process was largest (#53).
- Launch agents stuck in a restart loop are flagged (#55).
- Folders full of tiny files that waste disk blocks are explained (#62).

### App
- After a cleanup, the estimate is shown next to how much space the disk actually gained, with an empty-the-Trash hint (#54).
- The sidebar disk meter shows purgeable space, swap and APFS local snapshots (#60).
- The Homebrew tab previews `brew cleanup` and runs it after confirmation (#64).
- Documentation describes the reference cleanup tool neutrally (#43).

### Notes
- `FileSystemUtils.directorySize` counts hidden files on purpose (it no longer skips them), so project and cache sizes include dot-files such as `node_modules/.pnpm`.

---

## [1.0.0] — 2026-06-29

Initial public release.

### Scan Rules (36 unique rules in `RuleCatalog.all`)

**Baseline — runs for every user**
- User Caches — `~/Library/Caches/` (3-day age gate)
- Temporary Files — `~/Library/Caches/TemporaryItems/` and system temp dirs
- Logs & Crash Reports — `~/Library/Logs/` and `DiagnosticReports/` (1-day gate)
- Browser Caches — Chrome, Safari, Firefox, Brave, Edge, Arc, Opera render caches
- Browser Extended Artifacts — GPU/shader caches (safe) and session/storage data (review)
- Browser Personal Data — history, cookies, form data across all major browsers (30-day gate)
- Installer Files — `.dmg`, `.pkg`, `.iso`, `.xip` and installer ZIPs in Downloads/Desktop/iCloud Drive (7-day gate)
- Stale App Versions — detects duplicate `.app` bundles by bundle ID; flags older copies
- Project Artifacts — `node_modules/`, `target/`, `venv/`, `dist/`, and 10 other patterns in user project trees (7-day gate)
- iOS / iPadOS Backups — groups by device; flags old or redundant backups (30-day gate)
- Productivity App Caches — Slack, Zoom, Google Drive FS, Dropbox, Teams, OneDrive, Office caches; Zoom recordings flagged as review (3-day / 30-day gates)
- Orphaned Launch Agents — plists in `~/Library/LaunchAgents/` whose binary no longer exists (30-day gate)

**Developer profile — adds above plus**
- Xcode DerivedData, Archives, Simulator Caches
- VS Code caches, duplicate extensions, stale workspace storage
- JetBrains caches, stale IDE versions (90-day gate), review-required state
- Docker Desktop logs + VM disk image visibility
- AI Tool Caches — Cursor, Claude, Windsurf, GitHub Copilot, Continue, Tabnine
- Homebrew download cache
- Polyglot package manager caches — pip/Poetry/uv, gem/Bundler/rbenv, Gradle/Maven/Ivy2, Cargo/rustup, Go module cache
- Project Artifacts v2 — Spotlight-discovered project roots with opt-out checkboxes
- Wrong-platform binaries — Windows/Linux executables in Downloads and JetBrains plugin trees

**Designer profile** — adds Adobe and Figma caches + render preview review items

**Video builder profile** — adds Final Cut Pro, Premiere, After Effects, DaVinci Resolve caches

### App Features

- **Scan dashboard** — unified scan across all categories; Quick Clean (safe-only), Deep Clean (safe + review with confirmation); per-rule progress (title + index/count); force-rescan
- **Full Disk Access coaching** — detects likely missing FDA; Settings status + empty-scan guidance with System Settings deep link
- **Metrics** — total reclaimable space, per-category summary cards, large file breakdown (≥ 50 MB), by-tool attribution with top 10 files per app
- **Project scan paths** — manual project roots for artifact purge; Spotlight discovery for Project Artifacts v2 (managed via Settings / discovery store)
- **Device Backups card** — shows each stale backup with device name, iOS version, size, and date
- **App Manager** — full app inventory with size/install date/last-used; update detection (Sparkle + MAS); uninstaller with leftover scan; Homebrew cask detection
- **Homebrew Manager** — formulae, casks, outdated packages with streaming upgrade log; Migrate tab matches installed apps to Homebrew casks
- **Disk Analyzer** — async tree scan (depth 4, top 50 per node); proportional size bars; Reveal in Finder / Move to Trash on hover
- **Maintenance tab** — five one-shot system actions with live streaming log: Flush DNS, Rebuild Launch Services, Restart Finder, Vacuum SQLite databases (Mail/Safari/Messages), Docker System Prune (shown only when Docker daemon is running)
- **History / Audit log** — complete record of every cleanup run; expandable per-item detail; export as JSON or CSV
- **Exclusion list** — prefix or exact-path exclusions; persisted across launches

### Safety model

- Three risk levels: **Safe** (auto-clean), **Review** (confirm before clean), **Advanced** (detect-only; never deleted — e.g. Docker VM disk image)
- Every path is re-verified by `ScanPolicy` at cleanup time as a belt-and-suspenders check
- Minimum age gates per category prevent flagging files that are actively in use
- All cleanup uses `FileManager.trashItem` — nothing is permanently deleted; full undo via History tab
- `CleanupTransaction` records persisted to `~/Library/Application Support/Pare/transactions/`

### Distribution

- Requires macOS 13 Ventura or later
- Universal binary (Apple Silicon + Intel)
- Distributed as a signed and notarized `.dmg`; direct download (no Mac App Store — sandboxing is incompatible with full-disk scanning)
- Full Disk Access recommended: grant in System Settings → Privacy & Security → Full Disk Access
