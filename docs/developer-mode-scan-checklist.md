# Developer Mode Scan Update Checklist

Based on `docs/app-storage-investigation.md` (2026-04-15), this checklist focuses on improving the `developer` profile scanner for macOS and capturing what can be removed safely vs what should stay review-first.

## 1) Scanner Scope and Category Design

- [x] Add a dedicated developer tooling ruleset for app-specific paths:
  - [x] VS Code
  - [x] JetBrains (GoLand, DataGrip) — review rules for plugins/drivers
  - [x] Docker Desktop — logs (review) + VM data (advanced detect-only)
- [x] Keep large app bundles (`/Applications/*.app`) out of reclaimable results — app bundle paths are not in any scan target directory.
- [x] Preserve current low-risk default behavior:
  - [x] Safe paths are auto-included.
  - [x] Review/high-risk paths are detect-only or explicitly labeled `REVIEW`.

## 2) VS Code Coverage

- [x] Add safe cache rule(s):
  - [x] `~/Library/Caches/com.microsoft.VSCode.ShipIt/*`
  - [x] `~/Library/Application Support/Code/CachedExtensionVSIXs/*`
- [ ] Add review-required state rule(s):
  - [x] `~/Library/Application Support/Code/User/workspaceStorage/*` (age-gated)
  - [x] `~/Library/Application Support/Code/User/History/*`
  - [x] `~/.vscode/extensions/*` (flag as plugin/tooling impact)
- [x] Add optional duplicate-extension analysis for `~/.vscode/extensions`:
  - [x] detect multiple versions of the same extension id (`VSCodeDuplicateExtensionsRule`, risk: `.safe`, 3-day age gate)
  - [x] recommend keeping newest version (flagged in finding reason, e.g. "newer: 2024.2.0")

## 3) JetBrains (GoLand, DataGrip) Coverage

- [ ] Add JetBrains scan targets under `~/Library/Application Support/JetBrains`.
- [ ] Add review-required plugin rules:
  - [x] `*/plugins/*` for active and older IDE version folders
- [ ] Add review-required state/config exclusions:
  - [x] exclude or suppress `*/options/*`, `*/workspace*`, project metadata
- [ ] Add safe cache/log targets (where present):
  - [x] stale version folders in older IDE versions (`JetBrainsStaleVersionRule`, risk: `.review`, 90-day age gate)
- [x] Tag `jdbc-drivers` as review-required in DataGrip paths.

## 4) Docker Desktop Coverage

- [x] Add Docker review rule for logs:
  - [x] `~/Library/Containers/com.docker.docker/Data/log/*`
- [x] Add Docker VM storage as advanced/review-only detect target:
  - [x] `~/Library/Containers/com.docker.docker/Data/vms/0/data/*`
  - ⚠️ **This rule is architecturally wrong — see Phase D for fix**
  - `Docker.raw` (inside `vms/0/data`) is a monolithic VM disk; it contains ALL Docker data including user volumes (e.g. PostgreSQL databases). It cannot be selectively cleaned as a filesystem path. See `docs/developer-mode-phase-d-plan.md`.
- [x] Do not suggest direct file deletion for VM data.
- [x] Add guidance in output to use Docker-native cleanup (`docker system prune`, image/container/volume prune) — printed in CLI when ADVANCED findings detected.
- [x] **Phase D: Remove `DockerVMDataAdvancedRule`** — replaced with CLI hint approach. See `docs/developer-mode-phase-d-plan.md`.

## 5) Policy and Guardrails

- [x] Extend `ScanPolicy` marker strategy for developer-tooling-safe markers.
- [x] Add app-specific sensitive markers to avoid state/credential/session breakage (settings.json, .ssh/, .git-credentials, etc.).
- [x] Keep minimum-age guardrails (default 3 days) for cache-like paths.
- [x] Ensure review/advanced findings are visually separated in CLI and app summaries (risk badges + colored borders).

## 6) UX and Output Improvements

- [x] Add finding reason metadata (e.g. "VS Code extension update cache", "Docker VM disk image").
- [x] Add remediation hints per finding type:
  - [x] SAFE badge in app + [SAFE] tag in CLI
  - [x] REVIEW badge in app + [REVIEW] tag in CLI
  - [x] ADVANCED badge in app + [ADVANCED] tag + Docker-native guidance block in CLI
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
  - [x] Docker logs (review)
  - [x] Docker VM data (advanced/review-only, detect-only)

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

**Must NOT scan as a filesystem target:**
- `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`
- This is a ~1 TB sparse disk image — the entire Docker VM
- Contains ALL Docker data: images, containers, build cache, AND user volumes
- User PostgreSQL databases (and any other Docker volumes) live inside this file
- There is no way to selectively delete "build cache older than X days" from outside the VM
- `DockerVMDataAdvancedRule` reports this file as a finding — that is misleading and must be removed

Correct cleanup method for build cache:
- `docker builder prune --filter "until=168h"` — clears build cache older than 7 days, never touches volumes
- `docker system prune -f` — unused images/containers/networks/build cache; **Pare never passes `--volumes`**
- **Never** Trash `Docker.raw` or run volume prune from Pare — see `docs/features/docker-safety.md`

## Implementation History

- [x] Phase A: VS Code safe cache rules
- [x] Phase B: VS Code + JetBrains review rules and labels
- [x] Phase C: Docker logs (review) + VM detect-only reporting
- [x] Phase D: Docker VM rule fix, JetBrains stale version detection, VS Code duplicate extensions, Docker build cache CLI hint
- **COMPLETE** — all developer scan rules implemented. Remaining work tracked in `docs/user-stories.md`.
