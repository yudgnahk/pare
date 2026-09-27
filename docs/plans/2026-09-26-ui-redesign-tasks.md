# UI Redesign — Task State

Orchestrator log. Each wave needs Kelvin's approval; one wave per approval.

## Goal

Make Pare look and feel like a native, premium Mac utility (reference:
`assets/2026-09-26-reference-disk-analyzer.png`).

## Scope (approved 2026-09-26)

1. **Light/dark mode** — follow the macOS system appearance; every `AppTheme` token becomes adaptive.
2. **Category color system** — each `ScanCategory` gets a color and a squircle icon tile, used the same way in the sidebar, charts, legends and rows.
3. **Disk Analyzer redesign** — sortable `Table` with columns, a breadcrumb, an inspector pane, and "Add to review" in place of the hover trash button.

Out of scope for now: sizes shown in the sidebar, a stacked bar on the dashboard (these come after 1–3).

## Waves

| # | Wave | Owner | Status | Output |
|---|------|-------|--------|--------|
| 1 | Redesign plan (no code) | planner agent + `macos-swiftui-design` skill | done — awaiting review | `2026-09-26-ui-redesign-plan.md` |
| 2 | Phase 1 — adaptive tokens | tdd-guide agents | done — light mode unverified visually | branch `feat/ui-redesign-phase-1-adaptive-theme` |
| 3 | Review Phase 1 + commit + PR | code-reviewer | done — PR #31 | `../reviews/2026-09-26-ui-redesign-phase-1-review.md` |
| 4 | Phase 2 — category tiles + sidebar vibrancy | tdd-guide agents | implemented + committed, review pending | branch `feat/ui-redesign-phase-2-category-tiles` (stacked on phase 1) |
| 6 | Phase 3 — Disk Analyzer | tdd-guide agents | implemented, review pending | branch `feat/ui-redesign-phase-3-disk-analyzer` (stacked on phase 2, PR #33) |
| 5 | Makefile SDK fix | orchestrator | done — PR #32 | branch `fix/makefile-clt-sdk` |

## Decisions

- 2026-09-26: One branch and one PR per phase, all cut from `master` (Kelvin).

- 2026-09-26: Support both light and dark mode, following the system appearance (Kelvin).
- 2026-09-26: The planner runs as a general-purpose agent in the planner role, because the `everything-claude-code:planner` agent has no Write tool and the plan has to land in a file.
- 2026-09-26: Disk Analyzer "Add to Review" accepts scan-covered items only; arbitrary-file delete is dropped (Kelvin, Q1).
- 2026-09-26: The sidebar switches to native vibrancy with a faint brand tint (Kelvin, Q2).

## Checklist — Wave 4 (Phase 2; task details are in the plan)

- [x] 2.1 CategoryStyle rewrite + tests (seq)
- [x] 2.2 + 2.4 IconTile, SidebarMaterial (par-B)
- [x] 2.3 DestinationStyle + tests (par-B)
- [x] 2.5 SidebarView redesign (after B)
- [x] 2.6 ScanDashboardView tiles (par-C)
- [x] 2.7 + 2.8 + 2.9 DeviceBackupsCard, DisclosureSelectRow preview, ToolShareChart (par-C)
- [x] build clean

## Agent rules (every implementation agent reads this)

- Build: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift build` (or `make build`) must be clean.
- XCTest is unavailable locally. For [TDD] tasks, write the XCTest first, then show RED/GREEN with a throwaway `swift /tmp/*.swift` script that mirrors the pure logic, and delete the script afterwards.
- Edit only the files you own. Report build errors in other files instead of fixing them.
- Comments are one line, why-not-what; a doc comment is one sentence. Previews use `PreviewProvider` inside `#if DEBUG`, never `#Preview`.
- Functions under 50 lines, nesting at most 4 levels, no hardcoded colors (use `AppTheme`/`CategoryStyle` tokens). `ScanPolicy` stays the only place with path-safety logic.
- Before editing an existing symbol, run `npx gitnexus impact <Symbol> --direction upstream` and report the risk.
- Do NOT commit. Tick your checkbox below with a single-line edit; put deviations as one line under `## Notes — Phase 3`.

## Checklist — Wave 6 (Phase 3; task details are in the plan)

- [x] 3.1 + 3.6 directoryUsage (PareCore) + DiskLevelLoader (par-D)
- [x] 3.2 + 3.3 DiskEntry/DiskKind + DiskTableQuery (par-D)
- [x] 3.4 + 3.5 DiskBreadcrumb + DiskReviewResolver (par-D)
- [x] 3.7 + 3.8a CleanupCoordinator engine injection + latestFindingsSnapshot (par-D)
- [x] 3.9 DiskAnalyzerViewModel rewrite + AppModelStore wiring (3.8b), delete moveToTrash (seq)
- [x] 3.10 + 3.11 DiskFilterBar + DiskBreadcrumbBar (par-E)
- [x] 3.12 DiskAnalyzerTable (par-E)
- [x] 3.13 + 3.14 DiskInspectorPane + DiskReviewTray/DiskKindStyle (par-E)
- [x] 3.15 DiskAnalyzerView composition + move (seq)
- [x] 3.16 Docs: CLAUDE.md, roadmap, plan ticks (seq)
- [x] build clean

## Blockers

- None.

## Checklist — Wave 2 (Phase 1; task details are in the plan)

- [x] 1.1 + 1.2 ThemeSwatch/WCAG tests + adaptive AppTheme (seq)
- [x] 1.3 + 1.4 AppBackgroundView, GlassCard (par-A)
- [x] 1.5 + 1.6 PrimaryActionButton, CleanConfirmationSheet (par-A)
- [x] 1.7 + 1.8 HomebrewManagerView, MaintenanceView, TextZoomController (par-A)
- [x] 1.9 Light-mode audit (static grep plus screenshots; walking every screen by hand is left to Kelvin)
- [x] build clean (`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift build`)

**Build blocker (found 2026-09-26):** with the macOS 27 CLT SDK, `@State` is a macro, and its `SwiftUIMacros` plugin only ships with Xcode, so `make build` fails even on master. Workaround: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift build` builds clean. A Makefile fix is proposed as a follow-up.

**Environment:** this machine has Command Line Tools only (no Xcode, no swiftly), so XCTest cannot run here and the RED/GREEN steps cannot be seen locally. Pure logic is checked with a throwaway `swift` script; the XCTest files are verified on CI.

## Notes — Phase 1

- 1.5: hover stroke kept a two-state opacity (0.5/1.0) on `Hairline.strong` rather than a flat token, to preserve the existing hover-brighten effect; also moved the preview's hardcoded `.white` confirm-foreground override to `onAccent`.
- 1.7/1.8: `BrewOperationSheet.lineColor`'s `.red`/`.yellow`/`.cyan` terminal-output colors (brew stdout error/warning/info) were left as-is — they mimic terminal semantics, not app UI state, and the plan's blast-radius count (2 black/white + 4 red/green) excludes them.

## Findings from planning

- Safety bug: the Disk Analyzer hover trash calls `FileManager.trashItem` directly, which bypasses ScanPolicy, exclusions and undo. The same view model builds the tree on the main thread. Both are fixed in Phase 3.
- Contrast: text on the seafoam fill is ~1.8:1, and dark-mode tertiary text is 3.36:1. Both are fixed in Phase 1.

## Checklist — Wave 1

- [x] Plan file written (3 phases, 34 tasks)
- [x] Open questions answered
- [x] Kelvin approved Wave 2

## Follow-ups (not scheduled)

- [ ] **Needs Kelvin:** review PR #33 (Phase 2) and the Phase 3 PR. No code-reviewer agent has run on either yet.
- [ ] **Review note:** `DiskAnalyzerTable` re-implements the `DiskTableQuery` sort comparisons (drift risk). `onRunSmartScan` only calls `runScan()` and does not switch to the Smart Scan tab. `DiskBreadcrumb` hand-maps `/tmp`, `/var` and `/etc` to `/private/...`.
- [ ] **Needs Kelvin:** Jev AI shadow-mode trial; see `docs/research/2026-09-27-jev-ai-evaluation.md`.
- [ ] **Needs security review:** a "user-chosen file" policy in `ScanPolicy` so the Disk Analyzer can delete files the scan did not find.
- [ ] **Needs discussion:** permanent delete (CleanMyMac deletes directly and skips the Trash). Pare's current rule is Trash-only, which is what makes undo possible. Options: keep Trash-only, or add an explicit "Empty Pare items from Trash" step after cleanup.

## Notes — Phase 1

- `make build` (full `PareApp` target) fails on this machine independent of these changes: CLT SDK is `MacOSX27.0` (Swift 6.4 driver) and cannot locate the `SwiftUIMacros` plugin for `@State`/`@StateObject`, so every view using those macros fails to compile. Reproduced identically on the unmodified `feat/ui-redesign` tip via `git stash`. Verified this task's two files compile cleanly in isolation instead: `swiftc -typecheck Sources/PareApp/Theme/ThemeSwatch.swift Sources/PareApp/Theme/AppTheme.swift -target arm64-apple-macos13.0 -sdk $(xcrun --show-sdk-path)` exits clean. This is a toolchain/environment regression beyond Phase 1's scope, not introduced by 1.1/1.2 — needs a machine with a stable Xcode/CLT SDK (or `swiftly`) to confirm `make build`/`make test` end to end.

## Light-mode audit — Phase 1 (1.9)

Static grep of `Sources/PareApp` for `.white`/`.black`/`Color(red:`/`Color(hex:`, literal
`.red`/`.green`/`.yellow`/`.orange`/`.blue`, `.preferredColorScheme`, `NSAppearance(named:`,
`.environment(\.colorScheme)`, `NSColor(`, `Color.gray`, and raw hex literals — everything outside
`Theme/AppTheme.swift` and `Theme/ThemeSwatch.swift`. `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift build` is clean after the fix below (only pre-existing, unrelated warnings in `MaintenanceRunner`/`HomebrewManagerViewModel`).

**Fixed (1 site):**
- `Views/ScanDashboardView.swift:967` — Deep Clean's `CleanConfirmationSheet.Config` hardcoded `confirmForeground: .white`, overriding the `onAccent` default that 1.6 set on the component. In dark mode this sat on `review` (`#FA7A6B`, a light coral), so white-on-light-coral was low-contrast; in light mode `review` is dark enough that it read fine by coincidence. Swapped to `AppTheme.onAccent`.

**Found, left for later (already scheduled in Phase 2 — not touched here to avoid file conflicts):**
- `Theme/CategoryStyle.swift` — 9 literal `Color(red:)` swatches (`lavender`/`sky`/`sand`/`coral`/`sage`/`periwinkle`/`gold`/`violet`/`amber`) plus `Color.indigo`/`.teal`/`.orange` in `tint(for:)` and `chartPalette`. Task 2.1 rewrites this file against the new category swatch table.
- `Views/DeviceBackupsCard.swift` — 3 `Color.indigo` sites (icon, subtitle, tint). Task 2.7.
- `Views/Components/SidebarView.swift:150-151` — hardcoded `Color.black.opacity(0.0…0.18)` right-edge gradient, always dark regardless of appearance. Task 2.5 replaces the whole sidebar background (vibrancy + `Hairline.standard` divider); this file is reserved for that task per the plan's conflict list, so it was not edited here.
- `Views/Components/PareBrandLogo.swift` — 5 gradient literals. Per the plan these are intentionally kept; the brand mark is designed to work on both grounds.
- `Views/HomebrewManagerView.swift:1244-1246` — `.red`/`.yellow`/`.cyan` on `BrewOperationSheet.lineColor` (brew stdout line coloring). Intentionally left as terminal-style output, not app UI state (see existing Phase 1 note above).

No `.preferredColorScheme`, `NSAppearance(named:`, `.environment(\.colorScheme)`, or raw `NSColor(` construction was found outside the theme files, so nothing forces a fixed appearance at the view level.

**Visual check:** launched `.build/out/Products/Debug/PareApp` directly (sandbox disabled per the run-app memory note), found its window via `CGWindowListCopyWindowInfo(.optionAll)`, and captured it with `screencapture -l <windowID>`. Dark-mode capture saved to `docs/plans/assets/2026-09-26-phase1-dark.png` (this machine's real system appearance is Dark) and looks correct: legible text, teal accent, no white-on-white/navy-on-navy.
Forcing Light without touching the system-wide toggle did not work: neither the `-AppleInterfaceStyle Light` process argument (only the literal value `Dark` is special-cased by AppKit; there is no equivalent forcing to Light when the system default is Dark) nor a copy of the `.app` bundle with `NSRequiresAquaSystemAppearance` set to `true` in `Info.plist` (ad-hoc re-signed) changed the rendered theme — the window still drew with the Dark palette. No source override is causing this (grep above confirms no `.preferredColorScheme`/`NSAppearance` calls), so this looks like an environment/OS quirk on this macOS 26 beta build rather than an app bug. Skipped the light screenshot rather than keep a mislabeled dark capture, and did not touch System Settings' appearance.

**Manual checklist for Kelvin (screens not visually verified — grep found no violations in any of them, but they weren't seen rendered in Light):**
- [ ] Smart Scan — idle, scanning, results list, empty/first-run coaching, Full Disk Access card
- [ ] Apps (AppManagerView)
- [ ] Homebrew (formulas, casks, `BrewOperationSheet` terminal pane)
- [ ] Maintenance
- [ ] History
- [ ] Settings
- [ ] Sheets: `CleanConfirmationSheet` (Deep Clean and Selected variants), exclusion list, project scan paths
- [ ] Text-zoom HUD (`TextZoomController`)

## Notes — Phase 3

- 3.7/3.8a: not `[TDD]`-tagged in the plan (glue/DI, no branching logic), so added happy-path XCTest coverage only — `Tests/PareAppTests/CleanupCoordinatorTests.swift` (injected temp-store engine actually used by `confirm`) and `Tests/PareAppTests/ScanDashboardViewModelTests.swift` (snapshot starts empty) — rather than a full RED/GREEN throwaway-script cycle. `swift test` still fails locally on the pre-existing `no such module 'XCTest'` CLT limitation (reproduces identically on unmodified files); relying on CI per the plan's verification section.
- 3.4/3.5: `DiskBreadcrumb.canonicalize` hand-normalizes the `/tmp`, `/var`, `/etc` → `/private/…` indirection because Foundation's `resolvingSymlinksInPath()` deliberately leaves those three unresolved; both files got RED/GREEN via throwaway `/tmp` scripts mirroring `ScanPolicy.isEqualToOrDescendant` and real `ScanFinding`/`RiskLevel` before being deleted.
- 3.2/3.3: `DiskEntry.swift` was written first (ahead of its tests) per the explicit dependency note in this doc, since another agent was blocked on it; `DiskKind`/`DiskTableQuery` still got RED/GREEN via throwaway `/tmp` scripts mirroring the production logic before/after. `DiskEntry.id` and `DiskEntry.remainder(...)` are plain stored fields/factories rather than always auto-deriving `id` from `url`, so `DiskLevelLoader` (3.6) controls the identity string directly. `DiskSizeFloor`/`DiskSortField`/`DiskSortDescriptor` are new types owned by this file, not in the plan's exact-fields list, needed so `apply(...)` has a concrete sort/filter signature; `DiskKind` sorts by `rawValue` string (deterministic, not a specific visual order — no spec requirement either way).

- 3.9: `gitnexus impact DiskAnalyzerViewModel` reports `risk: CRITICAL` / 57 impacted, but almost all hits are file-level `IMPORTS` edges (any file importing the `PareApp` module); the only real `CALLS` dependents are `AppModelStore` (construction) and `DiskAnalyzerView` (usage), both owned/edited by this task. `DiskAnalyzerView` keeps its prior look (flat `List`, hover-reveal, share bar) but now reads one `DiskLevelLoader.Level` at a time instead of a full recursive tree, since the new `DiskEntry`/`DiskLevelLoader` model only loads one directory level per navigation step (no recursive `DiskNode` tree); double-click drills in, the header's new chevron button goes up a level. Full Table/breadcrumb-bar/filter-bar composition is 3.10–3.15, not this task. `XCTest` is unavailable locally (same CLT limitation as 3.7/3.8a and prior phases), so RED/GREEN for the pure tray-dedup/gating logic was demonstrated via a throwaway `/tmp` script (deleted after use) mirroring `DiskReviewResolver` + the tray-merge logic exactly; the full `Tests/PareAppTests/DiskAnalyzerViewModelTests.swift` (crumbs, filter/sort pipeline via real temp directories, dedup, `.notCandidate`/`.noScan`, tray totals, confirm-hands-coordinator-the-tray's-findings via a temp-store `CleanupEngine`) relies on CI to actually run.
- 3.12: new file only, no existing symbol edited, so no `gitnexus impact` was needed. `DiskEntry.modified` is `Date?`, which isn't `Comparable` in this SDK (verified via a throwaway `swiftc -typecheck` snippet), so `Table`'s `sortOrder` uses a private `DiskColumnComparator: SortComparator` instead of `KeyPathComparator`, re-deriving `DiskTableQuery`'s per-field comparisons (its helpers are private) rather than a keypath. The kind→(symbol, swatch) mapping is a closure parameter (`(DiskKind) -> (symbol: String, swatch: ThemeSwatch)`), not a protocol, per the task's "or" — 3.15 can pass `DiskKindStyle.style(for:)` once that file lands. Context menu: single selection shows Open (directories only)/Reveal/Copy Path/Add to Review; multi-selection shows only bulk Add to Review, since Reveal/Copy Path closures are per-entry and copying N paths through a single-path closure would silently overwrite the pasteboard.
- 3.15: `gitnexus impact DiskAnalyzerView`/`DiskAnalyzerViewModel` both report LOW risk once file-level `IMPORTS` noise is filtered out — the only real `CALLS` caller of either is `PareApp.swift` (`MainShellView`/`ContentView`), which this task also owns. Added `pendingCleanup`/`cleanupState`/`canUndo`/`cancelPendingCleanup`/`dismissCleanupResult`/`undoLastCleanup` forwarding properties plus a `coordinator.objectWillChange` → `self.objectWillChange` Combine subscription to `DiskAnalyzerViewModel` (mirrors `ScanDashboardViewModel`'s existing pattern) — without it the view's single `@ObservedObject` never re-renders when the nested `CleanupCoordinator` changes `pending`/`state`. `DiskAnalyzerView` gained one new public param, `onRunSmartScan: () -> Void = {}` (defaulted, so the one existing call site needed a one-line addition, not a signature break); `PareApp.swift` wires it to `{ models.scan.runScan() }` since the Disk Analyzer screen has no reference to `ScanDashboardViewModel` otherwise. "Collapsible under 1100 pt window width" is read from the real `NSWindow.frame.width` (via an `NSWindow.didResizeNotification` observer), not the content pane's own `GeometryReader` width, since the pane width is roughly `windowWidth - 232` (sidebar) and would sit under 1100 even at the 1240 pt default width, which would hide the inspector by default and contradict the mockup. Empty-filter and empty-folder both route through `EmptyStateView` (distinguished by whether search/kind/size filters are active); the table itself is only rendered when `visibleEntries` is non-empty. Verified live via `make run-app`: the header, sidebar and "No directory selected" empty state render correctly in dark mode (screenshot below); a live capture of the populated table/breadcrumb/inspector was attempted with a temporary (reverted) `onAppear` that opened a real directory, but repeated relaunches during capture triggered macOS's launch-throttling (`RBSRequestErrorDomain` "Launchd job spawn failed", then `SIGKILL` on direct exec) and the app could not be relaunched again in this session to retry — a machine/environment constraint, not a code issue; `swift build` stayed clean throughout.
- 3.13/3.14: new files only, no existing symbol edited. `DiskKindStyle` maps `folder` to `AppTheme.Swatch.accentDeep`, not plain `accent` — accent's dark-mode seafoam (`#5CC8BC`) measures ~2.0:1 for a white glyph (below the 3:1 floor), confirmed via a throwaway `/tmp` script mirroring `RGBA`/`WCAG.contrastRatio` before/after (deleted after use); `accentDeep` measures 4.08:1 dark / 8.03:1 light. Every other `DiskKind` reuses an existing `CategoryStyle` swatch (already covered by `CategoryStyleTests`), so `DiskKindStyleTests` only needed to gate the one new pairing. Added `DiskKindStyle.style(for:) -> (symbol:swatch:)` alongside the separate `symbol(for:)`/`swatch(for:)` so it satisfies `DiskAnalyzerTable.kindStyle`'s closure shape (3.12's note anticipated this exact name). `DiskEntry` has no creation-date field, so `DiskInspectorPane` reads `URLResourceValues(.creationDateKey)` from `entry.url` directly for the "Created" row — presentation-only glue, not core logic. Per the task instructions, `.insideFinding` shows explanatory text (which finding covers the entry), not an Add button, even though `DiskAnalyzerViewModel.addToReview` does accept `.insideFinding` (it adds the parent finding, not the entry itself) — the pane is intentionally stricter about what it *offers* than what the VM *accepts*. `swift test` still fails locally on the pre-existing `no such module 'XCTest'` CLT limitation; relying on CI.

## Notes — Phase 2

- 2.1: Kept `CategoryStyle.sky` as a `@available(*, deprecated)` alias (not migrated) because `DisclosureSelectRow`'s preview call site is owned by task 2.8, not 2.1; build is clean, with one expected deprecation warning there.
- 2.2/2.4: `IconTile` preview uses `.environment(\.colorScheme, …)` (no `.preferredColorScheme`, which needs a live window) to render both appearances; `SidebarMaterial` preview only shows the material (no content) since vibrancy needs a real window to render meaningfully.
- 2.7/2.8/2.9: `ToolShareChart` already used `CategoryStyle.chartColor(at:)` for both donut slices and legend dots (no `Color.indigo`/sky present), so 2.9 needed no edit — verified as clean; `sky` deprecation warning is now gone.
- 2.3: Settings gray (`#6B7280`/`#7B8392`) is new; all other destinations reuse an existing `CategoryStyle` swatch pair per the plan's naming (e.g. Smart Scan = userCaches teal), so palettes stay in one system. XCTest is unavailable on this machine, so RED/GREEN was demonstrated via a throwaway `/tmp` script (deleted after use), not a real test run.
- 2.6: Only `CategoryFolderRowView` (private, defined in `ScanDashboardView.swift`) got the 18pt finding-row tile, replacing its static `folder.fill` icon; it needed a new `category` field (from `SummaryItem`/`CategoryToolGroup`, both already carry `ScanCategory`) since `CategoryFolderRow` in `PareCore` doesn't. `largestItemRow`'s `SelectableCandidateRow` is a separate component file outside this task's ownership scope, so its icon was left as-is.
- 2.5: Kept the top accent tint at 4% (spec value) rather than the prior 10%; host's own 1px `Fill.control` divider between `SidebarView` and content (`PareApp.swift`) is a separate element from the new in-file `Hairline.standard` trailing divider — not edited, out of ownership scope for this task.
