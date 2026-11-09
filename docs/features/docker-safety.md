# Docker Safety Policy (Pare)

**Status:** binding product policy  
**Last updated:** 2026-11-09  

This document defines how Pare treats Docker Desktop storage. Implementation must match these rules.

---

## Core rules

1. **`Docker.raw` is not a normal cache.**  
   Path: `~/Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw`  
   It is the Docker Desktop **Linux VM disk image** (sparse file). It contains:
   - images  
   - containers  
   - build cache  
   - **named volumes** (databases, app data, etc.)

2. **Pare never deletes `Docker.raw` or anything under `…/data/vms/`.**  
   - Scan does **not** surface the VM disk as a finding (no Top Files / large-file rows).  
   - `CleanupEngine` path-blocks `ScanPolicy.isDockerNeverDeletePath` **even if** a finding is mis-tagged `.safe`.

3. **Pare never prunes Docker volumes.**  
   Maintenance / any shell helper must run only:
   ```text
   docker system prune -f
   ```
   **Forbidden:** `--volumes`, `volume prune`, or any flag that removes named volumes.

4. **Safe reclaim is Docker-native only** (inside the VM, not by trashing the sparse file):
   | Command | Effect |
   |---------|--------|
   | `docker system prune -f` | Stopped containers, unused networks, dangling images, dangling build cache |
   | `docker builder prune -f --filter until=168h` | **Default:** image build cache **older than 7 days** |
   | `docker builder prune -f --filter until=24h` | **Low disk:** build cache **older than 1 day** |
   | Docker Desktop UI disk tools | Official product controls |

5. **Build-cache age policy (Maintenance tab):**
   - **Routine:** “Docker Build Cache (>7 days)” — safe default; keeps recent layer cache for daily work.
   - **Low space:** “Docker Build Cache (>1 day, low space)” — more aggressive; still keeps the last day’s cache so an active rebuild is not fully cold.
   - Neither action touches named volumes or `Docker.raw`.
   - Prefer age-filtered `builder prune` over blanket `system prune` when the goal is only build cache.

6. **Size reporting** for files uses **allocated** disk usage (`totalFileAllocatedSize`), not logical EOF (often 1 TB virtual) — still used for cleanup safety paths and other rules.

7. **Reclaimable totals** exclude `.advanced` findings.

8. **Pare reads `settings-store.json` read-only and never edits Docker settings.**  
   The VM memory note below only explains; the user changes the limit in Docker Desktop.

---

## What is cleanable under Docker-related paths

| Path | Risk | Scan finding | Pare cleanup |
|------|------|--------------|----------------|
| `…/com.docker.docker/Data/log/` | `.safe` (aged) | Yes | Yes (Trash logs only) |
| `…/group.com.docker/log/` | `.safe` (aged) | Yes | Yes |
| `…/data/vms/**` including `Docker.raw` | n/a | **No** | **Never** |

---

## VM memory (explain-only)

`DockerMemoryRule` (developer profile, `.diagnostics`, `.advanced`, size 0) warns when Docker's Linux VM may hold too much RAM.

- **Keys** in `~/Library/Group Containers/group.com.docker/settings-store.json` (legacy `settings.json` only when the store is absent): `MemoryMiB` (absent = host RAM ÷ 2), `UseResourceSaver` (absent = on), `KubernetesEnabled` (absent = off; name inferred). Docker Model Runner runs on the host and is ignored.
- **Gate:** swap above 1 GB, and either (A) no useful limit (limit ≥ half of RAM − 256 MiB) with Resource Saver off or Kubernetes on, or (B) `MemoryMiB` unset on a host with 16 GB RAM or less (Resource Saver only stops the VM after idle with no containers). Settings are read first, swap only when the config can fire.
- **Copy:** one line, e.g. "Docker can take up to 8 GB of RAM — no memory limit set"; the tip suggests a limit of max(2, RAM ÷ 4) GB. One button opens `docker-desktop://dashboard/open` (opening Docker Desktop starts its VM).

---

## Code map

| Concern | Location |
|---------|----------|
| Never-delete path check | `ScanPolicy.isDockerNeverDeletePath` |
| Advanced markers | `ScanPolicy.developerDockerAdvancedPathMarkers` |
| Log-only markers | `developerDockerSafePathMarkers` / `developerDockerReviewPathMarkers` (no `/vms`) |
| Scan findings (logs only) | `DockerStorageRule` (does not emit VM disk) |
| VM memory note (settings read-only) | `DockerMemoryRule`, `DockerDesktopSettingsParser` |
| Note button link | `DockerDesktopLinks.dashboard` |
| Cleanup hard block | `CleanupEngine.clean` (before risk / persona checks) |
| System prune args (no volumes) | `MaintenanceRunner.dockerSystemPruneArguments` |
| Builder prune args (7d / 1d) | `MaintenanceRunner.dockerBuilderPruneArguments(untilHours:)` |
| Maintenance actions | `MaintenanceCatalog.dockerPrune` / `dockerBuilderPrune7d` / `dockerBuilderPrune1d` |
| CLI advisory | `PareCLI.printDockerBuildCacheHint` (suggests `until=168h`) |

---

## Planned change (Phase 10)

The selective Docker manager in `docs/roadmap.md` would allow `docker volume rm <exact-name>` for one
unused volume the user selected and confirmed. Update this policy before building it. `volume prune`,
`--volumes`, force removal and touching `Docker.raw` stay forbidden. Removing `docker system prune -f`
early was declined on 2026-10-03.

---

## Historical mistakes (do not repeat)

- **PR #14** reported Docker.raw with **logical** sparse size → fake multi-TB “reclaimable.” Fixed: allocated size + advanced out of totals.  
- **PR #1** correctly removed filesystem delete of the VM disk; re-introduction as detect-only is OK only with advanced + path ban.  
- Putting `/data/vms` in **review** persona markers made the VM tree look like a cleanable persona path; **removed** — only log paths remain in review/safe Docker markers.  
- Never document “volume prune” as a default Pare action.

---

## User-facing copy guidelines

- Prefer: “Docker VM disk (not a cache)… use docker system prune (never --volumes).”  
- Avoid: “Safe to delete”, “cache”, “reclaimable” for Docker.raw.  
- Maintenance description must state volumes are preserved.

---

## Tests that encode this policy

- `Phase7RuleTests.testIsDockerNeverDeletePathCoversVMDiskOnly`  
- `Phase7RuleTests.testDockerSystemPruneArgumentsNeverIncludeVolumes`  
- `Phase7RuleTests.testDockerBuilderPruneArgumentsAgeFilters`  
- `Phase7RuleTests.testDockerBuilderPruneActionsAreCatalogued`  
- `Phase7RuleTests.testDockerReviewMarkersDoNotIncludeVMsTree`  
- `Phase7RuleTests.testDockerStorageRuleDoesNotReportVMDisk`  
- `Phase7RuleTests.testFileSystemUtilsUsesAllocatedSizeForSparseFiles`  
- `DockerDesktopSettingsParserTests`, `DockerMemoryRuleTests`
- `CleanupEngineTests.testCleanBlocksDockerRawPathRegardlessOfRiskLevel`  
- `ScanRunnerTests.testAdvancedFindingsAreExcludedFromReclaimableTotals`  
