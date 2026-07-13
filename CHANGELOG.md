# Changelog

All notable changes to Pare are documented here.

---

## [1.0.0] — 2026-06-29

Initial public release.

### Scan Rules (22 rules across 14 categories)

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

- **Scan dashboard** — unified scan across all categories; Quick Clean (safe-only), Deep Clean (safe + review with confirmation); real-time progress; force-rescan
- **Metrics** — total reclaimable space, per-category summary cards, large file breakdown (≥ 50 MB), by-tool attribution with top 10 files per app
- **Project Roots card** — auto-discovers project roots via Spotlight; per-root opt-out checkboxes; manual addition
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
