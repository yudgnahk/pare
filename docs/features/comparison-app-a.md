# Pare vs App A — Feature Comparison

**Updated:** 2026-07-20 (post Phases 1–8 + Leave Homebrew)

## Alias definitions (internal only)

| Alias | Archetype |
|-------|-----------|
| **App A** | Open-source, **CLI/TUI-first** macOS cleaner. Scriptable path lists, permanent delete in many flows, power-user oriented. |
| **App B** | Commercial **multi-module GUI care suite** (cleanup + protection + performance + clutter). See [comparison-app-b.md](./comparison-app-b.md). |
| **Pare** | Native SwiftUI + PareCore. Risk-graded reclaim, Trash + undo, developer-depth focus. |

Do **not** use third-party product names in public docs, issues, or marketing. Use these aliases only.

---

## Positioning

| | **Pare** | **App A** |
|--|----------|-----------|
| Form factor | Native macOS SwiftUI app (+ CLI diagnostic) | CLI / TUI first |
| Safety model | `safe` / `review` / `advanced` + Trash + undo transactions | Mostly permanent delete; dry-run flags |
| Audience | Everyday users + developers who want a GUI | Power users comfortable in Terminal |
| Philosophy | Surgical reclaim with explainability | Broad scripted coverage, fast for experts |

**Status legend:** `Done` · `Partial` · `Open` · `Won’t do` (out of Pare positioning)

---

## Capability matrix

| Capability | App A | Pare | Status | Notes |
|------------|-------|------|--------|-------|
| User / system caches, logs, temp | Clean command | Rules: UserCaches, Logs, Temp | **Done** | Age gates + ScanPolicy |
| Browser caches | yes | BrowserCachesRule | **Done** | |
| Browser extended (GPU, session, IndexedDB…) | yes | BrowserExtendedArtifactsRule | **Done** | |
| Browser personal data (history, cookies…) | yes | BrowserReviewDataRule (`.review`) | **Done** | Conservative risk |
| AI tool caches | yes | AIToolCachesRule | **Done** | Copilot, Cursor, Claude, Windsurf, Continue, Tabnine |
| Homebrew download cache | yes | HomebrewCacheRule | **Done** | |
| Package manager caches (npm, pip, cargo, go…) | partial | PackageManager + Python/Ruby/Java/Rust/Go rules | **Done** | Breadth is a Pare strength |
| Wrong-platform binaries | no / limited | WrongPlatformBinariesRule | **Done** | Pare advantage |
| Installer files (.dmg/.pkg/…) | Installer finder | InstallerFileRule | **Done** | |
| Project artifact purge | Project purge command | ProjectArtifactRule + ProjectArtifactsRule + Spotlight discovery | **Done** | |
| App uninstall + leftovers | Uninstall command | App Manager + AppUninstaller | **Done** | Depth may still lag App A’s deep leftover lists |
| Homebrew-managed uninstall | yes | Detects cask → prefers brew | **Done** | |
| Stale / duplicate app versions | no | StaleAppVersionRule + JetBrainsStaleVersionRule | **Done** | Pare advantage |
| Docker reclaim | prune guidance | DockerStorageRule (advanced) + Maintenance prune | **Partial** | Never delete Docker.raw; prune without `--volumes` |
| iOS backups | varies | MobileSyncBackupsRule | **Done** | |
| Orphaned LaunchAgents | varies | OrphanedLaunchAgentsRule | **Done** | |
| Productivity app caches | partial | ProductivityCachesRule | **Done** | Slack, Zoom, Drive, Teams… |
| System optimizer tasks | Optimize command | Maintenance tab (DNS, LS, Finder, SQLite, Docker) | **Partial** | No sudo-heavy broken-pref repair / swap tricks |
| Disk analyzer drill-down | Analyze TUI | Disk tab tree | **Partial** | No aging heatmap; no cross-highlight with scan findings |
| Real-time system monitor | Status command | — | **Won’t do** (v1) | Out of disk-cleaner positioning |
| Operation history | History command | History tab + CleanupTransaction JSON + export | **Done** | |
| Path exclusions | whitelist | ExclusionList UI | **Done** | |
| Category-level whitelist | yes | path-only exclusions | **Open** | |
| Interactive CLI clean | primary UX | `pare-cli` diagnostic only | **Partial** | App is primary |
| Migrate apps → Homebrew | no | Migrate + `--adopt` | **Done** | Pare advantage |
| Leave Homebrew (keep app) | no | CaskLeaveHomebrew | **Done** | Pare advantage |
| Risk levels + hard-block advanced | no | ScanPolicy + CleanupEngine | **Done** | Pare advantage |
| Trash + undo | limited | Always Trash + transactions | **Done** | Pare advantage |
| Per-app “By Tool” attribution | no | ScanReportAnnotator | **Done** | Pare advantage |
| Incremental scan cache | no | CachedFileTraversal | **Done** | Pare advantage |
| Signed / notarized distribution | N/A (source/package install) | Phase 9 scripts; cert still open | **Partial** | US-4 |

---

## Former “App A has / we don’t” list — current truth

| # | Old claim | 2026-07 status |
|---|-----------|----------------|
| 1 | Full app uninstaller | **Done** — App Manager |
| 2 | System optimizer | **Partial** — Maintenance (non-sudo subset) |
| 3 | Real-time monitor | **Won’t do** for v1 |
| 4 | Disk analyzer | **Partial** — Disk tab |
| 5 | Project artifact purge | **Done** |
| 6 | Installer finder | **Done** |
| 7 | AI caches | **Done** |
| 8 | Homebrew cache | **Done** |
| 9 | Browser extended | **Done** |
| 10 | Audit log UI | **Done** — History |
| 11 | Category whitelist | **Open** |

---

## Where App A is still ahead

1. **CLI fluency** — one binary, scriptable, no GUI required  
2. **Leftover uninstall depth** — more obscure residual categories  
3. **Aggressive optimize** — sudo maintenance scripts Pare deliberately avoids  
4. **Category whitelist** — “never touch this class of path” without enumerating paths  
5. **Zero install friction** — package/source install; Pare still needs notarized DMG for non-devs  

## Where Pare is ahead

1. **Native GUI** with explainable findings  
2. **Risk grading + advanced hard-block**  
3. **Trash + undo transactions**  
4. **By Tool rollups** and developer ecosystem breadth  
5. **Homebrew lifecycle** — adopt, upgrade policy, Leave Homebrew  
6. **Docker safety** — never treat `Docker.raw` as a cache  
7. **Stale app version detection** (generic + JetBrains)  
8. **Wrong-platform** folder rollups under editors/package trees  

---

## Implication for roadmap

Closing more App A CLI parity is **low ROI** unless a row above is still `Open`/`Partial` *and* matches Pare’s “safe reclaim” brand. Prefer:

- Shipping (notarization)  
- Trust UX (permissions, empty-scan coaching)  
- Leftover depth / category exclude only if uninstall feedback demands it  

See [ranked backlog](../reviews/2026-07-20-competitive-gaps.md).
