# Developer Mode Phase D — COMPLETE

All Phase D work is done. Remaining product work is tracked as user stories in `docs/user-stories.md`.

## What Was Done

| Task | Branch | Description |
|------|--------|-------------|
| Remove `DockerVMDataAdvancedRule` | `phase-d/remove-docker-vm-rule` | `Docker.raw` is a monolithic VM disk containing user PostgreSQL volumes — not scannable as files. Rule removed from catalog, policy, and CleanupEngine. |
| JetBrains stale version detection | `phase-d/jetbrains-stale-version-rule` | `JetBrainsStaleVersionRule` (customScan): detects superseded IDE version folders in `~/Library/Application Support/JetBrains`, 90-day age gate, risk `.review`. |
| VS Code duplicate extensions | `phase-d/vscode-duplicate-extensions` | `VSCodeDuplicateExtensionsRule` already existed; added catalog assertion, 5 additional tests (age gate, 3-version ordering, risk level, unparsable dirs, multi-extension), closed checklist items. |
| Docker build cache CLI hint | `phase-d/docker-cli-hint` | `printDockerBuildCacheHint` in `main.swift`: fires on developer profile when Docker Desktop is installed; suggests `docker builder prune --filter "until=168h"` with explicit volumes warning. |

## Key Decisions

- `DockerVMDataAdvancedRule` was wrong at the architectural level — the only correct cleanup path for Docker build cache is via the Docker CLI, not the filesystem.
- `JetBrainsStaleVersionRule` uses `.review` risk (plan said `.safe`) because old IDE version folders can be several GB; user should confirm before removal.
- `VSCodeDuplicateExtensionsRule` uses `.safe` (plan said `.review`) because VS Code only loads the newest version of each extension — older duplicates are definitively inert.
