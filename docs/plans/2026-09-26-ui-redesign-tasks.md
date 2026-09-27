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
| 5 | Makefile SDK fix | orchestrator | done — PR #32 | branch `fix/makefile-clt-sdk` |

## Decisions

- 2026-09-26: One branch and one PR per phase, all cut from `master` (Kelvin).

- 2026-09-26: Support both light and dark mode, following the system appearance (Kelvin).
- 2026-09-26: The planner runs as a general-purpose agent in the planner role, because the `everything-claude-code:planner` agent has no Write tool and the plan has to land in a file.
- 2026-09-26: Disk Analyzer "Add to Review" accepts scan-covered items only; arbitrary-file delete is dropped (Kelvin, Q1).
- 2026-09-26: The sidebar switches to native vibrancy with a faint brand tint (Kelvin, Q2).
- 2026-09-27: The 4% tint looked too washed out next to the old brand gradient. Keep vibrancy, but make the brand tint much stronger (~15–20%, gradient reaching deeper). Icon tiles get a subtle top-to-bottom gradient plus a highlight edge (Kelvin).

## Checklist — Wave 4 (Phase 2; task details are in the plan)

- [x] 2.1 CategoryStyle rewrite + tests (seq)
- [x] 2.2 + 2.4 IconTile, SidebarMaterial (par-B)
- [x] 2.3 DestinationStyle + tests (par-B)
- [x] 2.5 SidebarView redesign (after B)
- [x] 2.6 ScanDashboardView tiles (par-C)
- [x] 2.7 + 2.8 + 2.9 DeviceBackupsCard, DisclosureSelectRow preview, ToolShareChart (par-C)
- [x] build clean

## Checklist — Phase 2 polish (on the #33 branch, then merged into #34)

- [x] Stronger sidebar brand tint over vibrancy
- [x] Icon tile gradient + highlight, glyph contrast ≥ 3:1 at the lightest stop
- [x] build clean + dark screenshot

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

- [ ] **Needs Kelvin:** review Phase 2 (code-reviewer), then push and open the stacked PR on top of #31.
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

## Notes — Phase 2 polish

- Sidebar tint: accent 0.18 -> 0.08 -> accentDeep 0.05 (top to bottom), over `SidebarMaterial` vibrancy. `textSecondary` stays >= 4.5:1 (worst case 4.89:1 light mode) against the opaque `AppTheme.Swatch.sidebar` approximation blended with the top stop.
- Icon tile gradient: lighten top stop 6%, darken bottom stop 8% (not the 8-12% spec target — `userCaches`' dark swatch only clears 3:1 white-glyph contrast up to ~7% lightening; worst case at 6% is 3.06:1). RED/GREEN shown via throwaway `/tmp` script (XCTest unavailable on this machine) before writing `IconTileGradientTests.swift`.

## Notes — Phase 2

- 2.1: Kept `CategoryStyle.sky` as a `@available(*, deprecated)` alias (not migrated) because `DisclosureSelectRow`'s preview call site is owned by task 2.8, not 2.1; build is clean, with one expected deprecation warning there.
- 2.2/2.4: `IconTile` preview uses `.environment(\.colorScheme, …)` (no `.preferredColorScheme`, which needs a live window) to render both appearances; `SidebarMaterial` preview only shows the material (no content) since vibrancy needs a real window to render meaningfully.
- 2.7/2.8/2.9: `ToolShareChart` already used `CategoryStyle.chartColor(at:)` for both donut slices and legend dots (no `Color.indigo`/sky present), so 2.9 needed no edit — verified as clean; `sky` deprecation warning is now gone.
- 2.3: Settings gray (`#6B7280`/`#7B8392`) is new; all other destinations reuse an existing `CategoryStyle` swatch pair per the plan's naming (e.g. Smart Scan = userCaches teal), so palettes stay in one system. XCTest is unavailable on this machine, so RED/GREEN was demonstrated via a throwaway `/tmp` script (deleted after use), not a real test run.
- 2.6: Only `CategoryFolderRowView` (private, defined in `ScanDashboardView.swift`) got the 18pt finding-row tile, replacing its static `folder.fill` icon; it needed a new `category` field (from `SummaryItem`/`CategoryToolGroup`, both already carry `ScanCategory`) since `CategoryFolderRow` in `PareCore` doesn't. `largestItemRow`'s `SelectableCandidateRow` is a separate component file outside this task's ownership scope, so its icon was left as-is.
- 2.5: Kept the top accent tint at 4% (spec value) rather than the prior 10%; host's own 1px `Fill.control` divider between `SidebarView` and content (`PareApp.swift`) is a separate element from the new in-file `Hairline.standard` trailing divider — not edited, out of ownership scope for this task.
