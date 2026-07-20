# Pare vs App B — Feature Comparison

**Updated:** 2026-07-20  

## Alias definitions (internal only)

| Alias | Archetype |
|-------|-----------|
| **App A** | Open-source, CLI/TUI-first cleaner. See [comparison-app-a.md](./comparison-app-a.md). |
| **App B** | Commercial **all-in-one Mac care suite**: multi-module GUI, subscription/one-time SKUs, cleanup + security + performance + clutter + often a menu-bar companion. |
| **Pare** | Focused, safety-first reclaim tool for free/direct distribution. |

Do **not** use third-party product names in public docs, issues, or marketing. Use these aliases only.

Feature sets for App B change with releases; treat this as a **strategic** matrix, not a SKU checklist.

**Status legend:** `Stronger` (Pare) · `Parity` · `Behind` · `Out of scope`

---

## Positioning

| | **Pare** | **App B** |
|--|----------|-----------|
| Business model | Free / direct GitHub release (planned) | Subscription + one-time SKUs |
| Core promise | Surgical reclaim; explain *why* something is junk | One-click “care for your Mac” |
| Safety narrative | Explicit risk levels; Trash; never advanced-delete | Review-before-remove; avoids system files |
| Surface area | Storage + apps + Homebrew + light maintenance | Cleanup + malware + privacy + performance + clutter + cloud |
| Developer focus | First-class (Xcode, JetBrains, package managers, Docker safety) | General consumer |

**Pare should not become an App B clone.** Compete on **trust, reclaimable accuracy, and developer depth** — not malware engines or menu-bar monitoring.

---

## Module-by-module map

App B typically groups tools into modules roughly like:

1. **Orchestrated care** — one primary “run everything safe” flow  
2. **Cleanup** — junk, caches, logs, mail attachments  
3. **Protection** — malware/adware + privacy/permissions  
4. **Performance** — login items, maintenance scripts, sometimes menu-bar monitor  
5. **Applications** — uninstall, update, reset, installer leftovers  
6. **Clutter** — large/old/duplicate files  
7. **Storage map** — visual disk explorer  
8. **Cloud cleanup** — iCloud / Drive connectors (where offered)  

### Orchestrated care (App B headline)

| App B care step (typical) | Pare equivalent | Status |
|---------------------------|-----------------|--------|
| Cleanup (junk auto-selected) | Scan → Quick Clean (safe) / Deep Clean (review) | **Behind** on “one button does all” UX |
| Protection / malware | — | **Out of scope** |
| Performance maintenance | Maintenance tab | **Partial** |
| Software updates | App Manager outdated (Sparkle/MAS) + Homebrew Outdated | **Partial** (no macOS updates) |
| Duplicate removal | — | **Behind** / low priority |

**Gap:** App B’s product power is **orchestration**. Pare has the pieces but no first-run “Safe Care” that chains scan → safe clean → optional maintenance without teaching the whole UI.

### Cleanup

| Area | App B | Pare | Status |
|------|-------|------|--------|
| System junk / caches / logs | Yes | Unified scan, many rules | **Parity+** for developer junk |
| Mail attachments | Yes | Not dedicated | **Behind** |
| Trash empty | Yes | User empties Trash (we only *move* to Trash) | **By design** |
| Large / old files | Clutter / storage map | Large files in results + Disk tab | **Partial** |
| Selectable clean | Yes | Selective clean shipped | **Parity** |

### Protection (malware, privacy, permissions)

| Area | App B | Pare | Status |
|------|-------|------|--------|
| Malware / adware (bundled engine) | Yes | — | **Out of scope** |
| Privacy (history, recent items) | Yes | BrowserReviewDataRule (`.review`) | **Partial** |
| App permissions browser | Yes | — | **Out of scope** (v1) |

### Performance

| Area | App B | Pare | Status |
|------|-------|------|--------|
| Login items / background agents | Yes | Orphaned LaunchAgents (missing binary only) | **Behind** |
| Maintenance scripts / DNS | Yes | Maintenance: DNS, Launch Services, Finder, SQLite | **Partial** |
| Free RAM (legacy Intel-era) | Sometimes | — | **Out of scope** |
| Menu bar monitor | Common | — | **Out of scope** (v1) |

### Applications

| Area | App B | Pare | Status |
|------|-------|------|--------|
| Uninstall + leftovers | Yes | App Manager | **Parity** (depth TBD vs App B) |
| App updates | Yes | Sparkle + MAS check | **Partial** |
| Reset app | Yes | — | **Open** (low) |
| Installer leftovers | Yes | InstallerFileRule | **Parity** |
| Homebrew casks/formulae | Limited / none as first-class | Homebrew Manager + Leave Homebrew | **Stronger** |

### Clutter / storage map / cloud

| Area | App B | Pare | Status |
|------|-------|------|--------|
| Duplicates / similar photos | Often | — | **Behind** |
| Large & old files UX | Strong consumer UI | Disk + large-file lists | **Behind** on polish |
| Visual storage map | Visual explorer | Disk tree (depth-limited) | **Behind** on visualization |
| Cloud cleanup (iCloud/Drive) | Sometimes | — | **Out of scope** (v1) |

### Trust, onboarding, distribution

| Area | App B | Pare | Status |
|------|-------|------|--------|
| Full Disk Access coaching | Polished first-run | Minimal / missing empty-scan guidance | **Behind** |
| Notarized installer | Yes | Scripts ready; signing open | **Behind** |
| In-app auto-update | Yes | — | **Behind** |
| Activity / “space freed” timeline | Often | History of cleans | **Partial** |
| Diagnostics for support | Support tooling | US-4 DiagnosticsExporter planned | **Behind** |

---

## Head-to-head strengths

### App B wins when users want

- One weekly “fix my Mac” button (orchestrated care)  
- Malware + privacy + performance in one subscription  
- Pretty storage map / clutter / cloud stories  
- Menu bar always-on presence  
- Polished onboarding and Gatekeeper-friendly install  

### Pare wins when users want

- **Developer reclaim** without false Docker TB totals  
- **Explainable** findings (reason + risk + By Tool)  
- **Hard safety** (`advanced` never deleted; search indexes protected)  
- **Homebrew-native** management (adopt / leave / non-greedy upgrade)  
- **Trash + undo** as default, not permanent wipe  
- No subscription tax for power users  

---

## Strategic “do not build” list

Copying these from App B would dilute Pare and explode scope:

1. Malware / third-party AV-class engine  
2. Menu bar system monitor  
3. Cloud provider cleanup connectors  
4. Photo-similar / AI duplicate galleries (unless storage narrative demands it later)  
5. macOS update installation  

---

## Strategic gaps worth closing (App B–inspired, Pare-shaped)

| Gap | Why it matters | Pare-shaped answer |
|-----|----------------|--------------------|
| One-button safe journey | Orchestrated care converts non-experts | “Safe Care”: scan → select safe → clean → optional maintenance |
| Permission coaching | Empty scans destroy trust | Full Disk Access guide when results look empty |
| Distribution polish | Users can’t install unsigned apps easily | Phase 9 / US-4 notarized DMG |
| Support bundle | App B has support path | Diagnostics export (US-4) |
| Clutter lite | Large downloads/old installers already partly covered | Improve large-file UX; skip photo dups for now |

Detail and ranking: [2026-07-20 competitive gaps](../reviews/2026-07-20-competitive-gaps.md).
