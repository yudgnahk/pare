# Pare gap analysis — UI, scan coverage, cleanup UX

**Date:** 2026-07-13  
**Branch:** `fix/ui-adaptive-layout-macos-polish`  
**Sources:** live `app-a clean --dry-run`, `pare-cli --profile developer`, codebase review, local disk inspection  

This document answers six questions raised after the App-B-style UI work. Each section: **finding → root cause → recommendation**.

---

## Executive summary

| # | Topic | Status | Priority |
|---|--------|--------|----------|
| 1 | Text zoom breaks layouts | Confirmed — fixed widths don’t flex enough | P1 |
| 2 | Chrome reclaimable ≪ App B / App A | Confirmed — age gate + missing Service Worker / bulk cache | P0 |
| 3 | Local Storage — too risky to auto-delete? | **Yes — keep out of Quick Clean** | Policy |
| 4 | vs `app-a clean --dry-run` | App A ~5.4 GB “clean” buckets; Pare ~9.2 GB (more project junk) — different product shape | P0/P1 |
| 5 | Stale DataGrip versions in list | Only **one** DataGrip app + one versioned AS folder — nothing stale to flag | OK / improve |
| 6 | Select files to clean | Missing — all-or-nothing Quick/Deep Clean | P0 product |
| 7 | Scan animation (3 steps) | Missing — ring spinner only | P1 polish |

---

## 1. Layouts break when text size increases

### Finding
⌘+ / large-window scale multiplies fonts and **some** control sizes, but many rows still use rigid column widths, min-widths, and single-line HStacks. At 150–200% zoom, headers and tables overflow or collide.

### Likely break points (code)

| Area | Issue |
|------|--------|
| Apps / Homebrew tables | Fixed `scale.colVersion`, `colDate`, `colActions` grow slower than labels; long names + Update button need more horizontal room than 13" width |
| `PrimaryActionButton` | `primaryMinWidth` + padded height; FlowLayout wraps but filter bars stay single-row HStack |
| Filter bars | Search field `maxWidth: 280` + toggles + sort menu don’t reflow reliably at large type |
| Metric tiles | Adaptive grid OK; large value fonts can clip with `lineLimit(1)` |
| Sidebar | Fixed `sidebarWidth: 232` — labels wrap poorly at high zoom |
| Sheets | Fixed ideal widths; content can overflow |

### Solutions

1. **Layout budget at zoom**  
   - Increase `sidebarWidth` with `displayScale` (e.g. `220 * spacingFactor`).  
   - Tables: prefer **flexible columns** + hide secondary columns earlier (already partial for compact); add **horizontal scroll only for table body**, not dual-axis chaos.

2. **Typography-aware controls**  
   - Stop hard-coding row heights; use `scale.space()` everywhere for vertical padding.  
   - Buttons: drop rigid `primaryMinWidth` when title is long; allow multi-line or icon-only below a width threshold.

3. **QA matrix**  
   - Test at zoom 100% / 130% / 160% / 200% × window widths 980 / 1200 / fullscreen.  
   - Checklist: Smart Scan results, Apps filters, Homebrew tabs, Maintenance grid, Settings.

4. **Optional**  
   - Cap automatic `extraLargeBase` (1.55×) slightly and push more size into **user zoom** so layouts stay designed for ≤1.3× auto scale.

**Implementation effort:** ~1–2 days UI hardening, no PareCore changes.

---

## 2. Chrome reclaimable space vs App B / App A

### Local snapshot (this machine)

| Path | Size | App A | Pare today |
|------|------|------|------------|
| `~/Library/Caches/Google/Chrome` | **~596–625 MB** | Yes (dry-run) | **~0** (not in top findings) |
| `…/Default/Service Worker` | **~455 MB** (+ other profiles ~50 MB) | Yes (~419+31 MB) | **Not scanned** |
| `…/Default/Local Storage` | **~36 MB** | Not emphasized | **Yes — REVIEW** (~38 MB) |
| `…/Default/IndexedDB` | **~187 MB** | Not in dry list as such | Review path, **30-day age gate** may hide |
| GPU / shader caches | small | partial | GrShaderCache **SAFE** (~0.5 MB) |
| App Support Chrome total | **~2.5 GB** | mixed / skip if Chrome running | mostly not flagged |

**Pare baseline browser total on this Mac:** ~38 MB (almost all Local Storage).  
**App A browser slice:** hundreds of MB to **~1 GB+** (Cache + Service Worker), when Chrome isn’t blocking.

### Why Pare under-reports Chrome

1. **3-day minimum age on browser / user caches** (`ScanPolicy.defaultCacheMinAgeSeconds`)  
   Sample of Chrome Cache files today: **all recent (< 3 days)**. Active browsers never surface disk cache under the age gate — App B/App A still list them.

2. **`BrowserCachesRule` only walks `~/Library/Caches/…`**  
   Large Chromium weight lives under **Application Support** (`Service Worker`, `Code Cache` variants, `GPUCache`, `File System`, etc.).

3. **`BrowserExtendedArtifactsRule`** covers Sessions / IndexedDB / Local Storage as **REVIEW**, with cache age (3 days) — not Service Worker.

4. **`BrowserReviewDataRule`** (history, cookies, IndexedDB, form data) uses a **30-day** age gate — deliberately conservative; recent personal data is hidden.

5. **Running Chrome** — App A skips some App Support cleanup while Chrome is open; Pare doesn’t special-case this yet.

### Local Storage — should we delete it?

**Recommendation: do not auto-delete; keep REVIEW or drop from default clean.**

| Content | Risk |
|---------|------|
| Site-specific offline data, PWA state | Data loss (drafts, offline apps) |
| Session / auth tokens in web apps | **Logout**, broken SSO, lost “remember me” |
| Not the same as macOS Keychain passwords | Still sensitive **credentials-adjacent** |

App B often pushes **Cache + Service Worker** harder than Local Storage. Pare currently **highlights Local Storage** (review) while **missing the safe-ish bulk cache** — product message is inverted vs industry tools.

### Solutions (scan coverage)

| Priority | Change | Risk level | Notes |
|----------|--------|------------|--------|
| P0 | Exempt **browser disk cache** under `Library/Caches/*Chrome*` from age gate **or** use 0–1 day | SAFE | Matches App A/App B |
| P0 | Add **Service Worker** dirs under Chromium profiles as SAFE (regenerable) | SAFE | Large win (~450 MB here) |
| P1 | Add `GPUCache`, `Code Cache`, `DawnWebGPUCache` under App Support | SAFE | Medium win |
| P1 | Multi-profile paths (`Profile 1`, `Profile 3`, …) not only `Default` | — | App A lists multi-profile SW |
| P2 | Keep Local Storage / Cookies / History as **REVIEW**, default **unchecked** in selective clean | REVIEW | Never Quick Clean |
| P2 | Warn if browser is running before cleaning App Support paths | UX | Like App A skip |

**Policy statement for product docs:**

> **Quick Clean never touches Local Storage, cookies, or passwords.**  
> Those paths are review-only (or not offered).  
> Prefer Service Worker + HTTP cache for reclaimable browser space.

---

## 3. Pare vs `app-a clean --dry-run` (this machine)

### Headlines

| Tool | “Potential” | Character |
|------|-------------|-----------|
| **App A** `app-a clean --dry-run` | **~5.36 GB**, 183 items, 37 categories | System + app caches, browsers, npm, Homebrew; **whitelists** JetBrains AS, Gradle, HuggingFace, etc. |
| **Pare** `pare-cli --profile developer` | **~9.2 GB** | Strong on **project artifacts** + package caches; weak on **live browser cache** & some AI/npx caches |

Numbers are not apples-to-apples: App A skips whitelisted paths Pare may still report; Pare counts large project `node_modules` / `.venv` / `target` that App A leaves to `app-a purge`.

### Where App A finds space Pare misses (or under-counts)

| App A item | Size (approx.) | Pare gap |
|-----------|----------------|----------|
| User app cache (broad `Library/Caches`) | **1.61 GB** | Age gates + browser exclusion + only “safe” markers |
| Chrome cache | **625 MB** | Age gate (all files fresh) |
| Chrome Service Worker | **~450 MB+** | Not in rules |
| npm `_npx` | **1.18 GB** | Only `_cacache` targeted |
| OpenCode cache | **~864 MB** | Not in AI rules (or incomplete) |
| Media analysis / Help / Maps / parsecd | tens of MB | Partial user-cache coverage |
| Trash empty | — | Not a scan finding (could be Maintenance) |

### Where Pare finds space App A soft-pedals

| Pare item | Size (approx.) | Note |
|-----------|----------------|------|
| Project artifacts (`.cache`, `node_modules`, `target`, `.venv`) | **~5.2 GB** | App A: `app-a purge` / large-file hints |
| `go-build` + module cache | **~900 MB** | App A developer section partial |
| JetBrains plugins / wrong-platform stubs | **GBs review** | App A **whitelists** JetBrains Application Support |
| Cargo registry | large | Overlap with App A |

### Optimization backlog (ordered)

1. **Browser SAFE pack** — Cache (no/short age) + Service Worker + multi-profile.  
2. **npm `_npx`** as SAFE package cache (with optional protect for active packages).  
3. **AI tool caches** — OpenCode, Codex cache dirs (not credentials).  
4. **Broader user cache** — mediaanalysisd, helpd, wallpaper (careful with Spotlight / FontRegistry).  
5. **pnpm store** — advisory only or dedicated “store prune” action (App A shows as large-file clue, not auto).  
6. **Directory-level findings** for `Library/Caches/Google/Chrome` instead of millions of tiny files (performance + UI).  
7. **Parity report** CI script: run App A dry-run JSON vs Pare report, diff top paths.

---

## 4. Stale versions (e.g. DataGrip)

### Finding (this machine)

| Location | Present |
|----------|---------|
| `/Applications/DataGrip.app` | One bundle, version **2026.1.4** |
| `~/Library/Application Support/JetBrains/DataGrip2026.1` | One versioned folder (~455 MB) |
| `~/Library/Application Support/JetBrains/Datagrip` | Extra unversioned folder name |

**No second DataGrip.app** and **no second `DataGrip20xx.y` folder** →  
`StaleAppVersionRule` and `JetBrainsStaleVersionRule` correctly produce **no “superseded DataGrip” finding**.

What *does* show for DataGrip: large **REVIEW** plugin jars under the **current** version (ml-llm, etc.) via `JetBrainsReviewRequiredRule` — not “stale version,” but “review plugin data.”

### Why users think “stale” is missing

- Toolbox / multiple apps: `DataGrip 2024.3.app` next to `DataGrip.app` → then StaleAppVersionRule would flag.  
- Multiple AS folders: `DataGrip2024.3` + `DataGrip2026.1` with **90-day age** on older → JetBrainsStaleVersionRule.  
- Unversioned `Datagrip` folder is **not** parsed by version regex → never compared.

### Solutions

1. **Document** in UI: “Stale versions appear only when 2+ installs/versions exist.”  
2. **Parse unversioned JetBrains product folders** as lowest priority when a versioned sibling exists.  
3. **Surface “current IDE plugin bloat”** as its own category label (not “stale”) so users aren’t confused.  
4. **Apps tab** already has inventory; link “Open App Manager” for version comparison of `.app` bundles.

---

## 5. Select files to clean — better UI

### Current UX

- **Quick Clean** = all `.safe` findings.  
- **Deep Clean** = all `.safe` + `.review`.  
- No per-file / per-category selection. Confirmation sheets only show counts.

### Goals

- User trust (especially REVIEW).  
- Avoid deleting Local Storage / history by accident.  
- Still allow one-click “safe only” for power users.

### Proposed UX: **Review & Clean** (primary path)

```
┌ Smart Scan results ─────────────────────────────────────────┐
│  Reclaimable  9.2 GB   [ Safe 6.1 · Review 3.1 · Advanced — ]│
│  [ Clean selected (2.4 GB) ]  [ Select all Safe ]            │
├ Categories ──────────────────────────────────────────────────┤
│ ☑ Project Artifacts     5.2 GB   Safe    [ details ▸ ]      │
│ ☑ Dev package caches    3.1 GB   Safe    …                  │
│ ☐ Browser Local Storage  36 MB   Review  ⚠ credentials      │
│ ☐ Chrome Service Worker 450 MB   Safe    (when implemented) │
├ Expanded category: Project Artifacts ───────────────────────┤
│ ☑ path…/.cache     1.45 GB                                  │
│ ☑ path…/target     969 MB                                   │
│ ☐ path…/node_modules 610 MB   (optional caution)            │
└─────────────────────────────────────────────────────────────┘
```

### Interaction model

| Control | Behavior |
|---------|----------|
| Default selection | All **SAFE** checked; all **REVIEW** unchecked; **ADVANCED** not selectable |
| Category checkbox | Toggles all items in category (respecting risk defaults) |
| File checkbox | Overrides category |
| Risk filter chips | Safe / Review / All |
| Primary CTA | **Clean selected (N · size)** → confirm sheet listing paths + sizes |
| Secondary | “Select all safe” / “Clear selection” |
| Advanced | Shown as advisory only (Docker VM, etc.) |

### Data model (PareApp)

```text
selectedFindingIDs: Set<UUID>   // or path hash
// derived from latestFindings after scan
// CleanupEngine.clean(findings: filtered)
```

Reuse `CleanupEngine.clean` with an explicit list (already generic); stop wiring only “all safe” / “all safe+review.”

### Navigation

- Post-scan **results** become the selection workspace (not a separate tab).  
- Optional **“Review Review items”** mode for Deep Clean equivalent.

### Effort

- ViewModel selection state + filter: **0.5–1 day**  
- UI rows with checkboxes + category headers: **1–2 days**  
- Confirm sheet + undo still via existing transactions: **0.5 day**  
- Tests for selection invariants: **0.5 day**

---

## 6. Scan animation — three steps (App-B-like)

### Current state

- Idle: SF Symbol hero + ring “Scan”  
- Scanning: ring rotation + “Scanning your Mac…”  
- Done: hard cut to results (no staged story)

### Proposed **3-step scan theater** (honest, not fake progress)

App B cycles icons/copy while working. Pare should map steps to **real rule batches** so the UI isn’t lying.

| Step | UI copy | Icon (SF Symbol) | Rule groups (approx.) |
|------|---------|------------------|------------------------|
| **1 · System** | “Scanning system & app caches…” | `internaldrive` / `folder.fill` | UserCaches, Temporary, Logs, Productivity, LaunchAgents |
| **2 · Apps & browsers** | “Scanning browsers & applications…” | `globe` / `app.badge` | Browser*, Installer, StaleApp, Mobile backups |
| **3 · Developer** | “Scanning developer tools & projects…” | `chevron.left.forwardslash.chevron.right` | Xcode, JetBrains, npm, AI, Docker hint, Project artifacts |

**Progress model**

- `ScanRunner` reports `currentRuleIndex / totalRules` (or batch id) via callback / `AsyncStream`.  
- Hero shows: step title, subtle icon crossfade, determinate bar = rules completed.  
- Optional micro-copy under bar: last completed rule title (debug-friendly, can hide later).

**Motion**

- Icon: opacity + scale 0.96→1, 0.35s easeOut, no layout thrash.  
- Ring: keep spinner until step 3 completes.  
- On finish: short success checkmark (~0.4s) then transition to results **without** staggered list animation (already removed for scroll perf).

**Do not** invent random percentages unrelated to work (users notice).

### Effort

- ScanRunner progress hook: **0.5–1 day**  
- Hero step UI: **0.5–1 day**  
- Total: **~1–2 days**

---

## 7. Cross-cutting product recommendations

1. **Default clean set = SAFE only**, with browser cache SAFE pack expanded.  
2. **Never default-select** Local Storage, cookies, history, autofill.  
3. **Selective clean UI** is the main trust unlock for REVIEW bulk (JetBrains plugins, VS Code workspace).  
4. **App A parity** is optional; Pare’s differentiator is **project + JetBrains honesty** without App A's hard whitelist.  
5. **Zoom layout QA** before shipping distribution (Phase 9).

---

## 8. Suggested implementation order

| Phase | Deliverable | Outcome |
|-------|-------------|---------|
| **A** | Browser SAFE pack + age-gate tweak + Service Worker | Chrome reclaimable competitive with App B |
| **B** | Selection model + Review & Clean UI | Users control what leaves the disk |
| **C** | Scan 3-step progress UI | Premium feel without fake progress |
| **D** | Text-zoom layout hardening | High zoom usable |
| **E** | npm `_npx`, OpenCode, broader user caches | Close remaining App A gaps |
| **F** | JetBrains unversioned folder + clearer labeling | Stale/version UX clarity |

---

## 9. LocalStorage policy (short answer)

**Yes — treat Local Storage as credential-adjacent.**  

- It is **not** Keychain, but often holds **session tokens and site logins for web apps**.  
- **Do not** include in Quick Clean.  
- Prefer showing **Cache + Service Worker** as the main Chrome reclaim story.  
- If shown at all: **REVIEW**, default **off**, explicit warning: “May sign you out of websites.”

---

## 10. Appendix — commands used

```bash
app-a clean --dry-run
# → Potential space: 5.36GB | Items: 183
# → Detailed list: ~/.config/app-a/clean-list.txt

.build/debug/pare-cli --profile developer --top 30
# → Total reclaimable: 9.2 GB (this machine)

du -sh ~/Library/Caches/Google/Chrome
du -sh ~/Library/Application\ Support/Google/Chrome/Default/Service\ Worker
du -sh ~/Library/Application\ Support/Google/Chrome/Default/Local\ Storage
```

### DataGrip check

```text
/Applications/DataGrip.app          → single install 2026.1.4
~/Library/Application Support/JetBrains/DataGrip2026.1
~/Library/Application Support/JetBrains/Datagrip   (unversioned; not compared)
→ No multi-version stale finding expected
```

---

## 11. Decision log (for product owner)

| Decision | Options | Recommendation |
|----------|---------|----------------|
| Local Storage | Hide / REVIEW default off / allow Deep Clean default on | **REVIEW, default off** |
| Browser cache age | Keep 3 days / 0–1 day / none for Cache only | **0 days for HTTP cache + SW** |
| Project `node_modules` | SAFE auto / REVIEW / exclude | Keep **SAFE** but **selectable** |
| Fake scan % | Yes / no | **No** — rule-based steps only |

---

*End of analysis. Ready to implement Phase A–C when prioritized.*
