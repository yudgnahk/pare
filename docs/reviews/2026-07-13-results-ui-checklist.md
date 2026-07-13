# Results UI redesign checklist

**Date:** 2026-07-13  
**Branch:** `feat/scan-ux-selective-clean-cache-breadth`  
**Source of truth for post-scan dashboard cleanup**

## Goals

1. Fix broken **By Tool** row layout (fixed-width % / size frames wrap under display scale).
2. **Category Overview** becomes a real browse + select surface (tree, folder bulk-select when safe).
3. Clarify **Category vs By Tool** — stop dual list confusion; tool view becomes a share chart only.
4. **Merge** “Large Files by Category” + “Top Files and Caches” into one selectable list with Finder reveal.
5. Keep sections fewer, clearer, action-oriented.

## Product decisions

| Topic | Decision |
|-------|----------|
| Category Overview | Primary place to browse findings and multi-select for **Clean selected** |
| Tree | Group findings under parent folder; checkbox on folder selects all *selectable* children |
| Folder bulk-select | Allowed when every child is non-`.advanced`; SAFE defaults selected, REVIEW opt-in |
| By Tool list | **Remove** as a second file list (was non-actionable + broken layout) |
| By Tool replacement | **Donut / share chart** + compact legend (attribution only, not a second clean surface) |
| Top + Large Files | **One** section: “Largest items” — select, reveal in Finder, exclude |
| Advanced risk | Visible for honesty; checkbox disabled (cannot clean) |

## Section order (after scan)

1. Header (reclaimable hero + rescan)
2. Review & Clean bar (selection count + Clean selected)
3. Cleanup status banner (if any)
4. Metrics row
5. Device backups (if any)
6. **Browse by category** (expandable tree + select)
7. **Where space goes** (tool share donut)
8. **Largest items** (merged candidates)

## Implementation checklist

### ViewModel

- [x] `folderGroups(for:)` — group findings by parent path
- [x] `togglePaths` / `selectionState(for:)` — multi-path selection
- [x] `largestItems` — unique paths sorted by size (cap ~40)
- [x] Keep category toggle for SAFE bulk select
- [x] `revealInFinder` available from all candidate rows

### Views

- [x] Fix / remove broken `ToolRollupRow` fixed frames
- [x] Category expandable browser with tree + checkboxes + reveal
- [x] Tool share donut + legend (Charts)
- [x] Merged Largest items section (select + reveal + exclude)
- [x] Remove duplicate Top Files / Large Files by Category sections
- [x] Copy: short subtitles explaining each section

### Verify

- [x] `make build` (macOS 13 Canvas donut — no SectorMark)
- [x] `make test` (317 passed)
- [ ] Manual: expand category → select folder → Clean selected
- [ ] Manual: donut legend readable at narrow width
- [ ] Manual: Largest items Show in Finder works

## Performance hotfix (2026-07-13 later)

- [x] **Never render per-file children** for SAFE caches in Browse by category
- [x] **Roll up** deep trees (`~/.npm/_cacache`, browser profiles, `~/Library/Caches/<App>`) to folder rows
- [x] Cap **80 folder rows**/category (largest first); show full `~/…` path
- [x] **Clear / All Safe** collapse expanded categories first; selection metrics O(selected) not O(all findings)
- [x] Precompute folder rows + path index once after scan (off main actor)

## Out of scope (follow-up)

- Per-tool clean filter chip on Largest items
- Auto-suggest 1d Docker prune when free space low
- Further scan-side aggregation (emit folder findings instead of per-file from rules)
