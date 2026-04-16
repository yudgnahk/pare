# Developer Mode Phase B Plan (Review Rules)

## Goal

Implement review-focused developer scan coverage for VS Code state and JetBrains (GoLand/DataGrip) plugin-heavy paths, while preserving safety-first behavior and clear risk labeling.

## Why Phase B

- Phase A delivered low-risk cache wins.
- Biggest remaining reclaimable hotspots in investigation are plugin/state folders under VS Code and JetBrains.
- These are not safe auto-clean targets; they need explicit `REVIEW` labeling and guardrails.

## Scope

In scope:
- VS Code review findings:
  - `~/Library/Application Support/Code/User/workspaceStorage/*` (age-gated)
  - `~/Library/Application Support/Code/User/History/*`
  - `~/.vscode/extensions/*`
- JetBrains review findings under `~/Library/Application Support/JetBrains`:
  - `GoLand*/plugins/*`
  - `DataGrip*/plugins/*`
  - `DataGrip*/jdbc-drivers/*`
- Rule-level filtering to suppress known active state/config paths:
  - `*/options/*`
  - workspace/project metadata markers
- CLI/app parity via shared core rules.

Out of scope:
- Docker rules (Phase C)
- duplicate-extension dedupe logic/recommendation engine
- delete/trash behavior changes

## Implementation Tasks

1) Add developer review markers in `ScanPolicy`
- Add `developerReviewPathMarkers` for VS Code and JetBrains review targets.
- Add `developerReviewExclusionMarkers` for state/config suppression.
- Keep existing sensitive marker checks in path matching.

2) Add VS Code review rule
- New rule file: `Sources/App BCore/Rules/VSCodeReviewRequiredStateRule.swift`
- Category: `.developerPackageCaches` (or new category later if needed)
- Risk: `.review`
- Include logic:
  - allow only review markers
  - reject exclusion markers
  - apply default cache-like age policy for `workspaceStorage`

3) Add JetBrains review rule
- New rule file: `Sources/App BCore/Rules/JetBrainsReviewRequiredRule.swift`
- Category: `.developerPackageCaches`
- Risk: `.review`
- Include logic:
  - allow plugin and jdbc-driver markers
  - reject `options/workspace/project state` markers
  - apply age filter where appropriate

4) Wire rules into developer catalog
- Update `Sources/App BCore/Scanning/RuleCatalog.swift` developer list.
- Place review rules after safe rules for predictable ordering.

5) Add/expand tests
- Update `Tests/App BCoreTests/ScanRunnerTests.swift`:
  - developer catalog includes new rule ids
  - VS Code review rule includes intended paths
  - VS Code review rule excludes sensitive/state-disallowed paths
  - JetBrains review rule includes plugin/jdbc paths
  - JetBrains review rule excludes options/workspace paths
  - risk labels remain `.review`

6) Validation run
- `swift test`
- `make run PROFILE=developer TOP=50`
- spot-check findings include review entries for VS Code and JetBrains.

## Acceptance Criteria

- Developer profile reports review findings for VS Code state and JetBrains plugin/jdbc paths.
- Sensitive/state-heavy paths are suppressed according to exclusions.
- No duplicate reporting between baseline and developer rules for the same VS Code cache paths.
- Tests pass and real scan output reflects review-labeled entries.

## Risks and Mitigations

- Over-reporting active state files:
  - mitigate with exclusion markers + sensitive marker guardrails.
- Under-reporting plugin bloat:
  - include broad but explicit plugin markers for versioned IDE folders.
- Category mixing (`safe` and `review` in same category):
  - rely on existing risk label rendering; revisit category split later if UX needs it.

## Suggested Prompt For Next Implementation Session

Use this prompt to start Phase B quickly:

```text
Implement Developer Mode Phase B based on `docs/developer-mode-phase-b-plan.md` and `docs/developer-mode-scan-checklist.md`.

Requirements:
1) Add review-only scan rules for:
   - VS Code: workspaceStorage, History, .vscode/extensions
   - JetBrains: GoLand*/plugins, DataGrip*/plugins, DataGrip*/jdbc-drivers
2) Add exclusion markers to suppress active state/config paths (options/workspace/project metadata).
3) Keep safety guardrails and risk labeling (`REVIEW`) in shared core policy.
4) Wire new rules into developer profile catalog.
5) Add/extend tests in `Tests/App BCoreTests/ScanRunnerTests.swift` for path inclusion/exclusion and risk labels.
6) Run `swift test` and `make run PROFILE=developer TOP=50` and summarize relevant findings.

Constraints:
- Do not commit.
- Preserve existing conventions in core rules.
- Keep changes minimal and focused on Phase B.
```
