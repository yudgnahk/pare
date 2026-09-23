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

## Phase 1 — Quick Wins (small-effort scan rules)

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
- [x] `DockerStorageRule` covers aged Docker Desktop logs only; `Docker.raw` and the entire `Data/vms/` tree are hard-blocked and never emitted as cleanable scan findings
- [x] Add Docker daemon and Desktop UI log paths to the existing rule
- [x] Add Docker-native build-cache actions for cache older than 7 days or 1 day
- [~] Retire the broad `docker system prune -f` action; replace it with individually selected resources in Phase 10
- [x] Never use bulk volume pruning; Phase 10 may remove only explicitly selected, unused volumes by exact name
- [~] Full storage diagnosis, per-resource selection, and reclaim preview — continued in Phase 10

### iOS / iPadOS Backup Management
- [x] `MobileSyncBackupsRule` (customScan) — enumerate `~/Library/Application Support/MobileSync/Backup/`
- [x] Parse `Info.plist` per backup for device name, iOS version, last backup date
- [x] Group by device; flag oldest backups per device as `.review` if > 1 backup exists, or any backup > 180 days old
- [x] "Device Backups" card in Scan tab showing device name, iOS version, backup date, size

### Browser Review Data
- [x] `BrowserReviewDataRule` — history databases, cookies, form data, IndexedDB, WebSQL for Safari, Chrome, Firefox, Brave, Arc, Edge
- [x] Risk: `.review` for all (personal data); 30-day minimum age gate
- [x] Distinct from existing `BrowserCachesRule` (which stays `.safe`)

---

## Phase 8 — Productivity & System Health

Spec: `docs/features/phase-8-productivity-system.md`

### Cloud & Productivity App Cleanup
- [x] `ProductivityCachesRule` — Slack, Zoom, Google Drive FS, Dropbox, Teams, OneDrive, Office caches
- [x] Targets: Slack workspace cache, Zoom cache + cloud recordings folder, Google Drive FS cache, Dropbox cache, Microsoft Teams cache, OneDrive cache, Office caches
- [x] Risk: `.safe` for caches, `.review` for Zoom recordings folder

### Orphaned Launch Agents
- [x] `OrphanedLaunchAgentsRule` (customScan) — scan `~/Library/LaunchAgents/*.plist`
- [x] Parse `Program` / `ProgramArguments[0]` from each plist; check if binary exists
- [x] Flag plist as `.review` if binary is missing; include missing binary path in `reason`
- [x] Skip plists with shell variable expansion in paths (can't resolve reliably)
- [x] 30-day age gate on the plist file itself

### Maintenance Tab
- [x] New SwiftUI tab "Maintenance" (icon: `wrench.and.screwdriver`) — one-shot system actions, not file deletions
- [x] `MaintenanceAction` struct (id, title, description, estimatedSeconds, requiresSudo) — in `PareCore/Maintenance/`
- [x] `MaintenanceRunner` (PareCore) — executes actions, streams stdout/stderr via `AsyncThrowingStream`
- [x] `MaintenanceViewModel` (@MainActor) — tracks running / completed / error state per action
- [x] `MaintenanceView` — 2-column card grid; each card shows icon, title, description, status badge, Run button, expandable inline log
- [x] Initial actions (no sudo required):
  1. **Flush DNS cache** — `dscacheutil -flushcache; killall -HUP mDNSResponder`
  2. **Rebuild Launch Services** — `lsregister -kill -r -domain local -domain system -domain user`
  3. **Restart Finder** — `killall Finder`
  4. **Vacuum SQLite databases** — Mail (version-scanned), Safari History, Messages
  5. **Docker system prune** — current implementation; remove in Phase 10 in favor of explicit resource selection
  6. **Docker build cache (>7 days)** — routine age-filtered builder prune
  7. **Docker build cache (>1 day)** — low-disk age-filtered builder prune
- [x] Actions stream stdout/stderr to an expandable inline log per card (auto-expands on first output)
- [ ] Validate on macOS 13, 14, 15 before shipping

---

## Competitive analysis (living)

Aliases (no third-party product names): **App A** = CLI-first cleaner · **App B** = commercial care suite.

- [x] App A comparison — `docs/features/comparison-app-a.md` (2026-07-20)
- [x] App B comparison — `docs/features/comparison-app-b.md`
- [x] Ranked next-5 backlog — `docs/reviews/2026-07-20-competitive-gaps.md`

---

## Phase 9 — Polish & Distribution

- [ ] Code signing — Developer ID Application certificate (requires your keychain cert)
- [x] Hardened Runtime entitlements — `scripts/PareApp.entitlements` (no JIT, no DYLD injection, no sandbox)
- [x] Privacy usage descriptions added to `scripts/AppInfo.plist` (Desktop, Documents, Downloads)
- [ ] Notarization (`xcrun notarytool`) — automated in `scripts/release.sh`
- [ ] Staple notarization ticket (`xcrun stapler`) — automated in `scripts/release.sh`
- [ ] Test Gatekeeper pass on a clean machine
- [x] App icon — design complete (`docs/brand-guide.html`); source SVG at `scripts/icon.svg`; generate .icns with `make icon`
- [x] `CHANGELOG.md` for v1.0
- [x] Distribution: direct download via GitHub Releases (MAS incompatible with full-disk scanning)
- [x] `scripts/release.sh` — universal binary build → sign → DMG → notarize → staple → verify
- [x] `make release` target added to Makefile
- [ ] GitHub release tagged v1.0.0 with signed `.dmg`

---

## Phase 10 — Selective Docker Storage Manager

Replace broad Docker pruning with an explainable, inventory-first workflow. Pare must show what consumes space, what each resource belongs to, and exactly what will be removed. Nothing is selected automatically, and Pare never runs `docker system prune`.

The binding [`Docker safety policy`](features/docker-safety.md) must be updated before implementation to permit targeted removal of an explicitly selected unused volume while continuing to forbid `docker volume prune`, `--volumes`, force removal, and direct deletion of `Docker.raw`. Docker CLI behavior references: [`docker system df`](https://docs.docker.com/reference/cli/docker/system/df/), [`docker buildx du`](https://docs.docker.com/reference/cli/docker/buildx/du/), [`docker buildx prune`](https://docs.docker.com/reference/cli/docker/buildx/prune/), [`docker volume inspect`](https://docs.docker.com/reference/cli/docker/volume/inspect/), and [`docker volume rm`](https://docs.docker.com/reference/cli/docker/volume/rm/).

### Investigation baseline (2026-07-30)

Read-only inspection of the current development machine:

| Storage | Used | Reclaimable now | Interpretation |
|---------|-----:|----------------:|----------------|
| `Docker.raw` host allocation | 33 GB | Not directly deletable | Sparse VM disk containing all Docker data |
| Images | 9.77 GB | 71 MB | Nearly every image is referenced by a container |
| Containers | 244 MB | 244 MB | 27 stopped containers; removable without touching volumes |
| Local volumes | 18.47 GB | 244 MB reported unused | Mostly persistent app/database data; never auto-prune |
| Build cache | 3.50 GB | 2.91 GB | Best safe-reclaim opportunity |

Largest persistent volumes are `data-api_arango_data` (12.61 GB) and `data-api_redis_data` (3.07 GB). This is why a 33–35 GB `Docker.raw` does not imply that 33–35 GB is safe to clean. About 2.91 GB of build cache is currently reclaimable. A materially larger reduction requires the user to identify and explicitly select projects or persistent datasets that are no longer needed.

### 10.1 — Read-only Docker inventory

- [ ] Add `DockerStorageInventory` actor in `PareCore`; run only when the Docker daemon is reachable
- [ ] Parse `docker system df`, `docker buildx du`, resource lists, and inspect output into typed image, container, volume, and build-cache usage
- [ ] Report three distinct numbers: `Docker.raw` host allocation, Docker-managed usage, and Docker-reported reclaimable bytes
- [ ] For every volume, show exact size, name, named/anonymous kind, creation time, driver, labels, Compose project/service, and attached running or stopped containers
- [ ] Infer a human-readable purpose such as database, dependency cache, or application data from labels, mounts, and owning services; display “Unknown” rather than guessing when evidence is insufficient
- [ ] Show every image, stopped container, and build-cache record with size, last-used information, ownership clues, and active/in-use state
- [ ] Build resource relationships so the UI can explain why an image or volume is blocked by a container
- [ ] Handle Docker absent, daemon stopped, permission denied, command timeout, and unsupported output without failing the normal Pare scan
- [ ] Cache read-only results briefly and add a manual Refresh action

### 10.2 — Per-resource selection and safety model

- [ ] Add a dedicated Docker card in Disk or Maintenance; do not represent `Docker.raw` as a normal scan finding
- [ ] Present separate Build Cache, Images, Containers, and Volumes sections with a checkbox on each individually removable row
- [ ] Default every checkbox to off; provide no “Select all” across resource types and no one-click broad cleanup
- [ ] Show selected bytes per section and a deduplicated estimated total before cleanup
- [ ] Label reclaimable build-cache records `.safe`; label stopped containers and unused images `.review`
- [ ] Label every volume `.advanced` because it may contain irreplaceable database or application data
- [ ] Block selection for volumes attached to any running or stopped container; show the blocking containers instead of silently removing them
- [ ] Allow only unused volumes to be selected, require a second confirmation, and require the user to type the volume name when it is named or larger than 1 GB
- [ ] Never preselect, bulk-prune, force-remove, detach, stop, or cascade-delete another Docker resource
- [ ] Offer volume backup/export guidance before confirmation
- [ ] Show the exact resource names, command, and expected consequences in confirmation UI

### 10.3 — Scoped cleanup actions

- [ ] Remove `MaintenanceCatalog.dockerPrune` and the `docker system prune` runner path
- [ ] Remove selected build-cache records with Buildx ID filters; retain age and storage-budget shortcuts only as selection helpers
- [ ] Remove selected stopped containers by exact container ID, never with container prune
- [ ] Remove selected unused images by exact image ID, never with image prune
- [ ] Remove selected unused volumes one at a time with `docker volume rm <exact-name>`, without `--force`
- [ ] Validate every selected resource again immediately before execution; skip anything that became active or attached
- [ ] Continue after an isolated resource failure and report the failed item without widening the command scope
- [ ] Re-run Docker inventory after each action and report actual reclaimed bytes
- [ ] Re-measure allocated `Docker.raw` size after cleanup; explain that host compaction may lag Docker-reported deletion
- [ ] Record command, before/after totals, stdout/stderr, and result in Pare History
- [ ] Support cancellation and prevent concurrent Docker maintenance actions

### 10.4 — UX and guidance

- [ ] Add a stacked usage view for images, containers, volumes, and build cache, separating active, blocked, selectable, and selected bytes
- [ ] Add “Why is Docker.raw larger?” help that explains sparse allocation and never suggests deleting the file
- [ ] Highlight high-return, low-risk recommendations first (currently old build cache), but leave them unselected
- [ ] For each volume, show “What is this?” ownership evidence, mounts, attached containers, and the likely consequence of removal
- [ ] Add search and filters for reclaimable, in use, Compose project, resource type, age, and size
- [ ] Link to Docker Desktop disk-image settings for moving the disk or changing its limit; do not edit Docker Desktop settings directly
- [ ] Add empty, daemon-offline, low-space, partial-failure, and post-clean states

### 10.5 — Verification and acceptance

- [ ] Unit-test parsers with multiple Docker CLI versions and localized/changed whitespace fixtures
- [ ] Test that no generated command contains `system prune`, any resource-level `prune` except filtered Buildx cache removal, `--volumes`, volume force removal, or direct `Docker.raw` deletion
- [ ] Test active resources and volumes attached to stopped containers cannot be selected
- [ ] Test commands contain only exact IDs/names selected by the user and selection is empty by default
- [ ] Test volume size, labels, Compose ownership, mounts, attachment state, and unknown-purpose fallback
- [ ] Integration-test against a disposable Docker fixture with images, stopped/running containers, build cache, named volumes, and Compose labels
- [ ] Verify before/after accounting and History output
- [ ] Validate Docker Desktop on Intel and Apple Silicon plus macOS 13, 14, and 15
- [ ] Acceptance: a user can understand each resource, select only exact items to remove, see selected bytes and consequences, and verify the result without Pare ever running a broad prune

---

## Phase 11 — Scan Coverage Gaps

Defect list with file locations: [`docs/features/scan-coverage-gaps.md`](features/scan-coverage-gaps.md).

### 11.1 — Finding deduplication (C1)

- [ ] Deduplicate findings by canonical path in `ScanRunner` — `BrowserReviewDataRule:51` and `BrowserExtendedArtifactsRule:80` resolve to the same Chromium `IndexedDB` path and both are counted
- [ ] Define the tie-break when two rules claim one path: highest risk level wins, so `.review` is never downgraded to `.safe`
- [ ] Collapse parent/child overlap so a folder finding and a file finding inside it contribute once
- [ ] Test: two rules emitting one path produce one finding and one contribution to the total
- [ ] Test: the sum of finding sizes never exceeds the allocated size of the union of their paths
- [ ] Find which rules emit the JetBrains Copilot `native/<platform>` folder/file pairs, including the native-platform `darwin-x64` on Intel
- [ ] Re-measure the baseline with `RuleCatalog.all` (the 2026-09-21 figure used the developer profile)
- [ ] Do this before the rest of Phase 11 — every displayed total depends on it

### 11.2 — Project artifact recognition (C2)

- [ ] Add `.build`, `.swiftpm`, `.dart_tool`, `.angular`, `.svelte-kit`, `.vite`, `.expo`, `.serverless`, `.terraform` to `ScanPolicy.projectLocalArtifactDirectoryNames`
- [ ] Confirm `CleanupEngine.isReclaimableProjectArtifact` still demands project-root evidence for each new name (fail-closed)
- [ ] Decide risk level per name — build output that may hold committed release artifacts stays `.review`, like `dist` and `build`
- [ ] Test: a SwiftPM `.build` under a project root is a finding; the same directory name outside any root is not

### 11.3 — Project root discovery (C3, C4, C5)

- [ ] Add `package.json`, `pubspec.yaml`, `Package.resolved`, `composer.json` to `SpotlightQueryRunner.signalNames`
- [ ] Remove `.git` — Spotlight does not index hidden entries, so it never matches
- [ ] Add `/go/pkg/mod/`, `/.pub-cache/`, `/.cargo/registry/` to `ScanPolicy.projectDiscoveryExcludedPathComponents`; dependency caches carry manifest files and are already covered by the package-cache rules
- [ ] Prune roots matching the new exclusions from `project-roots.json` on first launch after the fix
- [ ] Replace the `lastDiscoveredAt == nil` guard in `ProjectRootDiscovery.discoverIfNeeded()` with a TTL (7 days)
- [ ] Add a manual refresh entry point so a new project can be picked up on demand
- [ ] Test: a project with only `package.json` is discovered; paths under a dependency cache are not

### 11.4 — AI agent directories (privacy-critical)

Read the classification in the gaps doc before writing any rule here.

- [ ] Add `ScanPolicy.aiConversationDataMarkers` and check it wherever `appStateSensitiveMarkers` is checked
- [ ] Cover `~/.local/share/opencode/storage`, `~/.local/share/opencode/opencode.db`, `~/.claude/projects`, `~/.codex/sessions`, `~/.codex/*.sqlite`, `~/.cache/github-copilot/project-context`, `~/.cache/github-copilot/project-index`
- [ ] Fail closed: a denied path stays denied even when an ancestor matches an allowed marker
- [ ] Never surface a denied path in the UI — these directory names encode the user's project list
- [ ] Extend `app-catalog.json` (category `ai`) with reconstructible children only, never a whole tool directory: `~/.config/opencode/node_modules`, `~/.cache/codex-runtimes/*/dependencies`, `~/.cache/kilo/{bin,node_modules}`, `~/.cache/hyperframes/{chrome,fonts}`, `~/.paseo/models`
- [ ] `~/.paseo/models` is `.review`, never `.safe`
- [ ] Survey `~/.codex` and `~/.gemini` children and classify each before any catalog entry — never add either as a whole directory
- [ ] Test: `~/.local/share/opencode/log` is a finding while `~/.local/share/opencode/storage` is not, at both scan and cleanup time

### 11.5 — Stale CLI versions (C9)

- [ ] New `StaleCLIVersionRule` for `~/.local/share/*/versions/` and `~/.local/share/*/cli/_versions/` — keep the live version, flag the rest
- [ ] Resolve the live version from a `current` symlink or the binary on `PATH`, never from mtime or version sort. See the layout table in the gaps doc (Devin, cursor-agent, ACLI)
- [ ] Include dot-prefixed version directories (cursor-agent renames superseded ones to `.2026.09.10-*`) and `_download` staging directories
- [ ] Follow the `JetBrainsStaleVersionRule` shape: `customScan` for sibling comparison, `.safe`, age gate via `ScanPolicy.effectiveAgeDate`
- [ ] Register in `RuleCatalog` (developer profile + `all`)
- [ ] Test: two versions flag exactly one; a single version flags nothing; the `current` target is never flagged even when older than a sibling

### 11.6 — Homebrew breadth (C6)

- [ ] Cover `Caskroom/<cask>/<version>` superseded versions — keep the linked version only
- [ ] Report `Library/Taps` as `.review`; removal is a re-clone, not a rebuild
- [ ] Resolve the prefix through `BrewRunner.homebrewPrefix()` rather than hardcoding `/opt/homebrew` (Intel uses `/usr/local`)
- [ ] Surface superseded `Cellar` kegs from `brew cleanup --dry-run` so they count in the scan total
- [ ] Prefer a `brew cleanup` Maintenance action over deleting prefix contents directly; kegs and cask versions never go through `CleanupEngine`
- [ ] Sub-attribute `go_cache` / `go_mod_cache` inside the Homebrew cache for build-from-source installs
- [ ] Test: no finding is produced when Homebrew is absent

### 11.7 — Large stale files (C7)

- [ ] New `LargeStaleFilesRule` with its own discovery threshold (default 500 MB); `largeFileThresholdBytes` (50 MB) stays a display filter
- [ ] Scope `~/Downloads`, `~/Desktop`, `~/Documents`, `~/Library/ScreenRecordings`; any extension; risk `.review`; 90-day age gate; never `.safe`
- [ ] Surface individual files with source-app attribution rather than folder rollups
- [ ] Test: a file over the threshold untouched for 100 days is flagged; the same file touched yesterday is not

### 11.8 — Daemon logs (C8)

- [ ] Extend log coverage beyond `~/Library/Logs` to user-daemon logs written into tool home directories
- [ ] Keep the existing 1-day minimum age gate
- [ ] Ensure log databases belonging to a session store are excluded by 11.4's deny-list

### 11.9 — Inactive project dependency trees (C10)

- [ ] Add a per-root inactivity signal: last commit date and newest mtime outside artifact/dependency directories
- [ ] Flag `node_modules`, `.venv`, `venv` as `.review` only when the root is inactive **and** a lockfile or manifest exists to rebuild it
- [ ] Inactivity gate is a user setting, default 90 days
- [ ] Show the lockfile and uncommitted-change count on the finding; changes do not block
- [ ] Test: an active root's `node_modules` is never a finding; an inactive root without a lockfile is never a finding

### 11.10 — Downloaded ML models (C11)

- [ ] Cover `~/.cache/huggingface/hub`, `~/Library/Application Support/tts`, `~/.rembg` as `.review`, one finding per model
- [ ] Attribute each model to consuming projects by searching project roots for the model identifier; show "no consumer found" explicitly
- [ ] Never `.safe` — redownload can be multiple GB

### 11.11 — Abandoned downloads and updater payloads (C12)

- [ ] `.safe` for `*.tmp-*`, `*.partial`, `*.download` older than 1 day with no open handle
- [ ] Flag Electron/Squirrel updater payloads whose version is below the installed bundle's `CFBundleShortVersionString`
- [ ] Extend `InstallerFileRule` to `.tar.gz`/`.tgz` archives whose name matches an installed tool
- [ ] Test: a `.tmp` file currently open by a process is not flagged

### 11.12 — App bundles outside /Applications (C13)

- [ ] Bundle-aware walk of `~/Documents`, `~/Downloads`, `~/Desktop` for `.app` over 500 MB
- [ ] Report last-used date from `kMDItemLastUsedDate`; `.review` only
- [ ] Test: a `.app` bundle counts as one finding with its total size, not thousands of files

### 11.13 — Growth tracking and alerts (C14)

The request behind this is "stop making me check the disk". This sub-phase matters more than any single rule.

- [ ] Persist a per-directory size index at the end of each scan
- [ ] Show delta since the previous scan per top-level directory and per rule, sorted by growth
- [ ] Track refill rate per cache rule; a cache that regrows within 24 h is labelled working set and demoted in cleanup suggestions
- [ ] Add an "unaccounted" row: volume used minus scanned total, so growth in FDA-blocked areas is still visible
- [ ] Scheduled background scan (LaunchAgent) with a free-space threshold notification, default 20 GB
- [ ] Test: two scans with a directory grown by 1 GB report exactly that delta

### 11.14 — Docker VM disk visibility (C15)

- [ ] Detect-only `.advanced` finding for `…/vms/0/data/Docker.raw`: allocated size, apparent size beside it, labelled sparse
- [ ] Excluded from reclaimable totals; `isDockerNeverDeletePath` and the `CleanupEngine` block unchanged
- [ ] Attach the prune / Phase 10 guidance to the finding
- [ ] Update `DockerStorageRule` doc comment, `docs/features/docker-safety.md` and CLAUDE.md, which currently say the VM disk is never a finding
- [ ] Test: the finding exists, is `.advanced`, reports allocated size, and `CleanupEngine` still refuses it

### 11.15 — Local VM and Kubernetes disks (C16)

- [ ] New rule for `~/.minikube`, `~/.lima`, `~/.colima`, `~/.vagrant.d`, `~/.local/share/containers`, Parallels/VMware/UTM/VirtualBox images
- [ ] VM disks `.advanced` with allocated size; preloaded image tarballs for unused Kubernetes versions `.review`
- [ ] Show last-used date; 90 days untouched is the signal
- [ ] Test: a sparse disk image reports allocated, not apparent, size

### 11.16 — Version-manager installs (C17)

- [ ] Flag `asdf`/`pyenv`/`rbenv`/`nvm`/`fvm`/`rustup` versions that are neither the global default nor pinned by any discovered project root
- [ ] `.review` only; depends on 11.3 for a complete root set
- [ ] Test: a version pinned by one project's `.tool-versions` is never flagged

### 11.17 — Duplicate clones (C18)

- [ ] Group repos under discovered roots by `origin` remote; report groups of two or more
- [ ] Detect-only: each clone's `.git` size, last commit, dirty state

### 11.18 — Database dumps and loose archives (C19)

- [ ] `.review` for `*.rdb`, `*.aof`, `*.sql`, `*.dump` over 100 MB in project trees and at the top level of `~`
- [ ] `.review` for an archive whose extracted folder of the same name sits beside it
- [ ] Test: an archive with no sibling folder is not flagged

### 11.19 — Verification

- [ ] Confirm a scan report contains no duplicate paths
- [ ] `make run-app` and verify no AI conversation path appears anywhere in the UI
- [ ] Record the before/after reclaimable total for each sub-phase in the PR description

---

## Always-On (every phase)

- [ ] `make build` passes before any PR
- [ ] `make test` passes; coverage ≥ 80%
- [ ] `make run-app` — manual smoke test of changed feature
- [ ] `gitnexus_impact` run before editing any symbol
- [ ] `gitnexus_detect_changes` run before committing
- [ ] Update roadmap artifact after completing each phase
