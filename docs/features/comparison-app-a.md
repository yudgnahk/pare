# Pare vs App A — Feature Comparison

**App A** (github.com/mole-cli — the reference Go+Bash "clean macOS" CLI) has 8 commands and covers a wide surface area. This document maps the gaps and advantages.

---

## Features App A Has — We Don't (Gap List)

Ordered by user impact (highest first).

### 1. Full App Uninstaller with Leftover Detection
**App A command**: `app-a uninstall`  
App A finds and removes 52+ categories of hidden leftovers per app: Launch Agents/Daemons, preferences, cookies, caches, containers, saved state, WebKit storage, app scripts, Biometric DB entries, and more. It also detects whether the app was installed via Homebrew cask and calls `brew uninstall` in that case.

We have: no app uninstall capability at all.  
**Status**: Planned — `docs/features/app-manager.md`

---

### 2. System Optimizer
**App A command**: `app-a optimize`  
Runs system maintenance tasks that go beyond file deletion:
- DNS cache flush (`sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`)
- Finder cache refresh (kills and relaunches Finder)
- Dock refresh
- SQLite VACUUM on Mail, Safari, Messages databases
- LaunchServices database rebuild (`/System/Library/Frameworks/CoreServices.framework/…/lsregister -kill -r -domain local -domain system -domain user`)
- Broken preferences repair (removes zero-byte/malformed plists from `~/Library/Preferences/`)
- Swap file removal (restarts swap cleanly)

We have: none of these.  
**Priority**: Medium — these are power-user operations but high-impact when disk space or system sluggishness is the complaint.

---

### 3. Real-Time System Monitor
**App A command**: `app-a status`  
Live dashboard showing CPU per-core, memory pressure, disk I/O, network throughput, battery cycle count, thermal state, and an aggregate "health score". Alerts when any process exceeds a CPU threshold.

We have: no monitoring capability.  
**Priority**: Low for a disk-cleaner; medium if we want to expand into a full "system health" tool.

---

### 4. Interactive Disk Analyzer
**App A command**: `app-a analyze`  
TUI disk space explorer with drill-down navigation (like a CLI DaisyDisk). Shows directory trees sorted by size, highlights the largest files, shows directory "aging" (last-modified date), and allows deleting items to Trash directly from the view. JSON output mode.

We have: "Top Files" list in scan results, but no drill-down explorer.  
**Priority**: Medium — top-files surfacing is our partial answer, but interactive drill-down is materially better UX for diagnosing unexpected disk usage.

---

### 5. Project Artifact Purge
**App A command**: `app-a purge`  
Recursively finds and removes build artifacts across 7+ language ecosystems with a 7-day safety gate:
- Node.js: `node_modules/`
- Rust: `target/`
- Python: `venv/`, `__pycache__/`, `.pytest_cache/`, `*.egg-info/`
- Java/Kotlin/Gradle: `build/`, `.gradle/`
- Ruby: `.bundle/`
- Go: module download cache (`$GOPATH/pkg/mod/`)
- Generic: `dist/`, `.next/`, `.nuxt/`

Accepts custom scan paths. Supports dry-run.

We have: build artifact cleanup in the developer profile, but limited to a fixed set of well-known tool caches (Xcode DerivedData, Gradle caches, etc.) — not recursive project-tree scanning.  
**Priority**: Medium-High for developer users. Scanning arbitrary project trees is a distinct use case from scanning known tool directories.

---

### 6. Installer File Finder
**App A command**: `app-a installer`  
Finds installer files (`.dmg`, `.pkg`, `.iso`, `.xip`) across Downloads, Desktop, Homebrew cache, Mail downloads, iCloud Drive, and Telegram downloads. For `.zip` files, it also inspects the archive contents to detect zipped installers. Offers to move all to Trash.

We have: `WrongPlatformBinariesRule` detects non-macOS binaries in Downloads, but we do not scan for macOS installer files that are safe to remove after installation.  
**Priority**: Medium — this is a very common "low-hanging fruit" disk space win for most users.

---

### 7. AI / Agent Cache Cleanup
**App A command**: `app-a clean` (within `dev.sh`)  
App A's developer cleaning includes explicit cleanup of AI tool caches:
- GitHub Copilot cache (`~/.copilot/`)
- Cursor editor cache
- Claude (Anthropic desktop app) cache
- Windsurf cache
- Continue.dev cache
- Tabnine cache

We have: VS Code, JetBrains, and Docker caches — but no AI tool caches.  
**Priority**: High and growing — these caches are becoming significant in size.

---

### 8. Homebrew Cask Cache Cleaning
**App A command**: `app-a clean`  
App A cleans `$(brew --cache)` (the download cache for casks and bottles). A heavy Homebrew user can accumulate several GB here.

We have: no Homebrew cache cleaning.  
**Status**: Can be added as a simple rule in `HomebrewManager` or as a standalone `ScanRule`.

---

### 9. Browser Artifact Deep Cleaning
**App A command**: `app-a clean` (within `apps.sh`)  
Beyond caches, App A removes browser-specific artifacts: crash reports, session restore data, WebSQL databases, IndexedDB, shader caches, GPU caches, and extension development artifacts. Covers Chrome, Firefox, Safari, Brave, Arc, Edge, Opera.

We have: browser cache rules, but not the extended artifact set.  
**Priority**: Medium — the extended artifacts are meaningful but less common than caches.

---

### 10. Operation Audit Log
**App A command**: `app-a history`  
Every operation App A performs is logged with a timestamp, operation type, and list of affected paths. The log is queryable and exportable as JSON.

We have: `CleanupTransaction` JSON files in `~/Library/Application Support/Pare/transactions/` — effectively an audit log, but no UI to browse it.  
**Gap**: We have the data; we lack the UI to surface it.  
**Priority**: Low — the underlying data exists; this is a UI investment.

---

### 11. Whitelist (Global Exclusions by Category)
**App A command**: `app-a manage whitelist`  
App A supports category-level whitelisting — protect an entire class of paths from any cleaning command.

We have: `ExclusionList` (path-level exclusions), which is more granular but requires specifying individual paths.  
**Gap**: Category-level "never touch ~/Library/Caches/MyApp" without specifying every subpath.

---

## What We Do Better Than App A

### 1. Native SwiftUI GUI
App A is CLI-only (the paid Mac app is a separate commercial product). We ship a native macOS SwiftUI app with a visual scan dashboard, per-category breakdowns, animated progress, and one-click cleanup — accessible to non-technical users.

### 2. Trash-Based Cleanup with Undo
Every file we remove goes to Trash via `NSWorkspace.recycle`. App A deletes permanently in most commands (only `app-a analyze` trashes items). We also persist `CleanupTransaction` records for post-cleanup review.

### 3. Risk-Level Classification
Every finding is tagged `safe` / `review` / `advanced`:
- `safe`: auto-deletable with no confirmation
- `review`: requires user acknowledgement before `deepClean`
- `advanced`: detect and report only; `CleanupEngine` hard-blocks deletion

App A has `--dry-run` but no per-finding risk grading.

### 4. Per-App Attribution ("By Tool" Rollup)
`ScanReportAnnotator` maps every finding back to its source app and shows per-app totals with top-10 largest files. Users see "Xcode is responsible for 12 GB of your junk" rather than a flat list of paths.

### 5. Generic Stale App Version Detection
We detect multiple installed copies of any app — not just JetBrains — by grouping on `CFBundleIdentifier` and comparing `CFBundleVersion`. The older copy is flagged as a `.review` candidate (never auto-deleted). This covers: same app installed from two different sources, a previous version left behind after a manual upgrade, or a beta alongside its stable release.

The JetBrains rule was the starting point; `StaleAppVersionRule` generalises it to every `.app` bundle across `/Applications` and `~/Applications`. Both rules share the same version-comparison utility in `FileSystemUtils` and both use `effectiveAgeDate` (min of creation/mtime) as a tiebreaker so migration activity cannot hide a genuinely stale install.

App A has no equivalent for either the JetBrains-specific or the generic case.

### 6. ScanPolicy as Single Safety Guardrail
All path-safety logic lives in one place (`ScanPolicy`). Protected paths, sensitive paths, JetBrains app-state paths, minimum age gates, wrong-platform binary bypass — all centralized and re-verified at cleanup time in `CleanupEngine`. This makes it easy to audit and extend. App A's safety logic is scattered across 10+ Bash files.

### 7. Wrong-Platform Binary Detection in JetBrains Plugin Trees
We detect `win/`, `linux/`, `win32/` native plugin stub directories inside JetBrains IDE plugin trees (not just Downloads). These are inert on macOS and accumulate silently. App A does not have this.

### 8. `effectiveAgeDate` (Oldest of Creation/Mtime)
For directories, we use `min(creationDate, contentModificationDate)` as the age reference. This means JetBrains migration activity — which touches a stale version's config directory, resetting its mtime to today — cannot defeat the age gate. This is a correctness improvement App A does not have (App A uses mtime only).

### 9. Incremental Scan Cache (`CachedFileTraversal`)
After the first scan, subsequent rescans are fast because `CachedFileTraversal` caches metadata for unchanged directories. App A always does a full filesystem walk.

### 10. Per-Finding Confidence Score
Every `ScanFinding` carries a `confidence: Double` (0.0–1.0). Rules can express uncertainty. This enables future UI features like filtering low-confidence findings separately. App A has no equivalent.

---

## Priority Gap Closure Roadmap

| Priority | Feature | Effort |
|----------|---------|--------|
| High | AI tool cache rules (Copilot, Cursor, Claude) | Small — add rules to `Rules/` |
| High | App Manager (uninstall + outdated) | Large — see `app-manager.md` |
| High | Generic stale app version detection (`StaleAppVersionRule`) | Medium — extend `JetBrainsStaleVersionRule` pattern; see `app-manager.md` |
| High | Homebrew cache `ScanRule` | Small — one rule in `HomebrewManager` |
| Medium | Installer file finder (`app-a installer` equivalent) | Medium — new `ScanRule` |
| Medium | Project artifact purge (recursive tree scan) | Medium — new `ScanRule` with path input |
| Medium | Disk Analyzer drill-down view | Medium — SwiftUI `OutlineGroup` tree |
| Medium | System Optimizer (DNS, LaunchServices, SQLite vacuum) | Medium — needs admin privileges |
| Medium | Browser extended artifact cleanup | Small — extend existing browser rules |
| Medium | History/audit log UI | Small — read existing `CleanupTransaction` JSON |
| Low | System monitor dashboard | Large — out of scope for a disk cleaner |
