# Pare (Pure Swift) - Phase 2 Plan

## Phase Goal
Ship a native macOS SwiftUI app target that reuses the existing `PareCore` scanner stack, while keeping CLI parity for debugging and result validation.

Deliver a polished, visually rich, premium-feeling UI inspired by Pare-level quality, with strong visual hierarchy, motion, and macOS-native fit and finish.

## Why This Phase
- Convert the Phase 1 scanner MVP into a user-facing app shell.
- Prove architecture reuse (`PareCore` shared by app and CLI) before adding cleanup workflows.
- Establish confidence that UI-driven scans produce the same totals as CLI runs.

## Scope

### In Scope
- Add a macOS SwiftUI app target (for example, `PareApp`) in the same workspace/package.
- Reuse `PareCore` directly from the app target with no duplicated scan logic.
- Keep `pare-cli` as a diagnostic runner on top of the same core module.
- Introduce app state/view model wrapping `ScanRunner` and `RuleCatalog`.
- Implement profile selector UI for Baseline and Developer profiles.
- Implement scan trigger UI with loading/progress presentation.
- Implement results UI showing:
  - total reclaimable size
  - category summaries
  - top file/path candidates
  - per-category file lists filtered to files larger than 50 MB
  - quick action to reveal selected file in Finder
- Build a high-fidelity visual design system for the app experience, including:
  - premium typography scale and spacing system
  - layered backgrounds/materials and depth
  - polished cards, charts, and iconography
  - smooth motion for scan lifecycle and results reveal
  - responsive/adaptive behavior for common macOS window sizes
- Add UI quality bar criteria to ensure the app is beautiful, intentional, and not a generic utility layout.
- Add local run path for app target in docs and `Makefile`.
- Manually verify CLI and app produce consistent summary totals for the same profile.
- Restrict scan focus to low-impact cleanup candidates that should not affect app functionality, including cache/temporary/log-like files.
- Apply a default age guardrail for cache-like targets (only include candidates older than 3 days unless rule explicitly requires different behavior).

### Out of Scope
- New persona rule packs beyond what already exists.
- Any delete/trash/undo pipeline implementation.
- Full onboarding flow and advanced personalization settings.
- Scheduling, background scans, or release/notarization work.
- Scanning business-critical app data locations (documents, databases, project source, active app state files).

## Implementation Plan

### 1) App Target and Shared Core Wiring
- Create `PareApp` target and entry point.
- Link/import `PareCore` directly.
- Add a minimal dependency boundary check to ensure scanning logic lives only in core.

### 2) State Management and Scan Orchestration
- Add a `ScanViewModel` (or equivalent) that:
  - exposes selected profile
  - starts async scans
  - tracks `isScanning`, progress state, and error state
  - publishes formatted result summaries for UI
- Map profile selection to existing `RuleCatalog` profile definitions.
- Add candidate filtering policy in the scan pipeline:
  - size threshold for UI listing: include files greater than 50 MB in per-category file lists
  - age threshold for cache-like files: include only files older than 3 days by default
  - safety-first path filtering: include only low-impact cleanup locations

### 2.1) Scan Safety and Filtering Spec (Concrete Defaults)
- Define shared constants in core (single source of truth):
  - `largeFileThresholdBytes = 50 * 1024 * 1024`
  - `defaultCacheMinAge = 3 days`
- Apply low-impact scanning policy via rule and path constraints:
  - include cache/temp/log/crash-like targets only
  - exclude obvious app-critical paths (Documents, source repos, app data stores)
  - do not include user-auth/session/private data artifacts
- Keep parity-friendly behavior:
  - compute totals from full eligible findings
  - apply `> 50 MB` filter only for large-file detail list UI (not summary totals)

### 2.2) Finder Reveal Integration
- Add Finder reveal action for each large-file row:
  - use `NSWorkspace.shared.activateFileViewerSelecting([url])`
  - disable/hide action when path no longer exists
  - show non-blocking error state if reveal fails

### 3) SwiftUI Screens
- Build a single primary screen first (can later expand to multi-view navigation):
  - Profile selector (Baseline/Developer)
  - Scan action button
  - Scan status/loading indicator
  - Results summary cards/list for totals and categories
  - Top results list by reclaimable size
  - Category detail section listing files larger than 50 MB
  - "Show in Finder" action on listed file rows
- Keep UI intentionally thin and driven by view model state.

### 3.1) Visual Design Direction (Beautiful UI Requirement)
- Define a distinct visual language before implementation:
  - glass/material surfaces, soft gradients, subtle noise, and depth layers
  - semantic color tokens for safe/warning/high-risk categories
  - branded icon style and consistent corner radii/shadows
- Build reusable UI primitives:
  - `AppBackground`, `GlassCard`, `MetricTile`, `CategoryBar`, `PrimaryActionButton`
  - shared animation presets (spring/opacity/slide) for consistent motion feel
- Add delightful but purposeful animations:
  - scan start transition and active scanning pulse/flow
  - staggered result card entrance after scan completion
  - smooth number transitions for reclaimable size counters
- Ensure beauty does not reduce clarity:
  - maintain readability at all times
  - keep scan action and critical metrics prominent
  - preserve fast perceived performance by avoiding heavy visual overdraw

### 4) CLI Parity and Dev Workflow
- Keep CLI command path intact and confirm it still runs with shared core.
- Add/update `Makefile` target(s) for launching the app locally.
- Update docs with run instructions for both app and CLI comparison flow.

### 5) Validation and Manual QA
- Run `make build` and `make test` after integration.
- Perform side-by-side checks:
  - same machine/session
  - same profile
  - compare total reclaimable size and key category totals
- Record mismatches and resolve deterministic issues (sorting, path normalization, filtering differences).

### 5.1) Manual QA Test Matrix
- Baseline profile:
  - verify category summaries render and totals are stable between repeated scans
  - verify large-file list shows only entries `> 50 MB`
  - verify Finder reveal opens correct file selection
- Developer profile:
  - verify developer categories are included and sorted by reclaimable size
  - verify large-file threshold and Finder reveal behavior are identical to baseline
- Safety checks:
  - verify cache-like entries younger than 3 days are excluded by default
  - verify business-critical locations are not surfaced in results
- Regression checks:
  - run CLI with same profile and compare summary totals against app output
  - verify behavior when a listed file is removed before Finder reveal action

## Implementation Backlog (Remaining)

### A) Core/Policy
- Verify all existing and future rules consistently use shared `ScanPolicy` helpers.
- Extend tests to cover additional rule-specific edge cases (missing modification date, mixed path markers).

### B) UI/Interaction
- Add category-level expand/collapse for large-file sections to improve dense result browsing.
- Add optional sort controls (size, last used) for large-file rows.
- Refine Finder reveal feedback copy and styling for better trust/clarity.

### C) CLI/Docs
- Add app screenshot/recording references for release notes handoff (optional).

## Current Status Snapshot
- Completed:
  - SwiftUI app target created and integrated with package
  - Shared core wiring in app via `PareCore`
  - Initial premium UI primitives and dashboard implemented
  - Shared scan policy implemented (`50 MB` large-file threshold, `3-day` cache-like age guardrail, low-impact path filtering)
  - Grouped large-file sections (`> 50 MB`) implemented in app UI
  - Finder reveal action implemented with missing-file feedback handling
  - CLI output aligned with large-file grouping policy
  - Core tests expanded for age guardrail, large-file threshold, and protected-path exclusion
  - `Makefile` app run target added (`make run-app`)
  - Manual parity notes recorded for Baseline and Developer profiles in docs
  - Build and tests pass locally
- Remaining to fully close Phase 2:
  - optionally tighten UX polish for dense large-file browsing states

## Deliverables
- New SwiftUI macOS app target integrated in the existing workspace.
- Shared-core architecture verified (app + CLI both use `PareCore`).
- Working scan flow in app for Baseline and Developer profiles.
- Results presentation with total reclaimable, category summaries, and top files.
- Per-category large-file list (greater than 50 MB) with Finder reveal action.
- Default low-impact scan policy enforcing 3-day age minimum for cache-like cleanup candidates.
- High-fidelity, premium visual UI pass with reusable design primitives and motion patterns.
- Updated `Makefile` and docs for local app execution.
- Manual parity verification notes for app vs CLI totals.
- Added test coverage for age guardrail, large-file filtering, and protected-path exclusion.

## Definition of Done
- App target builds and launches locally.
- App scan succeeds for Baseline and Developer profiles.
- No scanner logic duplicated outside `PareCore`.
- CLI remains functional and uses same core code path.
- App and CLI summary totals are consistent for at least one controlled verification run per profile.
- Result lists show only low-impact candidates and exclude obvious app-critical data paths.
- Category detail list only includes files larger than 50 MB and supports opening selected path in Finder.
- Cache-like candidates respect default minimum age of 3 days.
- UI meets beauty/quality bar:
  - cohesive visual direction across all primary states
  - smooth, intentional animations with no distracting motion
  - polished layout quality comparable to top-tier macOS utilities
- Checklist items under Phase 2 are complete or explicitly documented with follow-up notes.

## Risks and Mitigations
- UI/core coupling risk: keep all scan decisions and rule resolution in core + view model adapter.
- Async state drift risk: centralize scan state transitions in one view model state machine.
- Parity mismatch risk: compare on same profile/session and normalize display vs raw-byte calculations.
- Visual scope creep risk: define a strict design token system and reusable primitives early to avoid one-off styling.
- Performance risk from rich visuals: profile SwiftUI rendering and limit expensive blur/material layers in dense lists.
- Scope creep risk: defer cleanup engine and non-essential settings to later phases.

## Suggested Execution Order
1. Apply final UX polish for large-file browsing and Finder feedback states.
