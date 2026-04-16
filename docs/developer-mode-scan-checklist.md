# Developer Mode Scan Update Checklist

Based on `docs/app-storage-investigation.md` (2026-04-15), this checklist focuses on improving the `developer` profile scanner for macOS and capturing what can be removed safely vs what should stay review-first.

## 1) Scanner Scope and Category Design

- [x] Add a dedicated developer tooling ruleset for app-specific paths:
  - [x] VS Code
  - [ ] JetBrains (GoLand, DataGrip)
  - [ ] Docker Desktop
- [ ] Keep large app bundles (`/Applications/*.app`) out of reclaimable results unless uninstall flow exists.
- [x] Preserve current low-risk default behavior:
  - [x] Safe paths are auto-included.
  - [ ] Review/high-risk paths are detect-only or explicitly labeled `REVIEW`.

## 2) VS Code Coverage

- [x] Add safe cache rule(s):
  - [x] `~/Library/Caches/com.microsoft.VSCode.ShipIt/*`
  - [x] `~/Library/Application Support/Code/CachedExtensionVSIXs/*`
- [ ] Add review-required state rule(s):
  - [x] `~/Library/Application Support/Code/User/workspaceStorage/*` (age-gated)
  - [x] `~/Library/Application Support/Code/User/History/*`
  - [x] `~/.vscode/extensions/*` (flag as plugin/tooling impact)
- [ ] Add optional duplicate-extension analysis for `~/.vscode/extensions`:
  - [ ] detect multiple versions of the same extension id
  - [ ] recommend keeping newest version

## 3) JetBrains (GoLand, DataGrip) Coverage

- [ ] Add JetBrains scan targets under `~/Library/Application Support/JetBrains`.
- [ ] Add review-required plugin rules:
  - [x] `*/plugins/*` for active and older IDE version folders
- [ ] Add review-required state/config exclusions:
  - [x] exclude or suppress `*/options/*`, `*/workspace*`, project metadata
- [ ] Add safe cache/log targets (where present):
  - [ ] stale cache/temp/log artifacts in older IDE versions
- [x] Tag `jdbc-drivers` as review-required in DataGrip paths.

## 4) Docker Desktop Coverage

- [ ] Add Docker review rule for logs:
  - [ ] `~/Library/Containers/com.docker.docker/Data/log/*`
- [ ] Add Docker VM storage as advanced/review-only detect target:
  - [ ] `~/Library/Containers/com.docker.docker/Data/vms/0/data/*`
- [ ] Do not suggest direct file deletion for VM data.
- [ ] Add guidance in output to use Docker-native cleanup (`docker system prune`, image/container/volume prune) instead of removing files directly.

## 5) Policy and Guardrails

- [x] Extend `ScanPolicy` marker strategy for developer-tooling-safe markers.
- [ ] Add app-specific sensitive markers to avoid state/credential/session breakage.
- [x] Keep minimum-age guardrails (default 3 days) for cache-like paths.
- [ ] Ensure review/advanced findings are visually separated in CLI and app summaries.

## 6) UX and Output Improvements

- [ ] Add finding reason metadata (for example: `cache`, `plugin`, `workspace state`, `docker vm data`).
- [ ] Add remediation hints per finding type:
  - [ ] Safe: direct cleanup candidate
  - [ ] Review: explain impact before deletion
  - [ ] Advanced: use app-native prune flow
- [ ] Add top offender rollups by app (VS Code / GoLand / DataGrip / Docker).

## 7) Validation Checklist

- [x] Run `make test` and ensure rule/policy tests pass.
- [x] Add or update tests for:
  - [x] new rule path matching
  - [x] risk labeling (`safe`, `review`, `advanced`)
  - [x] min-age behavior on newly added cache paths
  - [x] protected path handling
- [x] Run manual checks with `make run PROFILE=developer TOP=50`.
- [ ] Confirm expected findings include:
  - [x] VS Code ShipIt and Cached VSIX
  - [x] JetBrains plugin-heavy folders (review)
  - [ ] Docker logs (review)
  - [ ] Docker VM data (advanced/review-only, detect-only)

## Research: What We Can Remove From These Apps

Use this as removal guidance for developer-mode cleanup recommendations.

### Visual Studio Code

Safe to remove (low impact):
- `~/Library/Caches/com.microsoft.VSCode.ShipIt/*`
- `~/Library/Application Support/Code/CachedExtensionVSIXs/*`

Usually removable with review:
- old entries in `~/Library/Application Support/Code/User/workspaceStorage/*`
- `~/Library/Application Support/Code/User/History/*`
- unused or duplicate versions in `~/.vscode/extensions/*`

Avoid removing blindly:
- broad `~/Library/Application Support/Code/User/*` (settings/state)

### GoLand / DataGrip (JetBrains)

Safe to remove (target stale artifacts):
- older-version cache/temp/log artifacts under `~/Library/Application Support/JetBrains/*`

Usually removable with review:
- unused plugins in:
  - `~/Library/Application Support/JetBrains/GoLand*/plugins/*`
  - `~/Library/Application Support/JetBrains/DataGrip*/plugins/*`

Review before deleting:
- `jdbc-drivers` in DataGrip (`.../DataGrip*/jdbc-drivers/*`)
- active-version IDE state (`options`, workspace/project state)

### Docker Desktop

Safe to remove with review:
- `~/Library/Containers/com.docker.docker/Data/log/*`

Do not remove directly from filesystem (high risk):
- `~/Library/Containers/com.docker.docker/Data/vms/0/data/*`

Preferred cleanup method:
- Docker-native prune commands and Docker Desktop UI cleanup for images, containers, build cache, and volumes.

## Proposed Implementation Order

- [x] Phase A: VS Code safe cache rules (quick win, low risk)
- [x] Phase B: VS Code + JetBrains review rules and labels
- [ ] Phase C: Docker logs + advanced VM detect-only reporting
- [ ] Phase D: app-level rollups and remediation hints in UI/CLI

## Progress Notes (Current)

- [x] Added `VSCodeCachesRule` in developer profile for ShipIt and Cached VSIX paths.
- [x] Added developer-safe markers and protected-path override for Cached VSIX in `ScanPolicy`.
- [x] Fixed duplicate reporting by excluding VS Code cache paths from `UserCachesRule`.
- [x] Validated end-to-end via `swift test` and `make run PROFILE=developer TOP=50`.
- [x] Implemented Phase B review rules and labels for VS Code state and JetBrains plugins.
- [ ] Next up: implement Phase C Docker review/advanced detect-only rules.
