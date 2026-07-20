# Competitive Gaps & Ranked Next-5 Backlog

**Date:** 2026-07-20  
**Inputs:** Current Pare master (Phases 1–8 + Leave Homebrew #24), [App A comparison](../features/comparison-app-a.md), [App B comparison](../features/comparison-app-b.md), open [US-4](../user-stories.md).

## Alias definitions (internal only)

| Alias | Archetype |
|-------|-----------|
| **App A** | Open-source, CLI/TUI-first macOS cleaner |
| **App B** | Commercial multi-module Mac care suite (GUI + often menu bar) |
| **Pare** | This product |

Do not use third-party product names in public-facing copy. Use aliases in design docs, PR descriptions, and issues when comparing.

---

## Executive summary

Pare has **closed most historical App A feature gaps** (app uninstall, AI/Homebrew caches, project purge, installer finder, browser extended, history UI, maintenance subset, disk tree). Competing with **App B** is not about matching malware or visual storage maps — it is about **shipping**, **first-run trust**, and a **simpler safe-clean journey**.

**Positioning to defend:** surgical reclaim · risk levels · Trash+undo · developer depth · Homebrew honesty · Docker safety.

---

## Scorecard (high level)

| Theme | vs App A | vs App B | Comment |
|-------|----------|----------|---------|
| Junk discovery breadth | Ahead / parity | Parity+ for dev | 30+ rules in `RuleCatalog.all` |
| Safety / undo | Ahead | Ahead or parity | Advanced hard-block is unique |
| One-click care UX | Ahead of CLI | **Behind** | No orchestrated-care analogue |
| App + Homebrew lifecycle | Ahead | Ahead on Brew | Leave Homebrew is unique |
| Disk visualization | Behind TUI polish | **Behind** visual maps | Good enough for v1 |
| Malware / privacy suite | N/A | **Out of scope** | |
| Install / update / support | Behind (unsigned) | **Behind** | Blocks real users |
| System monitor | Won’t do | Out of scope | |

---

## Ranked “Next 5” backlog

Ordered by **user impact × strategic fit × effort**. Implement top-down unless blocked on Apple Developer credentials.

### 1. Distribution readiness (US-4 / Phase 9) — **Ship**

| | |
|--|--|
| **Why #1** | Without a notarized DMG, competitive comparisons are academic — only clone-and-build users exist. App B and App A (via package managers) install in minutes. |
| **Scope** | Developer ID signing · `make release` / notarytool · staple · Gatekeeper check · GitHub `v1.0.0` · **DiagnosticsExporter** + “Export Diagnostics…” |
| **Effort** | Medium (blocked on cert + Apple ID app password) |
| **Acceptance** | Fresh Mac: open DMG → app runs without right-click bypass; diagnostics JSON exports without full paths |
| **Refs** | `docs/user-stories.md` US-4, `scripts/release.sh`, `docs/roadmap.md` Phase 9 |

### 2. First-run trust: Full Disk Access + empty-scan coaching

| | |
|--|--|
| **Why #2** | App B’s polish starts at permissions. Pare can return sparse results without FDA; users conclude “app is broken” and never see developer reclaim strength. |
| **Scope** | Detect likely missing FDA (e.g. cannot list protected Library paths) · Settings/onboarding card with System Settings deep link · Empty-state copy when reclaimable ≈ 0 after scan · Optional “Open Full Disk Access” button |
| **Effort** | Small–medium |
| **Acceptance** | New user without FDA sees clear fix path; with FDA, card dismisses |
| **Not** | Fake progress or inventing findings |

### 3. “Safe Care” one-pass journey (orchestrated care, Pare-shaped)

| | |
|--|--|
| **Why #3** | App B wins non-experts with one button. Pare already has scan + quick clean + maintenance pieces — missing **orchestration and narrative**. |
| **Scope** | Home/hero action: Run Safe Care → unified scan → auto-select `.safe` only → confirm sheet (counts + size + large-clean search-index heads-up) → clean to Trash → optional “Run light maintenance?” (DNS only or user-picked) · Never auto-include `.review` / `.advanced` |
| **Effort** | Medium |
| **Acceptance** | New user frees space in ≤3 clicks without visiting every tab |
| **Explicitly exclude** | Malware, greedy Homebrew upgrade, Docker.raw, review browser data |

### 4. Scan progress & perceived performance

| | |
|--|--|
| **Why #4** | App A and App B feel “alive.” Pare sequential rules + long developer trees can look hung (partially fixed historically). Progress is trust. |
| **Scope** | Surface current rule title + index/count · Optional streaming category partials · Document warm vs cold expectations · Cap huge project-root walks if needed |
| **Effort** | Medium |
| **Acceptance** | During a full `RuleCatalog.all` scan, UI always shows which rule is running; cancel remains reliable |
| **Note** | Do **not** re-attempt nested `withTaskGroup` parallel rules without a careful design (prior revert) |

### 5. Quality bar + supportability (pre-release hardening)

| | |
|--|--|
| **Why #5** | Shipping with known red tests and no support bundle burns credibility. Complements #1. |
| **Scope** | Fix pre-existing failing tests (e.g. HomebrewCacheRule age/folder expectations post reconstructible-cache changes) · Align CLAUDE/CHANGELOG rule counts · Rename legacy app entry source file → `PareApp.swift` · DiagnosticsExporter if not done in #1 · Manual matrix notes for Maintenance on current macOS |
| **Effort** | Small–medium |
| **Acceptance** | `make test` green on clean checkout; docs match `RuleCatalog.all` count (~36 unique) |

---

## Explicitly deferred (not in next 5)

| Item | Reason |
|------|--------|
| Malware / antivirus | Wrong product; legal/update burden |
| Menu bar monitor | App A status / App B menu bar — not reclaim core |
| Cloud cleanup (iCloud/Drive APIs) | Scope + auth complexity |
| Photo duplicate / similar images | Consumer App B play; low fit |
| Category-level whitelist | Nice; path ExclusionList covers v1 |
| Deeper uninstall leftover categories | Only if App Manager user feedback demands |
| Full sudo System Optimizer | Roadmap deferred; hardware validation |
| Parallel rule execution | Prior instability; revisit after progress UI |
| Leave Homebrew move-vs-copy polish | Follow-up only if large-cask leave is painful |
| Pare auto-update (Sparkle) | After notarized releases exist (#1) |

---

## Suggested sequencing

```text
Week 1–2:  #5 test/doc hygiene (unblocks confidence)
           #2 FDA coaching (can ship without cert)
Week 2–4:  #1 signing + notarize + diagnostics  [cert-gated]
           #3 Safe Care UX (parallelizable once scan/clean APIs stable)
Week 4+:   #4 scan progress
Then:      Sparkle auto-update, leftover depth, category whitelist as feedback-driven
```

If **no Developer ID yet**: do **#2 → #3 → #5 → #4**, keep #1 as hard gate before public v1.0 marketing.

---

## Success metrics (post next-5)

| Metric | Target |
|--------|--------|
| Install path | Unsigned-right-click not required on clean Mac |
| First session | User understands FDA within 30s of empty-looking scan |
| Time-to-first-clean | ≤3 minutes for Safe Care on a dirty dev Mac |
| Support | Issue reporters can attach diagnostics JSON |
| Regression | `make test` green; no Docker.raw in reclaimable totals |

---

## Doc index

| Doc | Role |
|-----|------|
| [comparison-app-a.md](../features/comparison-app-a.md) | App A (CLI-first) matrix |
| [comparison-app-b.md](../features/comparison-app-b.md) | App B (care suite) matrix + do-not-build |
| This file | Ranked next-5 + sequencing |
| [user-stories.md](../user-stories.md) | US-4 still open; US-5/US-6 done |
| [roadmap.md](../roadmap.md) | Phase 9 distribution checklist |

---

## One-line recommendation

**Stop chasing App A CLI parity. Ship notarized Pare, teach Full Disk Access, and wrap existing safe clean into a single Safe Care journey — then harden tests and scan progress.**
