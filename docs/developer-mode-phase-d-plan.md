# Developer Mode Phase D Plan (Docker Rule Fix + Remaining Items)

## Goal

Fix the flawed `DockerVMDataAdvancedRule` and complete the remaining developer-mode items left open from Phases B–C.

## Why Phase D

- Investigation on 2026-06-16 confirmed that `DockerVMDataAdvancedRule` is architecturally wrong:
  - It targets `~/Library/Containers/com.docker.docker/Data/vms/0/data`
  - That directory contains a single file: `Docker.raw`, a sparse disk image (~1 TB on this machine)
  - `Docker.raw` is the entire Docker VM disk — all images, containers, build cache, AND user volumes live inside it
  - **User PostgreSQL databases are stored in Docker volumes inside `Docker.raw`**
  - There is no way to selectively clean "build cache older than X days" via a filesystem path on macOS Docker Desktop
  - Even though `.advanced` risk prevents CleanupEngine from deleting it, reporting it as a scan finding is misleading and could prompt users to delete the file outside the app
- Remaining open items from Phases B and C (rollups, duplicate extension detection, JetBrains safe cache targets) belong here.

## Scope

### 1. Remove `DockerVMDataAdvancedRule` (Critical)

- Delete `Sources/CleanMyMacCore/Rules/DockerVMDataAdvancedRule.swift`
- Remove the rule from `RuleCatalog.developer`
- Remove `developerDockerAdvancedPathMarkers` from `ScanPolicy` (and its entry in `personaProtectedPathOverrides`)
- Keep `DockerLogsReviewRequiredRule` — log files at `Data/log/` are genuinely cleanable

### 2. Add CLI Hint Output for Docker Build Cache

- When the developer profile scan runs and Docker Desktop data directory exists, emit a CLI hint (not a scan finding) suggesting:
  ```
  Docker build cache: run `docker builder prune --filter "until=168h"` to remove build cache older than 7 days (does not touch volumes).
  ```
- This should NOT create a `ScanFinding` — it is advisory output only
- Possible approach: a separate `ScanHint` model or just a post-scan advisory message in CLI output

### 3. JetBrains Safe Cache Targets (from Phase B backlog)

- Add a `JetBrainsSafeCachesRule` for stale artifacts in older IDE version folders under `~/Library/Application Support/JetBrains`
- Target: version-stamped folders older than 90 days (e.g. `GoLand2024.1/`, `DataGrip2023.3/`) — their entire subtree is safe once the IDE version is replaced
- Risk: `.safe` (auto-clean candidate)
- Keep exclusion markers: `options/`, workspace, project metadata, active version

### 4. VS Code Duplicate Extension Detection (from Phase B backlog)

- Implement `VSCodeDuplicateExtensionsRule` using `customScan`
- Scan `~/.vscode/extensions/` and detect multiple installed versions of the same extension ID
- Mark older versions as `.review` findings (keep newest, flag duplicates)
- This is version deduplication logic, not a file-include filter — must use `customScan`

### 5. Top Offender Rollups by App (from Phase D partial backlog)

- Add per-app summary rollups in CLI output for developer profile:
  - VS Code total
  - JetBrains (GoLand + DataGrip combined) total
  - Docker logs total
- Already tracked as remaining item in `developer-mode-scan-checklist.md`

## Implementation Order

1. Remove `DockerVMDataAdvancedRule` (unblock the misleading finding — do first)
2. JetBrains safe cache targets (quick win, low risk)
3. VS Code duplicate extension detection (`customScan` logic)
4. CLI hint for Docker build cache
5. Per-app rollup summaries in CLI

## Acceptance Criteria

- Developer scan no longer reports `Docker.raw` or any `vms/0/data` paths
- `swift test` passes with updated tests removing Docker VM rule assertions
- Docker log findings still appear as `REVIEW`
- JetBrains safe cache findings appear for stale older-version folders
- VS Code duplicate extension findings appear as `REVIEW` when multiple versions of the same extension are installed
- CLI developer scan output includes Docker build cache advisory hint when Docker is installed

## Risks and Mitigations

- Removing `DockerVMDataAdvancedRule` loses detection of Docker space usage:
  - Mitigate by surfacing advisory hint and keeping the log rule
  - The `Docker.raw` file is not meaningfully actionable from a filesystem cleanup perspective
- JetBrains version-folder detection may flag active version:
  - Mitigate by using install-date heuristics or explicitly excluding the newest-stamped folder

## Suggested Prompt For Next Implementation Session

```text
Implement Developer Mode Phase D based on `docs/developer-mode-phase-d-plan.md`.

Priority order:
1. Remove `DockerVMDataAdvancedRule` entirely:
   - Delete `Sources/CleanMyMacCore/Rules/DockerVMDataAdvancedRule.swift`
   - Remove from `RuleCatalog.developer`
   - Remove `developerDockerAdvancedPathMarkers` from `ScanPolicy` and its `personaProtectedPathOverrides` entry
   - Update tests in `ScanRunnerTests.swift` to remove Docker VM rule assertions
2. Add `JetBrainsSafeCachesRule` for stale older-version IDE folders (risk: `.safe`, age-gated at 90 days)
3. Add `VSCodeDuplicateExtensionsRule` using `customScan` for duplicate extension version detection (risk: `.review`)
4. Add CLI advisory hint in `main.swift` when Docker is installed: suggest `docker builder prune --filter "until=168h"`

Constraints:
- Do not commit.
- Do not modify cleanup engine behavior.
- Keep `DockerLogsReviewRequiredRule` intact.
- Run `swift test` and `make run PROFILE=developer TOP=50` after each step; report findings.
```
