# Docker Safety Policy (Pare)

**Status:** binding product policy  
**Last updated:** 2026-07-13  

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
   | `docker system prune -f` | Stopped containers, unused networks, dangling images, build cache |
   | `docker builder prune …` | Build cache only |
   | Docker Desktop UI disk tools | Official product controls |

5. **Size reporting** for files uses **allocated** disk usage (`totalFileAllocatedSize`), not logical EOF (often 1 TB virtual) — still used for cleanup safety paths and other rules.

6. **Reclaimable totals** exclude `.advanced` findings.

---

## What is cleanable under Docker-related paths

| Path | Risk | Scan finding | Pare cleanup |
|------|------|--------------|----------------|
| `…/com.docker.docker/Data/log/` | `.safe` (aged) | Yes | Yes (Trash logs only) |
| `…/group.com.docker/log/` | `.safe` (aged) | Yes | Yes |
| `…/data/vms/**` including `Docker.raw` | n/a | **No** | **Never** |

---

## Code map

| Concern | Location |
|---------|----------|
| Never-delete path check | `ScanPolicy.isDockerNeverDeletePath` |
| Advanced markers | `ScanPolicy.developerDockerAdvancedPathMarkers` |
| Log-only markers | `developerDockerSafePathMarkers` / `developerDockerReviewPathMarkers` (no `/vms`) |
| Scan findings (logs only) | `DockerStorageRule` (does not emit VM disk) |
| Cleanup hard block | `CleanupEngine.clean` (before risk / persona checks) |
| Prune args (no volumes) | `MaintenanceRunner.dockerSystemPruneArguments` |
| CLI advisory | `PareCLI.printDockerBuildCacheHint` |

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
- `Phase7RuleTests.testDockerReviewMarkersDoNotIncludeVMsTree`  
- `Phase7RuleTests.testDockerStorageRuleDoesNotReportVMDisk`  
- `Phase7RuleTests.testFileSystemUtilsUsesAllocatedSizeForSparseFiles`  
- `CleanupEngineTests.testCleanBlocksDockerRawPathRegardlessOfRiskLevel`  
- `ScanRunnerTests.testAdvancedFindingsAreExcludedFromReclaimableTotals`  
