# Roadmap & Checklist

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done

---

## Phase 0 — Rename to Pare

New name: **Pare** — surgical, deliberate reduction. Bundle ID: `com.yudgnahk.pare`.

- [x] Update `Package.swift` — product names, target names
- [ ] Update bundle IDs (`com.yudgnahk.pare`) across all targets — deferred to Phase 6 (requires Info.plist + signing)
- [x] Update `AppTheme`, window titles, About panel
- [x] Rename `PareApp/`, `PareCore/`, `PareCLI/` source directories
- [x] Update `CLAUDE.md` and all docs to reflect new name
- [x] Rename the repo

---

## Phase 1 — Quick Wins (copy from Mole, small effort)

### AI Tool Cache Rules
- [~] `AIToolCachesRule` — target dirs and what each produces:
  - [x] GitHub Copilot CLI: `~/.copilot/logs/`
  - [x] Cursor: `~/Library/Application Support/Cursor/Cache/`
  - [ ] Cursor Todesktop cache: `~/Library/Caches/com.todesktop.*/` — **needs ID verification; not present on test machine**
  - [x] Claude desktop: `~/Library/Application Support/Claude/Cache/`
  - [x] Windsurf: `~/Library/Application Support/Windsurf/Cache/`
  - [x] Continue.dev: `~/.continue/cache/`
  - [x] Tabnine: `~/.tabnine/`
- [x] Register in `RuleCatalog` (developer profile + `all`)

### Homebrew Download Cache Rule
- [x] `HomebrewCacheRule` — target: `~/Library/Caches/Homebrew/downloads` (bottles + cask downloads)
- [x] Skip gracefully if Homebrew not installed — cache dir doesn't exist → traversal returns empty (no-op)
- [x] Risk: `.safe` (download cache, always reconstructible)
- [x] Register in `RuleCatalog` (developer profile + `all`)
- Note: full `BrewRunner.homebrewPrefix()` integration deferred to Phase 4 (path is arch-independent)

### Installer File Finder
- [x] `InstallerFileRule` — scan locations:
  - [x] Downloads, Desktop
  - [x] `~/Library/Mobile Documents/com~apple~CloudDocs/` (iCloud Drive)
  - [ ] Telegram downloads — path unverifiable (not installed on dev machine); skip
- [x] Match: `.dmg`, `.pkg`, `.iso`, `.xip` at any depth
- [x] For `.zip`: inspect PK magic + central directory for `.app/` or `Payload/` entries
- [x] Risk: `.review` (may be intentionally kept)
- [x] Minimum age gate: 7 days (fresh downloads excluded)
- [x] Register in `RuleCatalog` (baseline profile + `all`)

---

## Phase 2 — Stale App Version Detection

- [x] Extract version comparison logic from `JetBrainsStaleVersionRule` into `FileSystemUtils.compareVersionStrings(_ a: String, _ b: String) -> ComparisonResult`
- [x] Update `JetBrainsStaleVersionRule` to use the shared utility
- [x] Implement `StaleAppVersionRule` (`customScan`):
  - Enumerate `/Applications`, `~/Applications` at depth 1
  - Read `CFBundleIdentifier` + `CFBundleVersion` from each `.app/Contents/Info.plist`
  - Group by bundle ID; skip groups with count == 1
  - Within each group: sort by `compareVersionStrings`, tiebreak by `effectiveAgeDate`
  - Flag all but highest as `.review` findings (category: `.applications`)
  - Skip `/System/Applications/` entirely
  - Fallback for missing bundle ID: normalise display name (strip trailing digits, "beta", "dev")
  - Do not flag groups where all members share the same `CFBundleVersion`
- [x] Write tests in `PareCoreTests`:
  - Two copies same bundle ID → older flagged
  - Same bundle ID, same version → neither flagged
  - Missing bundle ID → name-based fallback groups correctly
  - SIP path excluded
- [x] Register in `RuleCatalog.all` (added to `baseline` so all profiles include it)

---

## Phase 3 — App Manager

### Core (no UI yet — backend only)
- [x] `AppInventory` actor — discovery + metadata fetch
  - Scan `/Applications`, `/System/Applications`, `~/Applications`
  - Supplement with `NSMetadataQuery` for Setapp and other non-standard locations
  - Per-app: name, bundle ID, version, size (`totalFileAllocatedSizeKey`), install date, last-used (`kMDItemLastUsedDate`), MAS flag, SIP flag
  - Fetch concurrently with `withTaskGroup`
- [x] `AppUninstaller` — leftover scan + Trash
  - Key by bundle ID across all leftover locations (see `app-manager.md` for full list)
  - Detect Homebrew-managed apps via caskroom receipt; prefer `brew uninstall --zap`
  - Group Container: detect, surface as warning, never auto-select
  - Always uses `FileManager.trashItem`, never `removeItem`
- [x] `OutdatedChecker` — version check
  - Sparkle: read `SUFeedURL`, fetch appcast, parse `<sparkle:version>`
  - MAS: iTunes Lookup API, batch ≤ 25, retry with backoff
  - Run both channels in parallel
- [x] `InstalledApp`, `AppLeftover`, `UpdateInfo` value types (all `Sendable`)
- [x] Add `isSystemApp`, `isGroupContainer` to `ScanPolicy`

### SwiftUI (after backend is solid)
- [x] `AppManagerViewModel` (`@MainActor ObservableObject`)
- [x] `AppManagerView` — sortable list with filter bar
  - Columns: icon, name, version, size, install date, last used
  - Sort by any column (name, size, install date, last used)
  - Filter bar: search, hide SIP apps, only outdated
- [x] `AppUninstallConfirmSheet` — leftover preview, Group Container warning, confirm → Trash
- [x] Integrate into main navigation (Apps tab)

---

## Phase 4 — Homebrew Manager

### Core
- [x] `BrewRunner` — process wrapper
  - Detect prefix (check `/opt/homebrew/bin/brew` then `/usr/local/bin/brew`)
  - Set `HOMEBREW_NO_AUTO_UPDATE=1` and `HOME`
  - Read stdout + stderr concurrently (pipe deadlock prevention)
- [x] `BrewInventory` actor — `brew info --json=v2 --installed`
  - Parse formulae (name, version, install date, `installed_on_request`)
  - Parse casks (token, version, `auto_updates`, installed app names)
  - Default view: user-requested only (`installed_on_request: true`); toggle for all
- [x] `BrewOutdatedChecker` — `brew outdated --json=v2 --greedy`
  - Respect `pinned: true`
  - Tag `auto_updates: true` casks with "(auto)" badge
- [x] `MigrationAdvisor`
  - Fetch `https://formulae.brew.sh/api/cask.json` (24-hour cache)
  - Match installed apps by artifact app name and bundle ID (`artifacts[].uninstall[].quit`)
  - Exclude already Homebrew-managed apps
  - Prefer `brew install --cask --adopt <token>` (Homebrew ≥ 3.5)
- [x] `BrewFormula`, `BrewCask`, `OutdatedPackage`, `MigrationCandidate` value types

### SwiftUI
- [x] `HomebrewManagerViewModel` (`@MainActor ObservableObject`)
- [x] `HomebrewManagerView` — segmented: Formulae / Casks / Outdated / Migrate
- [x] `BrewOperationSheet` — streaming log output for upgrade/uninstall/migrate
- [x] "Not installed" placeholder with install instructions if Homebrew absent
- [x] Integrate into main navigation

---

## Phase 5 — Medium Priority Gaps

### Browser Extended Artifact Cleanup
- [x] Extend `BrowserCachesRule` to add Arc, Edge, Opera to `targetDirectories`
- [x] `BrowserExtendedArtifactsRule` (`customScan`) covers:
  - Shader / GPU caches in Application Support for Chrome, Edge, Brave, Arc, Opera → `.safe`
  - Session restore, WebSQL, IndexedDB, local storage for same browsers → `.review`
  - Note: browser crash reports already covered by `LogsAndCrashReportsRule` (DiagnosticReports)
- [x] Added `browserExtendedSafePathMarkers` / `browserExtendedReviewPathMarkers` to `ScanPolicy` + `personaProtectedPathOverrides`
- [x] `CleanupEngine.isPersonaPath` includes new markers so paths pass the re-verify guard

### Project Artifact Purge
- [x] `ProjectScanPathStore` — persists user-supplied root paths in `UserDefaults`
- [x] `ProjectArtifactRule` (`customScan`) — recursive walk (depth ≤ 5) of user roots
  - Targets: `node_modules/`, `target/`, `venv/`, `.venv/`, `__pycache__/`, `build/`, `.gradle/`, `.bundle/`, `dist/`, `.next/`, `.nuxt/`, `.cache/`
  - 7-day minimum age gate
  - Prunes descent into matched artifact dirs (no double-counting nested node_modules)
- [x] `ScanPolicy.isProjectArtifact()` + `CleanupEngine` bypass so paths in user project trees are cleanable
- [x] `ProjectScanPathsView` sheet accessible from new folder button in Scan header
- [x] Registered in `RuleCatalog.baseline` (included in `all`)

### System Optimizer
- [ ] Requires admin privileges — use `SMJobBless` or `AuthorizationExecuteWithPrivileges`
- [ ] Tasks: DNS flush, Finder refresh, LaunchServices rebuild, SQLite VACUUM (Mail/Safari/Messages), broken pref repair
- [ ] Each task is individually toggleable; show estimated time
- [ ] This is the riskiest phase — validate on macOS 13, 14, 15 before shipping
- Note: deferred — too risky without hardware validation on multiple macOS versions

### Disk Analyzer Drill-Down
- [x] `DiskAnalyzerView` + `DiskAnalyzerViewModel` — new "Disk" tab
  - Async tree scan (depth ≤ 4, top-50 children per node, sorted by size)
  - Size bar per row proportional to parent (colour shifts red for items > 50% of parent)
  - "Reveal in Finder" and "Move to Trash" actions on hover
- [ ] Highlight items matching existing scan findings (deferred — requires cross-ViewModel wiring)

### History / Audit Log UI
- [x] List view with expandable detail already existed (Phase 3/4)
- [x] Export as JSON (`NSSavePanel` → pretty-printed) and CSV (per-item rows) via Export menu in History header

---

## Phase 6 — Developer Ecosystem Breadth

Spec: `docs/features/phase-6-developer-breadth.md`

### Package Manager Cache Rules
- [x] `PythonCachesRule` — pip, Poetry, uv, pyenv download cache (NOT Python runtimes)
- [x] `RubyCachesRule` — gem download cache, Bundler cache, rbenv download cache (NOT installed versions)
- [x] `JavaBuildCachesRule` — Gradle caches + wrapper dists, Maven local repo, Ivy2 cache
- [x] `RustCachesRule` — Cargo registry cache + src, git checkouts, rustup downloads
- [x] `GoCachesRule` — Go build cache (`~/Library/Caches/go-build/`), module download cache
- [x] Register all in `RuleCatalog` (developer profile + `all`)

### Project Artifact Purge v2 — Smart Discovery
The Phase 5 implementation hardcodes scan paths. Replace with Spotlight-based project discovery:
- [x] `ProjectRootDiscovery` actor — `NSMetadataQuery` search for `.git` directories + language signal files (`Package.swift`, `Cargo.toml`, `go.mod`, `pyproject.toml`, `Gemfile`) scoped to user home
- [x] Deduplicate to project roots: resolve each signal to its parent, drop descendants within 3 path components of an ancestor (submodule heuristic)
- [x] Filter out system paths, `node_modules/`, `vendor/`, `.Trash/`
- [x] Persist confirmed roots to `~/Library/Application Support/Pare/project-roots.json`
- [x] `ProjectArtifactsRule` (customScan) — scan confirmed roots for artifact patterns; 7-day age gate per artifact directory
- [x] Artifact patterns: `node_modules/`, `target/`, `venv/`/`.venv/`, `__pycache__/`, `.gradle/`, `.bundle/`, `.next/`, `.nuxt/`, `.parcel-cache/`, `.turbo/`, `.nx/`, `dist/`
- [x] UI: "Project Roots" card in Scan tab — discovered roots with checkboxes (opt-out), "Rescan" button, "Add folder…" for manual addition

---

## Phase 7 — Platform Completeness

Spec: `docs/features/phase-7-platform-completeness.md`

### Docker Full Cleanup
- [ ] `DockerStorageRule` (extends/replaces `DockerLogsRule`) — detect Docker VM disk image size (`Docker.raw`), report as `.advanced` finding (detect only; deleting the image is too destructive)
- [ ] Add Docker log paths to existing rule (lifecycle logs, Desktop logs)
- [ ] `docker system prune` action in Maintenance tab (Phase 8) — safest way to reclaim Docker space

### iOS / iPadOS Backup Management
- [ ] `MobileSyncBackupsRule` (customScan) — enumerate `~/Library/Application Support/MobileSync/Backup/`
- [ ] Parse `Info.plist` per backup for device name, iOS version, last backup date
- [ ] Group by device; flag oldest backups per device as `.review` if > 1 backup exists, or any backup > 180 days old
- [ ] "Device Backups" card in Scan tab showing device name, iOS version, backup date, size

### Browser Review Data
- [ ] `BrowserReviewDataRule` — history databases, cookies, form data, IndexedDB, WebSQL for Safari, Chrome, Firefox, Brave, Arc, Edge
- [ ] Risk: `.review` for all (personal data); 30-day minimum age gate
- [ ] Distinct from existing `BrowserCachesRule` (which stays `.safe`)

---

## Phase 8 — Productivity & System Health

Spec: `docs/features/phase-8-productivity-system.md`

### Cloud & Productivity App Cleanup
- [ ] `ProductivityCachesRule` — extend `app-catalog.json` with `"productivity"` category
- [ ] Targets: Slack workspace cache, Zoom cache + cloud recordings folder, Google Drive FS cache, Dropbox logs, Microsoft Teams cache, OneDrive cache, Office temp files
- [ ] Risk: `.safe` for caches, `.review` for recording/document folders

### Orphaned Launch Agents
- [ ] `OrphanedLaunchAgentsRule` (customScan) — scan `~/Library/LaunchAgents/*.plist`
- [ ] Parse `Program` / `ProgramArguments[0]` from each plist; check if binary exists
- [ ] Flag plist as `.review` if binary is missing; include missing binary path in `reason`
- [ ] Skip plists with shell variable expansion in paths (can't resolve reliably)
- [ ] 30-day age gate on the plist file itself

### Maintenance Tab
- [ ] New SwiftUI tab "Maintenance" (icon: `wrench.and.screwdriver`) — one-shot system actions, not file deletions
- [ ] `MaintenanceAction` struct (id, title, description, estimatedSeconds, requiresSudo, run: () async throws -> Void)
- [ ] `MaintenanceViewModel` (@MainActor) — tracks running / completed / error state per action
- [ ] `MaintenanceView` — card grid; each card shows title, description, status, "Run" button
- [ ] Initial actions (no sudo required):
  1. **Flush DNS cache** — `dscacheutil -flushcache; killall -HUP mDNSResponder`
  2. **Rebuild Launch Services** — `lsregister -kill -r -domain local -domain system -domain user`
  3. **Restart Finder** — `killall Finder`
  4. **Vacuum SQLite databases** — Mail, Safari, Messages envelope indices
  5. **Docker system prune** — `docker system prune -f` (shown only if Docker is installed + running)
- [ ] Actions run via `NSTask`; stdout/stderr streamed to an inline log view
- [ ] Validate on macOS 13, 14, 15 before shipping

---

## Phase 9 — Polish & Distribution

- [ ] Code signing — Developer ID Application certificate
- [ ] Hardened Runtime entitlements audit
- [ ] Notarization (`xcrun notarytool`)
- [ ] Staple notarization ticket (`xcrun stapler`)
- [ ] Test Gatekeeper pass on a clean machine
- [ ] App icon (all required sizes: 16–1024 pt @1x/@2x)
- [ ] `CHANGELOG.md` for v1.0
- [ ] Distribution choice: direct download (GitHub Releases) vs Mac App Store
  - MAS requires sandboxing — most rules won't work under sandbox; direct download is the realistic path
- [ ] GitHub release with signed `.dmg`

---

## Always-On (every phase)

- [ ] `make build` passes before any PR
- [ ] `make test` passes; coverage ≥ 80%
- [ ] `make run-app` — manual smoke test of changed feature
- [ ] `gitnexus_impact` run before editing any symbol
- [ ] `gitnexus_detect_changes` run before committing
- [ ] Update roadmap artifact after completing each phase
