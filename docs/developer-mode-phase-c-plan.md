# Developer Mode Phase C Plan (Docker Coverage)

## Goal

Add Docker Desktop scanning coverage to the `developer` profile with safety-first risk labeling:
- Docker logs as `REVIEW`
- Docker VM storage as `ADVANCED` detect-only

## Why Phase C

- Investigation data shows Docker user data is the largest hotspot (`~/Library/Containers/com.docker.docker/...`).
- Logs are often reclaimable with review.
- VM storage contains images/containers/volumes and must not be treated as safe direct-delete data.

## Scope

In scope:
- Add Docker logs rule for:
  - `~/Library/Containers/com.docker.docker/Data/log/*`
  - risk level: `.review`
- Add Docker VM storage rule for:
  - `~/Library/Containers/com.docker.docker/Data/vms/0/data/*`
  - risk level: `.advanced`
- Add policy markers and overrides required for Docker paths without weakening existing guardrails.
- Wire both rules into `RuleCatalog.developer`.
- Add tests for inclusion/exclusion and risk labels.
- Update checklist docs with Phase C status.

Out of scope:
- Cleanup engine implementation (delete/trash/undo).
- Executing Docker prune commands from app/CLI.
- Docker resource attribution (per image/container/volume breakdown).

## Implementation Tasks

1) Extend policy markers in `ScanPolicy`
- Add Docker review marker(s):
  - `/library/containers/com.docker.docker/data/log`
- Add Docker advanced marker(s):
  - `/library/containers/com.docker.docker/data/vms/0/data`
- Add minimal persona protected-path override entries required for Docker detection under `Library/Containers`.
- Keep sensitive marker checks active.

2) Add Docker logs review rule
- New file: `Sources/PareCore/Rules/DockerLogsReviewRequiredRule.swift`
- Category: `.developerPackageCaches`
- Risk: `.review`
- Include logic:
  - allow only Docker log markers
  - pass through existing age behavior (or no age gating if not appropriate)

3) Add Docker VM advanced rule
- New file: `Sources/PareCore/Rules/DockerVMDataAdvancedRule.swift`
- Category: `.developerPackageCaches`
- Risk: `.advanced`
- Include logic:
  - allow only Docker VM markers
  - detect/report only (no cleanup semantics)

4) Wire rules in developer catalog
- Update `Sources/PareCore/Scanning/RuleCatalog.swift`:
  - append Docker review + advanced rules to developer rule list.

5) Add and update tests
- Update `Tests/PareCoreTests/ScanRunnerTests.swift` for:
  - developer catalog contains Docker rule ids
  - logs rule includes Docker log paths and excludes non-target paths
  - VM rule includes VM data paths and excludes non-target paths
  - risk labels: `.review` for logs, `.advanced` for VM

6) Validate with real commands
- Run:
  - `swift test`
  - `make run PROFILE=developer TOP=50`
- Confirm Docker findings appear and are labeled correctly.

7) Update docs/checklists
- Update `docs/developer-mode-scan-checklist.md` to mark Phase C items done.
- Update `docs/checklist.md` progress section.

## Acceptance Criteria

- Developer scan includes Docker logs as `REVIEW` findings.
- Developer scan includes Docker VM data as `ADVANCED` findings.
- No Docker VM paths are presented as safe-delete candidates.
- Tests pass and real scan output reflects expected risk labels.

## UX / Messaging Notes

When presenting Docker VM findings, include explicit guidance:
- Use Docker-native cleanup (`docker system prune`, image/container/volume prune, or Docker Desktop UI).
- Do not remove files directly in `.../Data/vms/0/data`.

## Risks and Mitigations

- Risk: overbroad inclusion under `Library/Containers`.
  - Mitigation: strict Docker-specific marker matching.
- Risk: users interpret `ADVANCED` as directly deletable.
  - Mitigation: clear warning text and Docker-native cleanup guidance.
- Risk: huge result volume from VM internals.
  - Mitigation: keep category/risk labels prominent and rely on existing top/large-file summarization.

## Post-Implementation Finding (2026-06-16)

**`DockerVMDataAdvancedRule` is architecturally wrong and must be removed in Phase D.**

Investigation confirmed that `vms/0/data` contains a single file `Docker.raw` — a ~1 TB sparse monolithic VM disk image. All Docker data lives inside it including user volumes (e.g. PostgreSQL databases). There is no filesystem-level way to selectively clean "build cache older than X days" from macOS. Reporting this file as a scan finding is misleading even at `.advanced` risk level.

See `docs/developer-mode-phase-d-plan.md` for the fix plan.

## Suggested Prompt For Next Implementation Session

```text
Implement Developer Mode Phase C using `docs/developer-mode-phase-c-plan.md` and `docs/developer-mode-scan-checklist.md`.

Requirements:
1) Add Docker logs review rule for `~/Library/Containers/com.docker.docker/Data/log/*`.
2) Add Docker VM advanced rule for `~/Library/Containers/com.docker.docker/Data/vms/0/data/*`.
3) Add required ScanPolicy markers/overrides while preserving existing protection/sensitive guardrails.
4) Wire both rules into developer profile catalog.
5) Add tests for inclusion/exclusion and risk labels.
6) Run `swift test` and `make run PROFILE=developer TOP=50`; summarize relevant Docker findings.
7) Update docs checklists for Phase C progress.

Constraints:
- Do not commit.
- Keep changes minimal and aligned with existing rule conventions.
- Do not add cleanup execution for Docker VM paths; detect/report only.
```
