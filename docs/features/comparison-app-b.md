# Pare vs App B — Feature Comparison

**Updated:** 2026-07-20  

**App B** (the App B vendor; current product often just “App B”, successor to App B) is a commercial all-in-one Mac care suite. Pare is a focused, safety-first reclaim tool for free/direct distribution.

Sources for App B modules: the App B vendor product docs/blog (Smart Care, Cleanup, Protection, Performance, Applications, My Clutter, Space Lens, Cloud Cleanup, Menu app, bundled malware engine). Feature sets change with releases; treat this as a strategic matrix, not a license feature checklist.

**Status legend:** `Stronger` (Pare) · `Parity` · `Behind` · `Out of scope`

---

## Positioning

| | **Pare** | **App B** |
|--|----------|----------------|
| Business model | Free / direct GitHub release (planned) | Subscription + one-time SKUs |
| Core promise | Surgical reclaim; explain *why* something is junk | One-click “care for your Mac” |
| Safety narrative | Explicit risk levels; Trash; never advanced-delete | Review-before-remove; avoids system files |
| Surface area | Storage + apps + Homebrew + light maintenance | Cleanup + malware + privacy + performance + clutter + cloud |
| Developer focus | First-class (Xcode, JetBrains, package managers, Docker safety) | General consumer |

**Pare should not become a App B clone.** Compete on **trust, reclaimable accuracy, and developer depth** — not malware engines or menu-bar monitoring.

---

## Module-by-module map

### Smart Care (App B headline)

| App B Smart Care step | Pare equivalent | Status |
|---------------------|-----------------|--------|
| Cleanup (junk auto-selected) | Scan → Quick Clean (safe) / Deep Clean (review) | **Behind** on “one button does all” UX |
| Protection / malware | — | **Out of scope** |
| Performance maintenance | Maintenance tab | **Partial** |
| Software updates | App Manager outdated (Sparkle/MAS) + Homebrew Outdated | **Partial** (no macOS updates) |
| Duplicate removal | — | **Behind** / low priority |

**Gap:** App B’s product power is **orchestration**. Pare has the pieces but no first-run “Safe Care” that chains scan → safe clean → optional maintenance without teaching the whole UI.

### Cleanup

| Area | App B | Pare | Status |
|------|-----|------|--------|
| System junk / caches / logs | Yes | Unified scan, many rules | **Parity+** for developer junk |
| Mail attachments | Yes | Not dedicated | **Behind** |
| Trash empty | Yes | User empties Trash (we only *move* to Trash) | **By design** |
| Large / old files | My Clutter / Space Lens | Large files in results + Disk tab | **Partial** |
| Selectable clean | Yes | Selective clean shipped | **Parity** |

### Protection (malware, privacy, permissions)

| Area | App B | Pare | Status |
|------|-----|------|--------|
| Malware / adware (bundled malware engine) | Yes | — | **Out of scope** |
| Privacy (history, recent items) | Yes | BrowserReviewDataRule (`.review`) | **Partial** |
| App permissions browser | Yes | — | **Out of scope** (v1) |

### Performance

| Area | App B | Pare | Status |
|------|-----|------|--------|
| Login items / background agents | Yes | Orphaned LaunchAgents (missing binary only) | **Behind** |
| Maintenance scripts / DNS | Yes | Maintenance: DNS, Launch Services, Finder, SQLite | **Partial** |
| Free RAM (Intel-era) | Menu / limited on Apple Silicon | — | **Out of scope** |
| Menu bar monitor | Yes | — | **Out of scope** (v1) |

### Applications

| Area | App B | Pare | Status |
|------|-----|------|--------|
| Uninstall + leftovers | Yes | App Manager | **Parity** (depth TBD vs App B) |
| App updates | Yes | Sparkle + MAS check | **Partial** |
| Reset app | Yes | — | **Open** (low) |
| Installer leftovers | Yes | InstallerFileRule | **Parity** |
| Homebrew casks/formulae | Limited / none as first-class | Homebrew Manager + Leave Homebrew | **Stronger** |

### My Clutter / Space Lens / Cloud

| Area | App B | Pare | Status |
|------|-----|------|--------|
| Duplicates / similar photos | My Clutter | — | **Behind** |
| Large & old files UX | Strong consumer UI | Disk + large-file lists | **Behind** on polish |
| Visual storage map | Space Lens | Disk tree (depth-limited) | **Behind** on visualization |
| Cloud cleanup (iCloud/Drive) | Cloud Cleanup | — | **Out of scope** (v1) |

### Trust, onboarding, distribution

| Area | App B | Pare | Status |
|------|-----|------|--------|
| Full Disk Access coaching | Polished first-run | Minimal / missing empty-scan guidance | **Behind** |
| Notarized installer | Yes | Scripts ready; signing open | **Behind** |
| In-app auto-update | Yes | — | **Behind** |
| Activity / “space freed” timeline | My Activity | History of cleans | **Partial** |
| Diagnostics for support | Support tooling | US-4 DiagnosticsExporter planned | **Behind** |

---

## Head-to-head strengths

### App B wins when users want

- One weekly “fix my Mac” button (Smart Care)  
- Malware + privacy + performance in one subscription  
- Pretty Space Lens / clutter / cloud stories  
- Menu bar always-on presence  
- Polished onboarding and Gatekeeper-friendly install  

### Pare wins when users want

- **Developer reclaim** without false Docker TB totals  
- **Explainable** findings (reason + risk + By Tool)  
- **Hard safety** (`advanced` never deleted; Spotlight indexes protected)  
- **Homebrew-native** management (adopt / leave / non-greedy upgrade)  
- **Trash + undo** as default, not permanent wipe  
- No subscription tax for power users  

---

## Strategic “do not build” list

Copying these from App B would dilute Pare and explode scope:

1. Malware / bundled malware engine-class engine  
2. Menu bar system monitor  
3. Cloud provider cleanup connectors  
4. Photo-similar / AI duplicate galleries (unless storage narrative demands it later)  
5. macOS update installation  

---

## Strategic gaps worth closing (App B-inspired, Pare-shaped)

| Gap | Why it matters | Pare-shaped answer |
|-----|----------------|--------------------|
| One-button safe journey | App B Smart Care converts non-experts | “Safe Care”: scan → select safe → clean → optional maintenance |
| Permission coaching | Empty scans destroy trust | Full Disk Access guide when results look empty |
| Distribution polish | Users can’t install unsigned apps easily | Phase 9 / US-4 notarized DMG |
| Support bundle | App B has support path | Diagnostics export (US-4) |
| Clutter lite | Large downloads/old installers already partly covered | Improve large-file UX; skip photo dups for now |

Detail and ranking: [2026-07-20 competitive gaps](../reviews/2026-07-20-competitive-gaps.md).
