# Phase 8 — Productivity & System Health

Three independent additions that complete Pare's coverage of the everyday-Mac-user surface area: cloud and collaboration app caches, orphaned launch agents from uninstalled apps, and a Maintenance tab for one-shot system repair actions.

## Goals

- Clean Slack, Zoom, Google Drive, Office, and similar productivity tool caches
- Surface launch agent plists that reference deleted binaries (post-uninstall leftovers)
- Give users a safe, GUI-driven way to run system maintenance tasks (DNS flush, LaunchServices rebuild, etc.) without opening Terminal

---

## Part 1 — Cloud & Productivity App Cleanup

### ProductivityCachesRule

Extend `app-catalog.json` with a new `"productivity"` category (same pattern as the existing `"ai"` category used by `AIToolCachesRule`). The rule reads the catalog and scans each entry's target paths.

**app-catalog.json entries to add:**

| App | Safe cache paths | Review paths |
|-----|-----------------|--------------|
| Slack | `~/Library/Application Support/Slack/Cache/`, `~/Library/Application Support/Slack/Service Worker/CacheStorage/`, `~/Library/Application Support/Slack/Code Cache/` | — |
| Zoom | `~/Library/Application Support/zoom.us/Cache/`, `~/Library/Application Support/zoom.us/data/` | `~/Documents/Zoom/` (cloud recordings — user may want to keep) |
| Google Drive | `~/Library/Application Support/Google/DriveFS/` (FS cache) | — |
| Dropbox | `~/Library/Application Support/Dropbox/logs/`, `~/.dropbox/logs/` | — |
| Microsoft Teams | `~/Library/Application Support/Microsoft/Teams/Cache/`, `Application Cache/`, `Code Cache/` | — |
| OneDrive | `~/Library/Containers/com.microsoft.OneDrive-mac/Data/Library/Caches/` | — |
| Word | `~/Library/Containers/com.microsoft.Word/Data/Library/Caches/` | — |
| Excel | `~/Library/Containers/com.microsoft.Excel/Data/Library/Caches/` | — |
| PowerPoint | `~/Library/Containers/com.microsoft.Powerpoint/Data/Library/Caches/` | — |
| Office (shared) | `~/Library/Group Containers/UBF8T346G9.Office/TemporaryItems/` | — |
| Spotify | `~/Library/Application Support/Spotify/PersistentCache/` | — |

**Rule properties:**
- Safe entries: `.safe`, confidence 0.95
- Review entries (Zoom recordings, etc.): `.review`, confidence 0.88
- Category: new `productivityCaches` category (display name: "Productivity Apps")
- Skip gracefully if the target directory doesn't exist (app not installed)

---

## Part 2 — Orphaned Launch Agents

When an app is uninstalled by dragging it to Trash (rather than using Pare's App Manager), any `LaunchAgent` plist files it installed are left behind. These plists reference binaries that no longer exist. launchd will attempt to start them at login and log errors repeatedly.

### OrphanedLaunchAgentsRule

Uses `customScan`.

**Scan location:**
```
~/Library/LaunchAgents/*.plist
```

**Per-plist check:**

1. Parse the plist with `PropertyListSerialization.propertyList(from:options:format:)`.
2. Extract the binary path:
   - `Program` key (string) if present, OR
   - `ProgramArguments` array — first element is the binary path.
3. Expand `~` and resolve any environment variable references. If the path still contains unexpanded variables (e.g. `$(TMPDIR)`) after expansion, **skip this plist** — can't reliably verify.
4. Call `FileManager.default.fileExists(atPath: binaryPath)`.
5. If the binary **does not exist** → emit a `.review` finding for the plist file.

**Finding properties:**
- Path: the `.plist` file
- Category: existing `applicationSupport` or a new `launchAgents` sub-category
- Risk: `.review` (safe for most users to delete, but a power user may have intentionally disabled an agent)
- Reason: `"References missing binary: /Applications/SomeApp.app/Contents/MacOS/Helper"`
- Confidence: 0.85
- Minimum age gate: 14 days on the plist itself (skip recently-installed agents that may be legitimately absent during first-run setup)

**Do not scan:**
- `/Library/LaunchAgents/` (system-wide, requires admin, higher false-positive risk — defer to a future phase)
- `/Library/LaunchDaemons/` (same reason)
- Plists with `Disabled = true` set — they are already inert; don't surface them as a problem

**Integration with App Manager:**

`AppUninstaller` already removes `~/Library/LaunchAgents/*{bundleID}*.plist` as part of a clean uninstall. `OrphanedLaunchAgentsRule` catches the cases where the user uninstalled outside Pare (drag-to-Trash, third-party uninstaller, etc.).

---

## Part 3 — Maintenance Tab

A new fifth tab for one-shot system repair actions. These are not file deletions — they fix system state and are complementary to Pare's cleanup capabilities.

### Data Model

```swift
struct MaintenanceAction: Identifiable, Sendable {
    let id: String
    let title: String
    let description: String          // what it does and when to use it
    let estimatedSeconds: Int        // shown as "~Ns" to the user
    let requiresRunningApp: String?  // e.g. "com.docker.docker" — show only if running
    let run: @Sendable () async throws -> String  // returns result summary string
}
```

```swift
@MainActor
final class MaintenanceViewModel: ObservableObject {
    @Published var actions: [MaintenanceAction] = []
    @Published var runningID: String? = nil
    @Published var results: [String: MaintenanceResult] = [:]  // id → .success(summary) | .failure(Error)
}
```

### Initial Action Set (no sudo required)

All actions run via `Process` (NSTask equivalent in Swift). No privileged helper required for this initial set.

---

**1. Flush DNS Cache**
- Command: `dscacheutil -flushcache` followed by `killall -HUP mDNSResponder`
- When to use: "A website isn't loading even though it's accessible elsewhere. Clears the DNS resolver cache."
- Estimated time: ~1 second
- Safe to run any time

---

**2. Rebuild Launch Services Database**
- Binary: `/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister`
- Arguments: `-kill -r -domain local -domain system -domain user`
- When to use: "Files opening in the wrong app, or 'Open With' shows duplicate entries. Rebuilds the system's app-to-file-type mapping."
- Estimated time: 15–45 seconds (warn the user)
- Safe to run any time; Finder may briefly restart

---

**3. Restart Finder**
- Command: `killall Finder`
- When to use: "Finder is not showing recently added files, or the desktop is unresponsive."
- Estimated time: ~2 seconds
- Finder restarts automatically after being killed

---

**4. Vacuum Mail Index**
- Path: `~/Library/Mail/V*/MailData/Envelope Index.sqlite`
- Command: `sqlite3 "<path>" "VACUUM; ANALYZE;"`
- When to use: "Mail is slow to search or load. Compacts the message index database."
- Estimated time: 5–30 seconds depending on mailbox size
- Requires Mail to be quit first — check with `NSRunningApplication` and prompt if open

---

**5. Vacuum Safari History**
- Path: `~/Library/Safari/History.db`
- Command: `sqlite3 "<path>" "VACUUM; ANALYZE;"`
- When to use: "Safari history search is slow. Compacts the history database."
- Estimated time: 2–10 seconds
- Requires Safari to be quit first

---

**6. Docker System Prune** *(conditional)*
- Command: `docker system prune -f`
- When to use: "Remove unused Docker containers, networks, and build cache. Does not remove named volumes."
- Estimated time: 5–60 seconds
- Only shown if Docker Desktop is installed (`/usr/local/bin/docker` or `/opt/homebrew/bin/docker` exists) AND Docker is currently running (checked via `docker info` with a 3-second timeout)
- Output includes bytes freed; surface this as the result summary

---

### SwiftUI Structure

New tab: icon `wrench.and.screwdriver`, label "Maintenance".

```
PareApp/Views/
  Maintenance/
    MaintenanceView.swift           # Tab root — grid of action cards
    MaintenanceActionCard.swift     # Single card: title, description, run button, result
    MaintenanceRunSheet.swift       # Modal during long-running action — streams stdout/stderr
```

Each `MaintenanceActionCard`:
- Title + description text
- Estimated time badge ("~15s")
- "Run" button (disabled while another action is running)
- State machine: idle → running (spinner + cancel) → success (checkmark + result string) → error (message)
- Idle after 30 seconds so the user can re-run

**Running state** for actions > 5 seconds: show a `MaintenanceRunSheet` modal with a scrollable log of stdout/stderr output. For short actions (< 5 seconds), show inline progress without a modal.

---

## Architecture

```
Sources/PareCore/
  Rules/
    OrphanedLaunchAgentsRule.swift
    ProductivityCachesRule.swift    # reads app-catalog.json "productivity" category

Sources/PareApp/
  Views/
    Maintenance/
      MaintenanceView.swift
      MaintenanceActionCard.swift
      MaintenanceRunSheet.swift
  ViewModels/
    MaintenanceViewModel.swift

Resources/
  app-catalog.json                 # add "productivity" entries
```

---

## Test Plan

| Test | What it verifies |
|------|-----------------|
| `OrphanedLaunchAgentsRuleTests` — missing binary flagged | Plist pointing to absent binary emits `.review` |
| `OrphanedLaunchAgentsRuleTests` — present binary not flagged | Plist with valid binary emits nothing |
| `OrphanedLaunchAgentsRuleTests` — variable in path skipped | `$(TMPDIR)/...` path produces no finding |
| `OrphanedLaunchAgentsRuleTests` — Disabled plist skipped | `Disabled = true` plist produces no finding |
| `OrphanedLaunchAgentsRuleTests` — age gate | Plist < 14 days old not flagged |
| `ProductivityCachesRuleTests` — absent app skipped | Rule produces no findings when Slack not installed |
| `ProductivityCachesRuleTests` — Zoom recordings are review | `~/Documents/Zoom/` finding is `.review` not `.safe` |
| `MaintenanceViewModelTests` — concurrent run blocked | Starting action while one runs does not start a second |
| `MaintenanceViewModelTests` — Docker action hidden | Action absent when Docker not installed |
