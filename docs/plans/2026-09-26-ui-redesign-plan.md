# UI Redesign — Implementation Plan

Wave 1 output for `2026-09-26-ui-redesign-tasks.md`. Planning only; no code has changed.
Reference: `assets/2026-09-26-reference-disk-analyzer.png`. Design guidance:
`.claude/skills/macos-swiftui-design/SKILL.md`. Brand source: `docs/brand-guide.html`.

## Summary

- Every `AppTheme` color becomes an adaptive `ThemeSwatch` (light + dark hex), bridged to SwiftUI
  through `NSColor(name:dynamicProvider:)`. It compiles under plain `swift build` with no asset catalog.
  The 589 existing `AppTheme.` call sites stay untouched. Only 10 hardcoded white/black sites and
  22 literal colors need editing.
- The light palette is anchored on the brand guide's "light surface" (`#EDF2F5` ground,
  `#1A2D40`-family text). Seafoam stays the accent, deepened to `#17706A` for light-mode
  text and fills. A contrast test suite gates every token pair.
- Each of the 16 `ScanCategory` cases gets one swatch and one SF Symbol, drawn by a new
  `IconTile` squircle component. Each swatch is tuned to give ≥3:1 against the white glyph and against
  both modes' grounds. The sidebar gets the same tiles for its destinations and a native vibrancy
  material.
- The Disk Analyzer becomes a flat, sortable `Table` per folder level, with a breadcrumb, a search bar,
  Kind and Size filters, and a custom inspector pane. All of these are available on macOS 13
  (hierarchical `Table` and `.inspector` require macOS 14).
- **Safety fix folded in:** the current hover trash (`DiskAnalyzerViewModel.moveToTrash`) calls
  `FileManager.trashItem` directly, so it bypasses `ScanPolicy`, exclusions and the undo record. It
  also builds the tree on the main actor. The plan replaces the button with "Add to review", which
  resolves the item against Smart Scan findings and runs through `CleanupCoordinator` →
  `CleanupEngine` → `CleanConfirmationSheet`.

## Design decisions

### Token model

- `Theme/ThemeSwatch.swift`: `struct ThemeSwatch: Sendable { let light: RGBA; let dark: RGBA }`,
  where `RGBA` is a hex value plus alpha. `var color: Color` returns
  `Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light })`.
  SwiftUI resolves this per render, so `.opacity()`, gradients and `Canvas` fills adapt without any
  `@Environment(\.colorScheme)` plumbing.
- `AppTheme` keeps its public surface (`AppTheme.accent`, `AppTheme.Hairline.standard`, …) as
  `static var … { Swatch.x.color }`, so call sites don't change. The raw swatches live in
  `AppTheme.Swatch`, which tests read directly with no `NSColor` resolution involved.
- New tokens: `onAccent` (text and glyph color on accent/success/review fills), `accentText` (accent used
  as text), `cardFill`, `Shadow.card`, `Background.vignette` and `Background.bloom`.
- Opacity-derived text tokens become solid hex. Dark `textTertiary` today (chalk at 48% alpha) measures
  **3.36:1 on `panel`** and fails the skill's 4.5:1 body bar.
- Two existing contrast defects get fixed along the way. `PrimaryActionButton` draws `textPrimary`
  (chalk) on a seafoam fill, which measures 1.8:1; it moves to `onAccent`. `CleanConfirmationSheet`
  hardcodes `.black` on its confirm button; that also moves to `onAccent`.

### Palette (hex; the WCAG ratio in brackets is measured against that mode's ground and panel)

| Token | Dark (current brand) | Light (new) |
|---|---|---|
| `base` (page ground) | `#0D1520` ink | `#EDF2F5` chalk-warm |
| `panelSecondary` | `#152030` marine | `#E4EBF0` |
| `panel` (cards) | `#1A2D40` surface | `#FFFFFF` |
| `cardFill` | `#1A2D40` @ 62% | `#FFFFFF` @ 85% |
| `sidebar` | vibrancy (see below); fallback `#152030` | vibrancy; fallback `#E6EDF2` |
| `sidebarSelected` | `#1F4757` | `#D3EBE7` |
| `textPrimary` | `#E4EDF2` [15.5 / 11.9] | `#152030` [14.5 / 16.4] |
| `textSecondary` | `#A9BCC9` [9.4 / 7.2] | `#44586A` [6.5 / 7.4] |
| `textTertiary` | `#8499A9` [6.2 / 4.8] | `#56697B` [5.0 / 5.7] |
| `accent` (fills, rings) | `#5CC8BC` | `#17706A` |
| `accentText` | `#5CC8BC` [9.1] | `#17706A` [5.2 / 5.9] |
| `accentDeep` | `#238C82` | `#0F5A55` |
| `onAccent` | `#0D1520` on seafoam [9.1] | `#FFFFFF` on `#17706A` [5.9] |
| `success` | `#57DB94` [10.5] | `#1A7542` [5.1 / 5.7] |
| `warning` | `#F7BD4F` [10.8] | `#8F5500` [5.4 / 6.1] |
| `review` (danger) | `#FA7A6B` [7.0] | `#B8352A` [5.2 / 5.9] |
| `Hairline.faint/standard/strong` | white 4 / 7 / 14% | `#152030` 5 / 9 / 16% |
| `Fill.subtle/control/hover/selected` | white 6 / 8 / 10 / 18% | `#152030` 4 / 6 / 8 / 12% |
| `tableHeaderBackground` | black 12% | `#152030` 4% |
| `Shadow.card` | black 20% | `#152030` 8% |
| `Background.vignette` | black 22% | clear |
| `Background.bloom` (accent opacity) | 0.22 | 0.08 |

Gradients are used sparingly. In light mode the page stays chalk-warm with a faint seafoam bloom and no
vignette. The seafoam→success gradient on `PrimaryActionButton` is kept, but only on the primary CTA.

### Sidebar: vibrancy (recommended)

Use `NSVisualEffectView` with `.sidebar` material and `.behindWindow` blending, wrapped in
`Views/Components/SidebarMaterial.swift`, plus a 4% seafoam tint at the top. It adapts to both modes
for free, matches Finder, System Settings and the reference app, and falls back to opaque
automatically when **Reduce Transparency** is on. The solid brand navy is left as the fallback token.
The existing comment, "Solid base so the menu is never transparent/invisible", records an earlier
problem. The material must be the bottom layer, and the task below checks this in both appearances.

### Category → color / symbol (tile swatches; white glyph ≥3:1 in both modes)

| Category | Symbol | Light | Dark |
|---|---|---|---|
| userCaches | `tray.full.fill` | `#1F8A80` | `#2A9D92` |
| temporaryFiles | `hourglass` | `#B86E00` | `#C27A12` |
| logsAndCrashReports | `doc.text.fill` | `#C4453A` | `#D0584C` |
| browserCaches | `globe` | `#2F7FD6` | `#3D8BE0` |
| developerBuildArtifacts | `hammer.fill` | `#7650D8` | `#8660E0` |
| developerPackageCaches | `shippingbox.fill` | `#1778A8` | `#2A8AB8` |
| developerSimulatorCaches | `iphone` | `#8A6A3E` | `#9C7A4A` |
| designerCaches | `paintbrush.pointed.fill` | `#D14E7A` | `#D85F88` |
| videoBuilderCaches | `film.fill` | `#2E8B57` | `#3A9863` |
| aiToolCaches | `brain.head.profile` | `#5A5FE0` | `#6A6FE6` |
| installerFiles | `arrow.down.doc.fill` | `#9A7A12` | `#A88720` |
| applications | `app.fill` | `#9A4FC8` | `#A75ED2` |
| projectArtifacts | `folder.fill.badge.gearshape` | `#B25E1E` | `#BE6B2C` |
| deviceBackups | `externaldrive.fill.badge.timemachine` | `#3F6F8F` | `#5585A6` |
| productivityCaches | `briefcase.fill` | `#5E7F1E` | `#6E9028` |
| launchAgents | `gearshape.2.fill` | `#5E6B78` | `#6E7C8A` |

Measured ranges: tile vs white glyph 3.3–5.9. Tile as a dot or bar segment on its ground: light
3.5–5.2, dark 3.2–5.5 on `panel`. With 16 categories some hues sit close together (the orange family),
so color is never the only cue. Every appearance pairs the color with the symbol and the label, as the
skill's accessibility rule requires.

Sidebar destination tiles (`Theme/DestinationStyle.swift`): Smart Scan teal `#1F8A80`, Apps blue
`#2F7FD6`, Homebrew amber `#B86E00`, Disk Analyzer indigo `#5A5FE0`, Maintenance graphite `#5E6B78`,
History purple `#9A4FC8`, Settings gray `#6B7280`. Glyph contrast is 4.0–5.5.

`IconTile`: a continuous `RoundedRectangle` with radius = 0.225 × side, filled with the swatch and a 6%
top-light overlay (the only gradient on the tile), with a white glyph at 0.58 × side. Sizes are 18
(table rows), 22 (sidebar/legend), 28 (category rows) and 56 (inspector hero). It is
`accessibilityHidden` because the adjacent label carries the meaning.

### Disk Analyzer layout (macOS 13)

```
┌ Sidebar ┬──────────────────────────────── content ───────────────────────┬─ Inspector (280) ─┐
│ tiles   │ Disk Analyzer · /Users/k   [Choose Folder…] [↻]                │ [56pt tile]       │
│ + vibr. │ 128.4 GB · 312 items · scanned 2 min ago                        │ name              │
│         │ [🔍 Search this folder     ] [Any Kind ▾] [Any Size ▾]          │ 14.9 GB on disk   │
│         │ ⌂ k  ›  Library  ›  Caches                         14.9 GB      │ ───────────       │
│         │ Name ▾              │ Size       │ Items │ Modified   │ Kind     │ Items   92,075    │
│         │ [tile] var          │ ▇▇▇ 11.4GB │ 19,458│ 13 Sep 2026│ Folder   │ Kind    Folder    │
│         │ [tile] tmp          │ ▇   3.6 GB │ 72,346│ 25 Sep 2026│ Folder   │ Modified …        │
│         │ ⋯ 214 smaller items │    40 MB   │       │            │          │ Location (wraps)  │
│         ├─────────────────────────────────────────────────────────────────┤ Reveal in Finder  │
│         │ Review: 3 items · 1.2 GB     [Clear] [Review & Move to Trash…]   │ Copy Path         │
└─────────┴─────────────────────────────────────────────────────────────────┴ Add to Review     ┘
```

- `Table(entries, selection:, sortOrder:)` is macOS 12. `contextMenu(forSelectionType:menu:primaryAction:)`
  is macOS 13; its primary action (double-click or Return) drills into a folder. Disclosure rows,
  `.inspector`, `TableColumnCustomization` and toolbar `.searchable` all require macOS 14, so they are
  not used. The search field is a custom `TextField` because the window hides its title bar.
- The name column never truncates silently: it uses middle truncation and `.help(fullPath)`. Modified
  uses `Date.FormatStyle` with `.abbreviated` date and no time. Kind uses `localizedTypeDescription`.
- There are no placeholder skeleton rows. Loading shows a determinate count ("Scanned 18,204 items…").
  Empty-filter and empty-folder states use `EmptyStateView`.
- Each level shows its top 200 children. The remainder folds into one non-actionable
  "N smaller items" row, which replaces today's silent 50-child cap.
- "Add to Review" resolves the entry against the latest Smart Scan findings using
  `ScanPolicy.isEqualToOrDescendant`, which matches by path component and never by substring:
  - **covered**: the entry contains findings, and the tray adds those findings (advanced ones excluded).
  - **inside a finding**: the tray adds a derived finding with the entry's path and the parent
    finding's category and risk.
  - **not a candidate** or **no scan yet**: the button is disabled and shows an inline reason, with a
    "Run Smart Scan" button when there is no scan yet.
  - `CleanupEngine` still re-verifies everything. The Disk Analyzer adds no new path rules.
- The tray's confirm step reuses `CleanConfirmationSheet` and a dedicated `CleanupCoordinator`
  instance with the `.selected` kind (`engine.clean`). Review-risk items get the same warning line
  Smart Scan uses, and skipped items are reported honestly in the result banner. Undo comes from the
  existing transaction.

## Blast radius

| Area | Files | Sites |
|---|---|---|
| `AppTheme.` references (unchanged; they adapt through tokens) | 34 | 589 |
| `Color(hex:)` literals in `AppTheme` → swatches | 1 | 10 |
| White/black alpha inside `AppTheme` (Hairline, Fill, table header) | 1 | 8 |
| White/black alpha in views: TextZoomController 1, MaintenanceView 1, HomebrewManagerView 2, PrimaryActionButton 1, GlassCard 1, SidebarView 2, CleanConfirmationSheet 1, AppBackgroundView 1 | 8 | 10 |
| Literal colors: CategoryStyle 9 + 5 system, PrimaryActionButton 1, DeviceBackupsCard 3 `Color.indigo`, HomebrewManagerView 4 `.red`/`.green` | 4 | 22 |
| `PareBrandLogo` gradient literals | 1 | 5 (kept; the brand mark works on both grounds) |
| Disk Analyzer (rewrite plus new files) | 2 → ~10 | — |
| PareCore (`FileSystemUtils`) | 1 | additive only |
| System `.primary`/`.secondary` in AppManager/Homebrew | 2 | 18 (already adaptive; left alone) |

About 40 edit sites in 14 existing files, plus about 14 new files. Before editing any existing symbol,
run `gitnexus_impact` on it, especially `AppTheme`, `CategoryStyle.tint`, `DiskAnalyzerViewModel` and
`CleanupCoordinator`.

## Phased tasks

Legend: **[seq]** must finish before the next group starts. **[par-X]** tasks in group X touch
different files and can run in parallel. **[TDD]** means write the XCTest first and watch it fail.

### Phase 1: Adaptive tokens

- [ ] **1.1 [seq][TDD]** `Tests/PareAppTests/ThemeContrastTests.swift` + `Sources/PareApp/Theme/ThemeSwatch.swift`
  - Tests (table-driven, both modes): `textPrimary`/`textSecondary`/`textTertiary`/`accentText`/`success`/
    `warning`/`review` ≥ 4.5 on `base`, `panel`, `panelSecondary`; `onAccent` ≥ 4.5 on `accent`;
    WCAG formula spot-checked against known pairs (black/white = 21). Separately, one test asserts that the
    dynamic `NSColor` resolves to different components under `.aqua` and `.darkAqua` (via
    `NSAppearance.performAsCurrentDrawingAppearance`).
  - Acceptance: `ThemeSwatch`, `RGBA`, `WCAG.contrastRatio` exist; no UI imports beyond SwiftUI/AppKit.
- [ ] **1.2 [seq]** `Sources/PareApp/Theme/AppTheme.swift`: add `AppTheme.Swatch` with the palette table,
  re-point every semantic color (including Hairline, Fill, `tableHeaderBackground`, `pageGradient`,
  `heroGlow`) and add `onAccent`, `accentText`, `cardFill`, `Shadow`, `Background`. Keep `Brand` raw and
  the `Color(hex:)` initializer.
  - Acceptance: no `Color.white`/`Color.black` in the file; 1.1 tests pass; `make build` is clean.
- [ ] **1.3 [par-A]** `Views/Components/AppBackgroundView.swift`: use the `Background.vignette` and
  `Background.bloom` tokens.
- [ ] **1.4 [par-A]** `Views/Components/GlassCard.swift`: use `cardFill` and `Shadow.card`.
- [ ] **1.5 [par-A]** `Views/Components/PrimaryActionButton.swift`: foreground → `onAccent`; stroke →
  `Hairline.strong`; replace the `.review` gradient literal with `review` → `review.opacity(0.88)`.
- [ ] **1.6 [par-A]** `Views/Components/CleanConfirmationSheet.swift`: `confirmForeground` defaults to
  `AppTheme.onAccent`; update the stale "dark-themed" doc comment.
- [ ] **1.7 [par-A]** `Views/HomebrewManagerView.swift`: two black/white sites → `Fill`/`textSecondary`;
  4 `.red`/`.green` → `review`/`success`.
- [ ] **1.8 [par-A]** `Views/MaintenanceView.swift` (line 240) and `Theme/TextZoomController.swift` HUD
  shadow → tokens. These are two files, but each edit is one line, so they fit in one task.
- [ ] **1.9 [seq]** Light-mode audit. Walk every screen in both appearances and list any leftovers
  in this doc: Smart Scan (idle, scanning, results, empty coaching, FDA card), Apps, Homebrew,
  Maintenance, History, Settings, all sheets, and the text-zoom HUD. Fix only token-level misses here;
  log layout issues for later.

### Phase 2: Category colors, icon tiles, sidebar

- [ ] **2.1 [seq][TDD]** `Tests/PareAppTests/CategoryStyleTests.swift` + rewrite `Sources/PareApp/Theme/CategoryStyle.swift`
  - API: `swatch(for: ScanCategory) -> ThemeSwatch`, `symbol(for:) -> String`, `tint(for:) -> Color`
    (kept for callers), `chartPalette` derived from swatches.
  - Tests: every `ScanCategory.allCases` symbol resolves through `NSImage(systemSymbolName:accessibilityDescription:)`
    (this catches symbols missing on the macOS 13 CI leg); white glyph ≥ 3:1 on each tile in both modes;
    tile ≥ 3:1 on `panel` and `base` in both modes; no two categories share both swatch and symbol.
- [ ] **2.2 [par-B]** New `Views/Components/IconTile.swift`: `IconTile(symbol:swatch:size:)` plus a
  `IconTile(category:size:)` convenience. `#if DEBUG` `IconTile_Previews: PreviewProvider` shows all
  categories in `.light` and `.dark`.
- [ ] **2.3 [par-B][TDD]** New `Theme/DestinationStyle.swift` + `Tests/PareAppTests/DestinationStyleTests.swift`
  (every `AppDestination` has a swatch with glyph contrast ≥ 3:1).
- [ ] **2.4 [par-B]** New `Views/Components/SidebarMaterial.swift`: an `NSViewRepresentable` around
  `NSVisualEffectView` (`.sidebar`, `.behindWindow`, `.followsWindowActiveState`).
- [ ] **2.5 [seq after 2.2–2.4]** `Views/Components/SidebarView.swift`: rows use `IconTile` (22 pt).
  Selection uses a rounded `Fill.selected` wash with `textPrimary` semibold, and the teal stroke and dot
  are dropped. The background is `SidebarMaterial` plus a 4% accent top tint, and the hardcoded
  black edge gradient is replaced with a `Hairline.standard` trailing divider.
  - Acceptance: the sidebar is readable in both modes, with Reduce Transparency both on and off.
- [ ] **2.6 [par-C]** `Views/ScanDashboardView.swift`: the category row dot (around line 442) becomes a 28 pt
  `IconTile`, and finding rows get an 18 pt tile before the title.
- [ ] **2.7 [par-C]** `Views/DeviceBackupsCard.swift`: three `Color.indigo` → `CategoryStyle` for `.deviceBackups`.
- [ ] **2.8 [par-C]** `Views/Components/DisclosureSelectRow.swift` preview: `CategoryStyle.sky` → `IconTile`.
- [ ] **2.9 [par-C]** `Views/Components/ToolShareChart.swift`: keep index colors (tools aren't
  categories), but legend dots use the swatch-derived `chartPalette`; verify the `Canvas` donut in both modes.

### Phase 3: Disk Analyzer

Core logic comes first so the UI tasks can run in parallel against fixed signatures.

- [ ] **3.1 [par-D][TDD]** `Sources/PareCore/Scanning/FileSystemUtils.swift` +
  `Tests/PareCoreTests/DirectoryUsageTests.swift`: add `directoryUsage(url:) -> DirectoryUsage`
  (allocated bytes, item count, newest modification) in a single enumerator pass that keeps the
  cancellation check. `directorySize` is unchanged. Tests build a temp tree with known sizes, counts
  and dates.
- [ ] **3.2 [par-D][TDD]** New `ViewModels/DiskAnalyzer/DiskEntry.swift` (`DiskEntry`: `id` = standardized
  path, url, name, isDirectory, isPackage, sizeBytes, itemCount, modified, `DiskKind`) and
  `DiskKind` (folder, application, image, video, audio, document, archive, diskImage, other, classified by
  `UTType` conformance) + `Tests/PareAppTests/DiskKindTests.swift` (table-driven by extension or UTType).
- [ ] **3.3 [par-D][TDD]** New `ViewModels/DiskAnalyzer/DiskTableQuery.swift` + tests: a pure
  `apply(entries, search, kind, sizeFloor, sortOrder) -> [DiskEntry]`. Search is case- and
  diacritic-insensitive on the name. Size buckets are Any, ≥ 1 MB, ≥ 100 MB and ≥ 1 GB. Sorting covers
  name, size, items, modified and kind, with a stable name tiebreak. The "smaller items" row is always
  last and ignores filters.
- [ ] **3.4 [par-D][TDD]** New `ViewModels/DiskAnalyzer/DiskBreadcrumb.swift` + tests: crumbs from root →
  current, with root == current, trailing slash, `/private/var` standardization, a current URL outside
  the root (rejected), and `up()`/`enter(child)`.
- [ ] **3.5 [par-D][TDD]** New `ViewModels/DiskAnalyzer/DiskReviewResolver.swift` + tests:
  `resolve(entryPath:, findings:) -> .covered([ScanFinding]) | .insideFinding(ScanFinding) | .notCandidate | .noScan`.
  Cases: exact match, both descendant directions, the `uv` vs `uv-backup` sibling, advanced findings
  excluded, and empty findings giving `.noScan`.
- [ ] **3.6 [par-D]** New `ViewModels/DiskAnalyzer/DiskLevelLoader.swift`: a nonisolated `Sendable` loader
  that lists one level, sizes children with `directoryUsage`, reports progress, and caps at 200 plus the
  "smaller items" remainder. It runs off the main actor and caches by path for back/forward.
- [ ] **3.7 [seq]** `ViewModels/CleanupCoordinator.swift`: add `init(engine: CleanupEngine = CleanupEngine())`
  so tests can inject a temp-store engine. This is additive; run `gitnexus_impact` first.
- [ ] **3.8 [seq]** `ViewModels/ScanDashboardViewModel.swift`: expose read-only `latestFindingsSnapshot`.
  `Navigation/AppModelStore.swift`: build `DiskAnalyzerViewModel(findingsProvider: { [scan] in scan.latestFindingsSnapshot })`.
- [ ] **3.9 [seq][TDD]** Rewrite `ViewModels/DiskAnalyzerViewModel.swift` + `Tests/PareAppTests/DiskAnalyzerViewModelTests.swift`:
  root and current URL, crumbs, visible entries (via `DiskTableQuery`), selection, sort order, filters,
  and a review tray (deduplicated by path, with byte and review-risk counts). It owns its own
  `CleanupCoordinator` (`.selected`) and refreshes the level on completion. **Delete `moveToTrash`.**
  Tests cover: drill in and out updates crumbs; the filter and sort pipeline; add-to-review dedup;
  `.notCandidate` and `.noScan` never add; the tray total; `confirm` hands the coordinator the tray's
  findings.
- [ ] **3.10 [par-E]** New `Views/DiskAnalyzer/DiskFilterBar.swift`: search field plus Kind and Size `Picker`s
  in `.menu` style.
- [ ] **3.11 [par-E]** New `Views/DiskAnalyzer/DiskBreadcrumbBar.swift`: clickable crumbs with a 16 pt
  `IconTile`, a back chevron, and the level total.
- [ ] **3.12 [par-E]** New `Views/DiskAnalyzer/DiskAnalyzerTable.swift`: a `Table` with columns Name
  (kind tile + name), Size (share bar + bytes), Items, Modified and Kind; `sortOrder` binding;
  `contextMenu(forSelectionType:primaryAction:)` for drill-in, Reveal, Copy Path and Add to Review;
  `.tableStyle(.inset(alternatesRowBackgrounds: true))`.
- [ ] **3.13 [par-E]** New `Views/DiskAnalyzer/DiskInspectorPane.swift`: 56 pt tile, name (wraps, never
  truncated), size, a details grid (Items, Kind, Modified, Created, Location), and actions
  (Reveal in Finder, Copy Path, Add to Review / disabled reason / "Run Smart Scan").
- [ ] **3.14 [par-E]** New `Views/DiskAnalyzer/DiskReviewTray.swift` + `Theme/DiskKindStyle.swift`: the
  tray bar and the `CleanConfirmationSheet.Config` builder (title, byte total, review warning);
  `DiskKind` → swatch and symbol (folder uses accent, the rest reuse category hues).
- [ ] **3.15 [seq]** Move `Views/DiskAnalyzerView.swift` to `Views/DiskAnalyzer/DiskAnalyzerView.swift`
  and compose the header summary, filter bar, breadcrumb, table | inspector (`HStack`, inspector
  280 pt, collapsible under 1100 pt width), tray, sheet and result banner. Loading, empty and
  error states follow the skill: no skeleton rows. `#if DEBUG` previews use `PreviewProvider`.
- [ ] **3.16 [seq]** Docs: in `CLAUDE.md` Known State, add the adaptive tokens and the Disk Analyzer
  review flow; add a `docs/roadmap.md` entry; tick this plan's boxes.

**Parallel groups:** A (1.3–1.8) after 1.2 · B (2.2–2.4) after 2.1 · C (2.6–2.9) after 2.2 ·
D (3.1–3.6) can start once Phase 1 has merged (3.1–3.5 don't depend on Phase 2) · E (3.10–3.14) after 3.9.
Group C and group D touch disjoint files, so they can overlap. Sequential chains:
1.1→1.2→A→1.9; 2.1→B→2.5; 3.7→3.8→3.9→E→3.15→3.16.
Shared-file conflicts to watch: `AppTheme.swift` (1.2 only), `ScanDashboardView.swift` (2.6 only),
`SidebarView.swift` (2.5 only).

## Verification per phase

Every phase:

- `make build` must compile clean (plain `swift build`; no asset catalogs, no `#Preview`).
- `make test` must pass. On a machine with only the Command Line Tools this fails with
  `no such module 'XCTest'`; that is the known environment limitation, so rely on the CI
  `macos-26` leg and the macOS 13/14 legs.
- `make run-app`, checked in **both** appearances (System Settings → Appearance, toggled while the
  app runs; it must repaint live without a relaunch).

Per-phase manual checks:

- **Phase 1:** Every screen from 1.9 in Light and Dark. Check text legibility, card edges and hairlines,
  CTA text on the seafoam/success fills, sheets, and the text-zoom HUD. No white-on-white or
  navy-on-navy anywhere.
- **Phase 2:** The sidebar with Reduce Transparency on and off, with the window active and inactive.
  Category tiles look identical in Browse by category, finding rows and the Device Backups card. The
  donut legend is correct in both modes.
- **Phase 3:** Choose `~` and drill three levels by double-click; the breadcrumb jumps back. Sort by
  every column. Search plus each Kind and Size filter, including the empty result. Inspector actions:
  Reveal, Copy Path (check the pasteboard), and Add to Review on a Smart-Scan-covered cache, on
  `~/Documents` (disabled with a reason), and with no scan (prompt). Run the review flow to Trash, then
  Undo from the result banner. The UI must not freeze while sizing a large folder (the loader runs off
  the main actor).

## Risks

- **Behavior change:** removing the direct trash means files outside Smart Scan's rules can no longer
  be deleted from the Disk Analyzer (see Q1).
- **Vibrancy:** `.behindWindow` blending depends on the window's layering; `.hiddenTitleBar` and the
  custom `HStack` shell are untested with it. Fallback: the opaque `sidebar` token is one line away.
- **Dynamic `NSColor` in `Canvas`/`GraphicsContext`:** resolution should follow the environment, but
  2.9 must verify it explicitly. The fallback is to read `@Environment(\.colorScheme)` in that one view.
- **`Table` and text zoom:** `pareDisplayScale` fonts apply per cell, but row height follows the
  content, so check at ⌘+ ×3.
- **Sizing cost:** `directoryUsage` walks each child subtree once per level visit. The per-path cache
  bounds repeat visits, but the first visit to `~` stays as expensive as it is today.
- **Visual regressions:** the 589 unchanged token sites all shift in light mode. 1.9 is the safety
  net and cannot be skipped.

## Resolved decisions (Kelvin, 2026-09-26)

1. **Add to Review accepts scan-covered items only.** Deleting arbitrary files from the Disk Analyzer is dropped for this redesign. A "user-chosen file" policy in `ScanPolicy` is logged as a follow-up that **needs a security review** before any work starts.
2. **Sidebar switches to native vibrancy** (`NSVisualEffectView` `.sidebar`) with a faint brand tint.
