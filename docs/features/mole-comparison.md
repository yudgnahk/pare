# Pare vs Mole — Complete Comparison

**Updated:** 2026-07-13  
**Mole:** `mo clean --dry-run` (CLI) · **Pare:** `pare-cli --profile developer` + SwiftUI app  
**Live sample machine:** Apple Silicon Mac (same host used for both tools)

This document is the **product source of truth** for Mole parity: what we still need, what we already do better, and policy choices (especially browsers).

---

## 1. Head-to-head (live dry-run, this machine)

| Metric | Mole `mo clean --dry-run` | Pare `pare-cli --profile developer` |
|--------|---------------------------|--------------------------------------|
| Headline reclaimable | **~5.36 GB** (183 items, 37 categories) | **~9.2 GB** (thousands of files; richer project tree) |
| Character | System + browser + npm + Homebrew; heavy **whitelists** | Developer-first: projects, JetBrains, package caches |
| Browser (Chrome) | Cache **~625 MB** + Service Worker **~450 MB+** | Was weak (~38 MB Local Storage); **fixed in this PR** with SAFE pack |
| Project trees | Hinted via `mo purge` / large files | First-class **Project Artifacts** (node_modules, target, .venv, …) |
| JetBrains Application Support | Often **whitelisted** | Surfaced (stale versions, plugins, wrong-platform stubs) |
| Docker.raw | Clue only | **Hard policy:** never delete VM disk / volumes |
| UI | Terminal | Native SwiftUI (sidebar, selective clean, undo) |

> Numbers change over time. Re-run both tools after major changes and update §1.

---

## 2. Where Pare is **better** than Mole

| Area | Why Pare wins |
|------|----------------|
| **Project artifact discovery** | Recursive / catalogued project junk (`.cache`, `node_modules`, `target`, `.venv`) in the main scan, not a separate mental model only (`mo purge`) |
| **JetBrains honesty** | Flags superseded IDE folders, review plugins, wrong-platform native stubs — Mole often **protects** JetBrains paths via whitelist |
| **Risk model** | Explicit **SAFE / REVIEW / ADVANCED** with CleanupEngine re-checks; Mole is mostly path lists |
| **Docker safety** | Binding policy: never Trash `Docker.raw` / volumes; Maintenance prune without `--volumes` |
| **Native Mac app** | Sidebar IA, undo via Trash transactions, App Manager, Homebrew manager, Disk Analyzer, History export |
| **Selective clean (this PR)** | User picks findings; REVIEW (e.g. Local Storage) defaults **off** |
| **Policy transparency** | Docs for Docker, Local Storage, risk gates — not a black box |
| **Wrong-platform binaries** | Windows/Linux stubs in Downloads + JetBrains plugins |
| **Stale app versions** | Duplicate `.app` bundles by bundle ID |
| **Homebrew manager** | Formulae/casks/outdated/migrate/adopt in-app (beyond cache clean) |

---

## 3. Gaps Pare must still fill (backlog)

Ordered by user impact. Status reflects **this PR** when marked done.

### Scan / reclaim

| Gap | Mole behavior | Pare before | This PR | Follow-up |
|-----|---------------|-------------|---------|-----------|
| Chrome/Safari **HTTP cache** | Always listed | Hidden by **3-day age gate** when browser is active | **No age gate** for browser cache paths | — |
| Chrome **Service Worker** | ~hundreds of MB | Missing | **SAFE** multi-profile | Edge/Brave/Arc already same rule |
| Chromium **GPUCache / Code Cache** under App Support | Partial | Partial | SAFE markers expanded | — |
| Multi-profile browsers | Yes | Mostly `Default` | **All profiles** under User Data | — |
| `~/.npm/_npx` | Yes (~1 GB here) | Only `_cacache` | **SAFE** target | — |
| OpenCode / Codex **caches** | Yes | Incomplete | OpenCode cache in catalog | Codex: never sessions/credentials |
| Broad user caches (mediaanalysis, helpd, Maps) | Yes | Partial | Partial | Expand carefully |
| Empty Trash | Yes | No | No | Maintenance action |
| System caches needing sudo | Optional | No | No | Out of scope for sandboxed app |
| pnpm **store** prune | Large-file clue | Not auto | Not auto | Dedicated prune UX |

### Product / UX

| Gap | Status |
|-----|--------|
| Select files/categories to clean | **This PR** |
| 3-step scan progress animation | **This PR** |
| Text-zoom layout hardening | **This PR** (sidebar width + flexible CTAs) |
| Full `mo optimize` parity | Partial via Maintenance tab |
| Real-time system monitor | Out of scope |

### Policy (not gaps — intentional)

| Topic | Decision |
|-------|----------|
| **Local Storage / cookies / history** | **Never Quick Clean.** REVIEW only; selective clean defaults **unchecked**. May log users out of web apps. |
| **Docker.raw / volumes** | Never filesystem delete |
| **ADVANCED findings** | Report only; blocked in CleanupEngine |

See also: [`docs/features/browser-local-storage-policy.md`](browser-local-storage-policy.md).

---

## 4. Feature matrix (commands)

| Mole command | Pare equivalent | Notes |
|--------------|-----------------|-------|
| `mo clean` | Smart Scan + Quick/Selected/Deep Clean | Risk tiers + selection |
| `mo clean --dry-run` | Scan only (no delete) | App shows estimates |
| `mo uninstall` | **Apps** tab | Leftovers + Trash |
| `mo optimize` | **Maintenance** tab | Subset of tasks |
| `mo analyze` | **Disk Analyzer** tab | Tree + trash |
| `mo purge` | Project artifact rules | In unified scan |
| `mo installer` | InstallerFileRule | .dmg/.pkg/… |
| `mo history` | **History** tab + export | JSON/CSV |
| `mo status` | — | Not planned |
| Homebrew cache | HomebrewCacheRule + **Homebrew** tab | Manager is broader |

---

## 5. Implementation checklist (this PR)

- [x] Docs: this comparison + Local Storage policy + gap analysis link  
- [x] Browser SAFE pack (cache age, Service Worker, multi-profile GPU/Code cache)  
- [x] npm `_npx`  
- [x] OpenCode cache in AI catalog  
- [x] Selective clean UI (SAFE default on, REVIEW default off)  
- [x] ScanRunner progress + 3-step hero  
- [x] Zoom: sidebar width scales; primary CTA min-width flexible  
- [x] JetBrains unversioned folder as oldest sibling when versioned peers exist  
- [ ] Broader system caches (mediaanalysis, helpd) — follow-up  
- [ ] Empty Trash maintenance action — follow-up  
- [ ] Automated Mole-vs-Pare path diff script — follow-up  

---

## 6. How to re-verify

```bash
mo clean --dry-run
# list: ~/.config/mole/clean-list.txt

swift run pare-cli --profile developer --top 30
# or: make start PROFILE=developer
```

Compare browser lines (Chrome cache / Service Worker) and developer package totals after this PR.

---

## 7. Related documents

| Doc | Purpose |
|-----|---------|
| [browser-local-storage-policy.md](browser-local-storage-policy.md) | Why Local Storage is not auto-cleaned |
| [../reviews/2026-07-13-scan-ui-gap-analysis.md](../reviews/2026-07-13-scan-ui-gap-analysis.md) | Original investigation notes |
| [docker-safety.md](docker-safety.md) | Docker never-delete policy |
| [../roadmap.md](../roadmap.md) | Phase status |
