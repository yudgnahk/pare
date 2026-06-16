# App Storage Investigation (VS Code, GoLand, DataGrip, Docker)

Date: 2026-04-15

## Scope

Investigated disk usage for these apps and their user-data/cache footprints:

- Visual Studio Code
- GoLand
- DataGrip
- Docker Desktop

This report summarizes where space is used and which areas are likely safe vs review-required for cleanup.

## Method Used

1. Ran core scanner with `developer` profile for broad reclaimable candidates.
2. Measured installed app bundle sizes in `/Applications`.
3. Measured app-specific data directories under:
   - `~/Library/Application Support`
   - `~/Library/Caches`
   - `~/Library/Containers`
   - `~/.vscode`
   - `~/.docker`
4. Drilled down into largest subfolders with `du -sh ... | sort -h`.

## High-Level Findings

### Installed app bundles

- `/Applications/Visual Studio Code.app`: `532M`
- `/Applications/GoLand.app`: `3.4G`
- `/Applications/DataGrip.app`: `2.5G`
- `/Applications/Docker.app`: `2.3G`

### User data and cache hotspots

- VS Code data:
  - `~/Library/Application Support/Code`: `2.1G`
  - `~/.vscode/extensions`: `848M`
  - `~/Library/Caches/com.microsoft.VSCode.ShipIt`: `624M`
- JetBrains data (GoLand + DataGrip):
  - `~/Library/Application Support/JetBrains`: `2.3G`
- Docker data:
  - `~/Library/Containers/com.docker.docker`: `10G`
  - Main hotspot: `~/Library/Containers/com.docker.docker/Data/vms/0/data`: `10G`

## App-by-App Breakdown

## 1) Visual Studio Code

Main storage consumers:

- `~/Library/Application Support/Code/WebStorage`: `1.2G`
  - Largest shard: `.../WebStorage/23`: `987M`
- `~/Library/Application Support/Code/User`: `503M`
  - `User/workspaceStorage`: `424M`
  - `User/History`: `50M`
- `~/Library/Application Support/Code/CachedExtensionVSIXs`: `297M`
- `~/.vscode/extensions`: `848M`
  - Several large extensions and duplicate versioned installs were found.
- `~/Library/Caches/com.microsoft.VSCode.ShipIt/update.zKwfDGe`: `624M`

Risk guidance:

- Safe candidates (generally low-impact):
  - `~/Library/Caches/com.microsoft.VSCode.ShipIt/*`
  - `~/Library/Application Support/Code/CachedExtensionVSIXs/*`
  - old `User/workspaceStorage` entries (review by age)
- Review-required:
  - `~/Library/Application Support/Code/User/*` (settings/state/history)
  - `~/.vscode/extensions/*` (removing extensions affects tooling)

## 2) GoLand

Main storage consumers:

- App bundle: `/Applications/GoLand.app`: `3.4G`
- `~/Library/Application Support/JetBrains/GoLand2025.1/plugins`: `993M`
- `~/Library/Application Support/JetBrains/GoLand2024.3/plugins`: `326M`
- Combined GoLand support folders are a large part of JetBrains usage.

Risk guidance:

- Safe candidates:
  - old version caches and temporary IDE metadata where applicable
- Review-required:
  - `.../plugins` folders (removal disables installed plugins)
  - active-version `options`, `workspace`, project state files

## 3) DataGrip

Main storage consumers:

- App bundle: `/Applications/DataGrip.app`: `2.5G`
- `~/Library/Application Support/JetBrains/DataGrip2024.3/plugins`: `914M`
- `~/Library/Application Support/JetBrains/DataGrip2024.3/jdbc-drivers`: `79M`

Risk guidance:

- Safe candidates:
  - stale temporary/cached artifacts in older IDE versions
- Review-required:
  - `plugins` and `jdbc-drivers` (removal impacts features/connectivity)

## 4) Docker Desktop

Main storage consumers:

- App bundle: `/Applications/Docker.app`: `2.3G`
- `~/Library/Containers/com.docker.docker/Data/vms/0/data`: `10G`
  - Contains a single file: `Docker.raw` (sparse disk image, ~1 TB allocated)
  - `Docker.raw` is the entire Docker VM disk — all images, containers, build cache, AND volumes live inside it
  - **User PostgreSQL databases are stored in Docker volumes inside `Docker.raw`**
- `~/Library/Containers/com.docker.docker/Data/log`: `73M`

Risk guidance:

- Safe candidates:
  - Docker logs (`.../Data/log`) after review
- **DO NOT scan or report `vms/0/data` as a filesystem cleanup target:**
  - `Docker.raw` is a monolithic VM disk; it cannot be selectively cleaned from outside
  - There is no filesystem path for "build cache older than X days" — that data is inside the VM
  - Direct deletion destroys all Docker data including user volumes and databases
  - Correct approach: `docker builder prune --filter "until=168h"` or `docker system prune --filter "until=168h"` (never touches volumes unless `--volumes` flag is added)

## Scanner Correlation (Current Rules)

Developer profile scan summary (current core rules):

- Total reclaimable: `4.45 GB`
- Top category: `Developer Package Caches (3.72 GB)`
- VS Code cache artifacts were detected under `User Caches`.
- Docker/JetBrains heavy paths are mostly outside current low-impact rule set and should remain review-first.

## Recommended Cleanup Strategy

1. Start with low-risk, high-return targets:
   - VS Code ShipIt update cache
   - VS Code cached VSIX packages
2. Review extension bloat:
   - remove unused/duplicate VS Code extensions
   - remove unused GoLand/DataGrip plugins from older IDE versions
3. Treat Docker VM data as explicitly out-of-scope for filesystem scanning:
   - `Docker.raw` contains user volumes (e.g. PostgreSQL databases) — cannot be selectively cleaned
   - prune build cache via `docker builder prune --filter "until=168h"` (does NOT touch volumes)
   - prune unused images/containers via `docker system prune --filter "until=168h"` (no `--volumes` flag)
4. Keep app bundles untouched unless uninstalling the app.

## Suggested Next Scanner Enhancements

If desired, add a dedicated "Dev Tooling" pack with:

- VS Code cache rules (safe): ShipIt update cache, CachedExtensionVSIXs
- VS Code state rules (review): workspaceStorage/history
- JetBrains plugin/state rules (review)
- Docker logs (review) and Docker VM storage (advanced/review-only, detect-only)
