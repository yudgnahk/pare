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

- [ ] Extract version comparison logic from `JetBrainsStaleVersionRule` into `FileSystemUtils.compareVersionStrings(_ a: String, _ b: String) -> ComparisonResult`
- [ ] Update `JetBrainsStaleVersionRule` to use the shared utility
- [ ] Implement `StaleAppVersionRule` (`customScan`):
  - Enumerate `/Applications`, `~/Applications` at depth 1
  - Read `CFBundleIdentifier` + `CFBundleVersion` from each `.app/Contents/Info.plist`
  - Group by bundle ID; skip groups with count == 1
  - Within each group: sort by `compareVersionStrings`, tiebreak by `effectiveAgeDate`
  - Flag all but highest as `.review` findings (category: `.applications`)
  - Skip `/System/Applications/` entirely
  - Fallback for missing bundle ID: normalise display name (strip trailing digits, "beta", "dev")
  - Do not flag groups where all members share the same `CFBundleVersion`
- [ ] Write tests in `PareCoreTests`:
  - Two copies same bundle ID → older flagged
  - Same bundle ID, same version → neither flagged
  - Missing bundle ID → name-based fallback groups correctly
  - SIP path excluded
- [ ] Register in `RuleCatalog.all`

---

## Phase 3 — App Manager

### Core (no UI yet — backend only)
- [ ] `AppInventory` actor — discovery + metadata fetch
  - Scan `/Applications`, `/System/Applications`, `~/Applications`
  - Supplement with `NSMetadataQuery` for Setapp and other non-standard locations
  - Per-app: name, bundle ID, version, size (`totalFileAllocatedSizeKey`), install date, last-used (`kMDItemLastUsedDate`), MAS flag, SIP flag
  - Fetch concurrently with `withTaskGroup`
- [ ] `AppUninstaller` — leftover scan + Trash
  - Key by bundle ID across all leftover locations (see `app-manager.md` for full list)
  - Detect Homebrew-managed apps via caskroom receipt; prefer `brew uninstall --zap`
  - Group Container: detect, surface as warning, never auto-select
  - Always use `NSWorkspace.recycle`, never `FileManager.removeItem`
- [ ] `OutdatedChecker` — version check
  - Sparkle: read `SUFeedURL`, fetch appcast, parse `<sparkle:version>`
  - MAS: iTunes Lookup API, batch ≤ 25, retry with backoff
  - Run both channels in parallel
- [ ] `InstalledApp`, `AppLeftover`, `UpdateInfo` value types (all `Sendable`)
- [ ] Add `isSystemApp`, `isGroupContainer` to `ScanPolicy`

### SwiftUI (after backend is solid)
- [ ] `AppManagerViewModel` (`@MainActor ObservableObject`)
- [ ] `AppManagerView` — sortable table (`Table` on macOS 13+)
  - Columns: icon, name, version, size, install date, last used
  - Sort by any column
  - Filter bar: search, hide SIP, only outdated, only duplicates
- [ ] `AppUninstallConfirmSheet` — leftover preview, Group Container warning, confirm → Trash
- [ ] Integrate into main navigation (tab or sidebar item)

---

## Phase 4 — Homebrew Manager

### Core
- [ ] `BrewRunner` — process wrapper
  - Detect prefix (check `/opt/homebrew/bin/brew` then `/usr/local/bin/brew`)
  - Set `HOMEBREW_NO_AUTO_UPDATE=1` and `HOME`
  - Read stdout + stderr concurrently (pipe deadlock prevention)
- [ ] `BrewInventory` actor — `brew info --json=v2 --installed`
  - Parse formulae (name, version, install date, `installed_on_request`)
  - Parse casks (token, version, `auto_updates`, installed app names)
  - Default view: user-requested only (`installed_on_request: true`); toggle for all
- [ ] `BrewOutdatedChecker` — `brew outdated --json=v2 --greedy`
  - Respect `pinned: true`
  - Tag `auto_updates: true` casks with "(auto)" badge
- [ ] `MigrationAdvisor`
  - Fetch `https://formulae.brew.sh/api/cask.json` (24-hour cache)
  - Match installed apps by artifact app name and bundle ID (`artifacts[].uninstall[].quit`)
  - Exclude already Homebrew-managed apps
  - Prefer `brew install --cask --adopt <token>` (Homebrew ≥ 3.5)
- [ ] `BrewFormula`, `BrewCask`, `OutdatedPackage`, `MigrationCandidate` value types

### SwiftUI
- [ ] `HomebrewManagerViewModel` (`@MainActor ObservableObject`)
- [ ] `HomebrewManagerView` — segmented: Formulae / Casks / Outdated / Migrate
- [ ] `BrewOperationSheet` — streaming log output for upgrade/uninstall/migrate
- [ ] "Not installed" placeholder with install instructions if Homebrew absent
- [ ] Integrate into main navigation

---

## Phase 5 — Medium Priority Gaps

### Browser Extended Artifact Cleanup
- [ ] Extend existing browser cache rules to cover:
  - Crash reports, session restore, WebSQL, IndexedDB
  - Shader caches, GPU caches
  - Targets: Chrome, Firefox, Safari, Brave, Arc, Edge, Opera

### Project Artifact Purge
- [ ] New rule or standalone scanner — recursive directory tree walk from user-supplied root paths
- [ ] Targets: `node_modules/`, `target/` (Rust), `venv/`, `__pycache__/`, `build/`, `.gradle/`, `.bundle/`, `dist/`, `.next/`, `.nuxt/`
- [ ] 7-day minimum age gate
- [ ] Expose "add scan path" UI so users can point at their Projects folder

### System Optimizer
- [ ] Requires admin privileges — use `SMJobBless` or `AuthorizationExecuteWithPrivileges`
- [ ] Tasks: DNS flush, Finder refresh, LaunchServices rebuild, SQLite VACUUM (Mail/Safari/Messages), broken pref repair
- [ ] Each task is individually toggleable; show estimated time
- [ ] This is the riskiest phase — validate on macOS 13, 14, 15 before shipping

### Disk Analyzer Drill-Down
- [ ] `SwiftUI.OutlineGroup` tree view rooted at a user-chosen directory
- [ ] Size bar per row (proportional to parent)
- [ ] Sort by size; highlight items matching existing scan findings
- [ ] "Reveal in Finder" and "Move to Trash" actions per row

### History / Audit Log UI
- [ ] Read existing `CleanupTransaction` JSON from `~/Library/Application Support/<AppName>/transactions/`
- [ ] List view: timestamp, operation type, file count, total size freed
- [ ] Detail view: per-file paths, risk level, outcome (trashed / skipped)
- [ ] Export as JSON or CSV

---

## Phase 6 — Polish & Distribution

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
