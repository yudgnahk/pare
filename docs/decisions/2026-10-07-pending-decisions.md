# Pending decisions — 2026-10-07

Each item has context, options, evidence measured on the maintainer's Mac today, a
recommendation, and what changes in code for each pick. Every measurement was read-only:
`stat`/`du` with a 20 s cap per folder, bounded walks, and no writes outside a temp dir.

**Machine state:** 8.0 GB free of 245 GB (3.3 %, `volumeAvailableCapacityForImportantUsage`).
Under the Phase 12 spec that is the *critical* pressure tier.

## Quick answers

| # | Decision | Recommendation |
|---|---|---|
| A | Cache activity cut-offs N/M; one-click override for hot | Keep **N = 3, M = 30**. Hot rows stay **unchecked but selectable, one click per row**. |
| B | Dependency folders of inactive projects (12.2) | Keep tiers **14 / 7 / 3**. **Require a lockfile** at first. Report broken venvs, but **defer the package-list export**. **Land after #50** and the free-space seam. Ship in 4 slices. |
| C | Seam consolidation | **After** merging the stack. Do 6 small refactor PRs, starting with `FindingKey` + `ScanFinding.replacing` (which fixes a real `GoCachesRule` bug), then a test fixture, free space, processes, lsof, and finding insights. |
| D1 | #49: Google/Mozilla prefix protection only at scan time | **Intended. Keep it**: `ProductivityCachesRule` cleans `com.google.drivefs.finderext` on purpose. Add a one-line comment. |
| D2 | #64: `brew cleanup` deletes directly | **Accept.** Homebrew's own store, a fresh preview and an explicit confirmation. Document the native-command exception, with no Undo. |
| D3 | #57: version-shaped items only pass the version-sibling gate | **Accept.** It can only narrow (fail closed). Follow up with a clearer skip reason. |

---

## A. Cache activity thresholds: N (hot) and M (cold)

**Context.** Draft PR #67 labels `.safe`/`.review` cache findings as hot, warm or cold from
their newest mtime. It samples to depth 2, at most 2,000 entries, 0.25 s per finding and 3 s
in total. The labels are display only for now. The next slice turns them into behaviour:
hot is skipped, cold is `.safe` and preselected, warm is `.review`. N and M have to be fixed
before that slice.

### Evidence

134 cache folders were measured: every entry of `~/Library/Caches`, every `~/.cache/*`, and the
developer caches (npm, pnpm, bun, Yarn, Cargo, Go, Homebrew, Xcode, CoreSimulator). The sampler
from #67 was re-implemented in Python: root mtime plus entries at depth 1–2, pre-order, with
the same cap. The 20 largest:

| Cache | Size | Newest entry (days) | Sampled | (1,14) | (3,30) | (7,60) | (7,90) |
|---|---:|---:|---|---|---|---|---|
| `~/Library/Caches/go-build` ¹ | 4.6 GB | 0.0 | 2000 (cap) | hot | hot | hot | hot |
| `~/.cache/codex-runtimes` ² | 1.5 GB | 58.3 | 4 | cold | cold | warm | warm |
| `~/Library/pnpm/store` | 1.4 GB | 0.0 | 8 | hot | hot | hot | hot |
| `~/.cache/uv` ¹ | 1.3 GB | 0.1 | 101 | hot | hot | hot | hot |
| `~/go/pkg/mod/cache` ¹ | 859 MB | 0.1 | 42 | hot | hot | hot | hot |
| `~/Library/Caches/ms-playwright` | 849 MB | 0.0 | 38 | hot | hot | hot | hot |
| `~/.cargo/registry` | 436 MB | 0.1 | 7 | hot | hot | hot | hot |
| `~/.cache/kilo` ² | 424 MB | 84.8 | 19 | cold | cold | cold | warm |
| `~/.cache/github-copilot` ² | 274 MB | 246.0 | 18 | cold | cold | cold | cold |
| `~/Library/Caches/pnpm` | 198 MB | 0.0 | 4 | hot | hot | hot | hot |
| `~/.cache/hyperframes` ² | 198 MB | 73.5 | 5 | cold | cold | cold | warm |
| `~/.bun/install/cache` | 184 MB | 0.1 | 506 | hot | hot | hot | hot |
| `~/.yarn/berry/cache` ² | 156 MB | 153.6 | 452 | cold | cold | cold | cold |
| `~/.npm/_cacache` | 128 MB | 0.0 | 93 | hot | hot | hot | hot |
| `~/.cache/node` | 102 MB | 0.1 | 3 | hot | hot | hot | hot |
| `~/.cache/huggingface` ² | 88 MB | 13.7 | 6 | warm | warm | warm | warm |
| `~/Library/Caches/node-gyp` | 62 MB | 0.1 | 3 | hot | hot | hot | hot |
| `~/Library/Caches/CodexBar` | 58 MB | 0.0 | 12 | hot | hot | hot | hot |
| `~/Library/Caches/GeoServices` | 50 MB | 0.0 | 163 | hot | hot | hot | hot |
| `~/.npm/_npx` | 40 MB | 0.1 | 8 | hot | hot | hot | hot |

¹ Never gets a label: never-clean after #46 (Go) or `.advanced` (uv).
² No rule on `integration/2026-10-07` reports this folder today.
Xcode `DerivedData`, `iOS DeviceSupport` and `CoreSimulator/Caches` exist but are empty on this machine.

Totals per (N, M):

| (N, M) | All 134 folders (13.3 GB): hot / warm / cold | Folders ≥ 100 MB (15, 12.8 GB): hot / warm / cold |
|---|---|---|
| (1, 14) | 66 · 10.5 GB / 33 · 117 MB / 35 · 2.6 GB | 10 · 10.2 GB / 0 / 5 · 2.6 GB |
| **(3, 30)** | 92 · 10.5 GB / 14 · 93 MB / 28 · 2.6 GB | 10 · 10.2 GB / 0 / 5 · 2.6 GB |
| (7, 60) | 95 · 10.5 GB / 16 · 1.7 GB / 23 · 1.1 GB | 10 · 10.2 GB / 1 · 1.5 GB / 4 · 1.1 GB |
| (7, 90) | 95 · 10.5 GB / 24 · 2.3 GB / 15 · 442 MB | 10 · 10.2 GB / 3 · 2.2 GB / 2 · 430 MB |

What the numbers say:

1. **The ages are bimodal.** Newest-entry ages per folder: ≤ 1 d: 66, 1–3 d: 26, 3–7 d: 3,
   7–14 d: 4, 14–30 d: 7, 30–60 d: 5, 60–90 d: 8, > 90 d: 15. Caches are either in daily use or
   untouched for months.
2. **N barely changes the bytes.** Moving N from 1 to 3 relabels 26 small folders, about
   26 MB of Apple daemon caches written every day or two. **M decides exactly one large folder:**
   `~/.cache/codex-runtimes` (1.5 GB, 58 days) is cold at M = 30 and warm at M = 60 or 90.
3. **Almost every byte Pare scans today is hot.** The five cold folders of 100 MB or more
   (2.6 GB in total) are under `~/.cache/<tool>` and `~/.yarn/berry`, which no rule reports today.
   The thresholds therefore matter more for a future generic `~/.cache` rule than for current findings.
4. **The sampler leans towards "older".** A newer file deeper than depth 2 is missed:
   `~/Library/Caches/com.apple.Spotlight` sampled at 21.6 days, while a full walk found 18.9.
   The error is a few days, which is noise at M = 30. Only `go-build` and `golangci-lint` hit
   the 2,000-entry cap, and both were already hot from their root mtime. Every sample took
   8 ms or less.

### Options

| Option | Consequence on this machine |
|---|---|
| A1 (1, 14) | Same cold bytes as A2. 33 small folders become warm instead of hot. A cache used every two weeks would be preselected in slice 2. |
| **A2 (3, 30)**, #67's default | Warm band is 14 folders / 93 MB. Cold is 2.6 GB, including `codex-runtimes` at 58 days. |
| A3 (7, 60) | `codex-runtimes` (1.5 GB) becomes warm, so it is not preselected in slice 2. Cold is 1.1 GB. |
| A4 (7, 90) | Only `github-copilot` and Yarn berry stay cold (430 MB). Long-unused tool caches stay unchecked. |

**Recommendation: A2 (3, 30).**
- Because the data is bimodal, any M from 30 to 60 gives the same answer except for one folder.
- 30 days matches the monthly cadence of the existing age gates.
- The row text already shows the exact age ("Not used in 58 days") before anything is cleaned.
- Cold only ever preselects items that are already `.safe`, which means reconstructible.
- Pick A3 instead if slice 2 should preselect less on first run.

### Should "hot" be overridable in one click?

| Option | Consequence |
|---|---|
| H1 Hot is hard-skipped and cannot be selected | On this machine that removes nearly every scanned cache byte from Smart Scan (pnpm, Playwright, npm, bun, node-gyp…), at critical pressure with 8 GB free. It needs a new cleanup-time re-check in `ScanPolicy`/`CleanupEngine`. |
| **H2 Hot is shown unchecked with "In active use", and its checkbox stays enabled** | One click per row includes it. The clean confirmation sheet lists it as "in active use — will be re-downloaded". |
| H3 Hot is hidden behind a "Show caches in use" toggle | Two clicks, and the space is invisible until the user goes looking for it. |

**Recommendation: H2.**
- Hot is a "probably not worth it" signal, not a safety signal; the safety gates are `RiskLevel` and `ScanPolicy`.
- Do not add a bulk "include all hot" button. It would bring back bulk-cleaning of working caches.

### What changes in code

- **A2:** nothing new. #67 already ships 3 and 30 (`CacheActivityClassifier.defaultHotDays`/`defaultColdDays` in `Sources/PareCore/CacheActivity/CacheActivity.swift`). Un-draft it and merge.
  - Optionally move the two constants into `ScanPolicy`, next to the per-category minimum ages.
- **A1, A3 or A4:** change those two constants and the boundary cases in `Tests/PareCoreTests/CacheActivityTests.swift`.
- **H2 (slice-2 PR):**
  - `ScanDashboardViewModel`: preselection skips `.hot` and selects `.cold` only when the finding is `.safe`.
  - `SelectableCandidateRow`: the toggle stays enabled.
  - `CleanConfirmationSheet`: one line for the hot items included.
  - No engine change.
- **H1:** a new fail-closed check in `ScanPolicy`, called from `CleanupEngine`, with its own tests.

---

## B. Phase 12.2: dependency folders of inactive projects

**Context.** The spec is `docs/features/project-dependency-reclaim.md` (Phase 12 in the roadmap).
It brings back `node_modules`, `venv`, `.venv` and `.bundle` directly under a confirmed project
root, as `.review` only. A folder is reported when the project has restore evidence, has been
inactive longer than the disk-pressure tier allows (14, 7 or 3 days), and is not in use.
Phase 12.1 (SwiftPM `.build`) is already covered by #44.

### Evidence

Every dependency folder under `~/Projects` to depth 4 was listed, without descending into
dependency, `.git` or build folders. Project activity is the newest of the enclosing repo's
`.git/index`, `.git/logs/HEAD` and `.git/FETCH_HEAD`, the lockfile and manifest, and the
project's top-level entries other than dependency and artifact folders.

| Dependency folder | Size | Project inactive (days) | Folder's own mtime (days) | Lockfile |
|---|---:|---:|---:|---|
| `yudgnahk/mv-studio/analysis/.venv` | 1.3 GB | 0.1 | 0.1 | `uv.lock` |
| `yudgnahk/chess-puzzle/node_modules` | 241 MB | 0.0 | 2.3 | `pnpm-lock.yaml` |
| `yudgnahk/chess-puzzle-wt/tap-perf/node_modules` | 240 MB | 0.0 | 0.0 | `pnpm-lock.yaml` |
| `yudgnahk/chess-puzzle-wt/webkit/node_modules` | 240 MB | 0.0 | 0.0 | `pnpm-lock.yaml` |
| `yudgnahk/games/zoominoes/node_modules` | 224 MB | 0.0 | 5.2 | `package-lock.json` |
| **`yudgnahk/pixel-flow/node_modules`** | **156 MB** | **5.4** | 7.3 | `package-lock.json` |
| `yudgnahk/resuforge/node_modules` | 153 MB | 0.0 | 0.1 | `pnpm-lock.yaml` |
| `yudgnahk/mv-studio/app/node_modules` | 125 MB | 0.1 | 7.7 | `bun.lock` |
| `yudgnahk/mayhoa/node_modules` | 121 MB | 0.0 | 0.1 | `pnpm-lock.yaml` |
| **`mcp/serena/.venv`** | **120 MB** | **50.7** | 460.9 | `uv.lock` |
| `yudgnahk/pantheora/node_modules` | 100 MB | 0.0 | 0.0 | `pnpm-lock.yaml` |
| `yudgnahk/exam-prep-kit/.venv` | 85 MB | 0.0 | 36.4 | none, and no manifest |
| `yudgnahk/fable-moonshot-wt/song/node_modules` | 61 MB | 0.0 | 0.1 | `bun.lock` |
| `yudgnahk/fable-moonshot-wt/stereo/node_modules` | 61 MB | 0.0 | 0.0 | `bun.lock` |
| `yudgnahk/fable-moonshot/node_modules` | 61 MB | 0.0 | 0.1 | `bun.lock` |
| `yudgnahk/mv-studio/studio/node_modules` | 37 MB | 0.1 | 7.2 | `bun.lock` |

What that means:

- **16 folders, 3.3 GB in total. 14 of them belong to projects touched in the last 3 hours.**
- What would be offered under each tier:
  - Comfortable (14 days): 120 MB (`serena`).
  - Low (7 days): 120 MB.
  - Critical (3 days, today's tier): 276 MB (`serena` and `pixel-flow`).
- The 11 GB from the 2026-09-30 field run was already deleted by hand, so this machine now under-shows the feature.
- **The folder's own mtime is the wrong clock, as the spec says.** `serena/.venv` is 461 days old, but the project was touched 51 days ago. `exam-prep-kit/.venv` is 36 days old in a project that is active today.
- Neither inactive project had a running process today (`ps -axo comm=,args=`).
- **Going deeper (depth 6–8) finds 30–34 folders, and the extra ones are traps the rule must handle:**
  - pnpm workspace members such as `apps/web/node_modules` and `packages/engine/node_modules` are 0–3 MB symlink farms. Fold them into the workspace root instead of reporting each one.
  - `actions-runner/externals/node20/lib/node_modules` is a bundled runtime with no lockfile. Requiring restore evidence rejects it.
  - Fixtures such as `dev-env-optimizer/testdata/…/node_modules` and `.venv` are 0 MB. A minimum size rejects them.
  - In git worktrees such as `mv-studio-wt/revapp/app/node_modules` (118 MB), `.git` is a file. Activity has to follow `gitdir:` to `.git/worktrees/<name>/index`. Otherwise it falls back to the `.git` file's creation date and looks older than it is.
  - Nested projects with no `.git` of their own, such as `mv-studio/tools/py-inspect/.venv` (38 MB) and `pantheora/assets/runtime/ground-trial/.venv` (62 MB), must use the enclosing repo's git markers. With the enclosing repo's markers, an active monorepo protects all its sub-projects.
- **On a 245 GB disk the percentage limits bind, not the GB limits:**
  - comfortable needs ≥ 36.8 GB free (15 %);
  - critical starts below 12.3 GB (5 %);
  - today's 8.0 GB is critical.

### Decide-points

**B1 Tier thresholds**

| Option | Consequence here |
|---|---|
| **Keep 14 / 7 / 3 with the 72-hour floor** | Offers 120 MB / 120 MB / 276 MB. The tiers only change the outcome for projects idle 3–14 days, which here is only `pixel-flow`. |
| Flat 14 days, no pressure scaling | Simpler, with no free-space dependency. Offers 120 MB today, at critical pressure. |
| 30 / 14 / 7 | Offers 120 MB at every tier. `pixel-flow` is never offered. |

Recommendation: **keep 14 / 7 / 3.**
- Every finding is `.review` and never preselected, so a lower threshold costs at most one unchecked row.
- The spec's open question was whether the tiers suit a 228 GiB disk. They do: the percentage limits apply and are sensible.

**B2 Require a lockfile?**

| Option | Consequence here |
|---|---|
| Lockfile **or** manifest (spec); manifest-only shows a drift warning | Same result here, because no folder is manifest-only. Elsewhere, `requirements.txt`/`package.json`-only projects come back with versions that may drift. |
| **Lockfile only, first PR** | Same 276 MB here, and restore is exact. Manifest-only projects are never offered. |
| Lockfile only for Node and Ruby; lockfile or manifest for Python | Covers the common `requirements.txt` venv without a lockfile, at the cost of a split rule. |

Recommendation: **lockfile only in the first PR.**
- 15 of 16 real folders have a lockfile. Manifest-only adds 0 bytes here and is the one path where a restore can differ.
- Add manifest-only, with the drift warning, in a later slice if users ask for it.

**B3 Broken venvs (dangling `bin/python`)**

Measured: there are none today. The `tts/.venv` case was fixed by hand on 2026-09-30, and `exam-prep-kit/.venv/bin/python` still resolves.

| Option | Consequence |
|---|---|
| Spec: report regardless of activity, and offer "Save package list" when there is no manifest | Adds Pare's first write into a user's project (`venv-packages-<date>.txt`). |
| **Report broken venvs regardless of activity, only when a lockfile or manifest exists; defer the export** | No new write path. A broken venv with no manifest stays unreported, which is the fail-closed choice. |
| Skip broken venvs | Loses the clearest win of the 2026-09-30 field run. |

Recommendation: **the middle option.** The package-list export becomes its own slice with its own tests.

**B4 Does it depend on #50 (in-use gate)?**

#50 already checks every cleanup item with `OpenFileSnapshot.holder(atOrUnder:)`. That uses lsof `-Fpcn`, which lists each process's cwd as well as its open files. `holder(atOrUnder:)` can take the **project root** instead of the item, which is exactly what the spec asks for.

| Option | Consequence |
|---|---|
| **Land after #50, and check the project root at cleanup time** | No new lsof code. #50 is already in `integration/2026-10-07`. |
| Ship without an in-use check, relying on ≥ 3 days of inactivity | A dev server or MCP server started from a stale project could lose its `.venv` mid-run. |
| Separate lsof call in the rule | Duplicates #50 and adds to section C's lsof consolidation. |

Recommendation: **land after #50.** Also land after the free-space consolidation (C step 3), because the pressure tier needs one free-space reader.

### Implementation order (PR slices)

1. **12.2a, policy only.** In `ScanPolicy+ProjectDependencies.swift`:
   - the tier constants and the 72-hour floor;
   - `projectActivityDate(root:)`, covering the enclosing repo, worktree `gitdir:`, lockfile and top-level entries;
   - the lockfile → restore-command table;
   - a fail-closed `isReclaimableProjectDependency`;
   - table-driven tests and the snapshot digest. No rule yet.
2. **12.2b, the rule and the engine route.** Needs #44, #45, #50 and C step 3.
   - `ProjectDependencyRule` (`.review`, never preselected) runs over the confirmed roots from #45. It folds workspace members into the root and has a minimum size, which is a `ScanPolicy` constant.
   - The reason text reads "Inactive 9 days · free space is critical (3-day threshold) · restore with `pnpm install`".
   - `CleanupEngine` routes dependency-named items only through the new gate, using the same exclusive pattern as #56/#57, plus #50's holder check on the project root.
3. **12.2c:** broken-venv detection (needs a lockfile or manifest).
4. **12.2d:**
   - "Save package list" export;
   - manifest-only projects, with the drift warning;
   - an "empty the Trash to get the space back" note at critical pressure, which uses #54's verified reclaim.

---

## C. Seam consolidation

**Context.** Today's PRs each added their own injectable seam for the same system facts. This
section reads `integration/2026-10-07`, which has #38–#64 merged. #66 and #67 are separate:
each branches from master directly and is not in integration.

### Inventory

**Free space**: five readers.

| Seam | PR | File | Shape |
|---|---|---|---|
| `FreeSpaceProviding` / `StatfsFreeSpace` | #48 | `Maintenance/SQLiteVacuumEnvironment.swift` | `availableBytes(atPath:) -> Int64?` (statfs `f_bavail`) |
| `VolumeFreeSpaceProviding` / `SystemVolumeFreeSpace` | #54 | `Cleanup/VolumeFreeSpace.swift` | `freeSpace(forVolumeContaining:) -> VolumeFreeSpace?` (important-usage + available) |
| private `volumeCapacity` closure | #60 | `DiskHealth/DiskHeaderProvider.swift` | re-implements #54 line for line |
| `freeDiskBytes` closure | #53 | `Rules/MemoryPressureRule.swift` | important-usage only |
| inline `resourceValues` | master | `PareApp/ViewModels/VolumeUsageModel.swift` | total + important-usage |

The "swap plus low disk" warning is also written twice, with different thresholds:
- `DiskHeaderSnapshot.warnsOfSwapPressure`: swap > 4 GB and free < 10 GB;
- `MemoryPressureRule`: swap > 1 GiB and free < 10 GiB.

The `sysctl vm.swapusage` parser is duplicated too: `SwapUsageRule` (#51) and `SwapUsageParser` (#60).

**Running apps and processes**: five checks.

| Seam | PR | File | Shape |
|---|---|---|---|
| `RunningAppChecking` | #48 | `Maintenance/SQLiteVacuumEnvironment.swift` | `isRunning(bundleIdentifier:) -> Bool` |
| `RunningAppsProviding` | #50 | `Cleanup/InUseGate.swift` | `runningApps() -> [RunningApp]` |
| `RunningExecutablesProviding` | #57 | `Scanning/RunningExecutables.swift` | `runningExecutablePaths() async -> [String]?` (`ps -axo comm=`, 5 s) |
| `CodexActivity` closure | #59 | `Rules/CodexStagingRule.swift` | `() async -> Bool` (`ps -axco comm=`, 3 s, plus `NSWorkspace`) |
| `RunningAppsProvider` typealias | master | `Homebrew/CaskLeaveHomebrew.swift` | `() -> [String]` (bundle paths) |

There are four live `NSWorkspace.shared.runningApplications` implementations and two `ps` invocations with different flags.

**lsof**: two parsers over the same `ToolCommandRunner` (10 s timeout).

| | #50 `OpenFileSnapshot` | #51 `DeletedOpenFilesRule` |
|---|---|---|
| Arguments | `-n -P -w -Fpcn` | `+L1 -n -P -w -FpcDisn` |
| Result | path → holder index, including ancestors | private `[OpenDeletedFile]` |
| Seam | `OpenFileSnapshotProviding` | `Listing` closure |

Both exited 0 here: 0.3 s and 0.1 s.

**Per-finding metadata**: four storage styles.

| Data | PR | Where it lives |
|---|---|---|
| `isSizeComplete` | #58 | field on `ScanFinding` |
| `annotations: [FindingAnnotation]` | #46 + #51 | field on `ScanFinding`. Integration's merge already resolved it to the union `.workingSet(selfTrimDays:)` + `.explainOnly(action:)`. No app view reads it; it only feeds `reason` text. |
| Regrowth | #63 | no field: `RegrowthDetector` rebuilds the finding as `.review` and appends to `reason` |
| Cache activity | #67 | `[String: CacheActivityLabel]` on the view model, keyed by **raw** path |
| Growth | #66 | `GrowthSnapshot` per report, with its own canonical key |

The canonical-key expression `ScanPolicy.canonicalPathURL(…).path.lowercased()` is copied four
times: `OpenFileSnapshot`, `RegrowthDetector`, `ScanPolicy+VersionSiblings` and #66.

**Real bug found while reading.** `GoCachesRule`'s private `annotated(with:)`
(`Rules/GoCachesRule.swift:69`) rebuilds `ScanFinding` without `isSizeComplete`, so the flag
silently resets to `true`. Impact is small: the finding is `.advanced`, so only the "at least" size text is wrong.

**Test hermeticity.** About 50 `CleanupEngine(` call sites in tests inject none of `openFiles:`,
`runningApps:`, `freeSpace:` or `runningExecutables:`. Non-dry-run tests therefore call the real
lsof and `NSWorkspace`.

### Target shape: one seam per concern

All of these go under a new `Sources/PareCore/System/` folder:

| File | Type | Replaces |
|---|---|---|
| `VolumeCapacity.swift` | `struct VolumeCapacity { totalBytes, importantUsageBytes, availableBytes }`, `protocol VolumeCapacityProviding { func capacity(forVolumeContaining: URL) -> VolumeCapacity? }`, live `SystemVolumeCapacity` | #48, #54 (rename), #60 closure, #53 closure, `VolumeUsageModel` inline read. #48's VACUUM check reads `availableBytes` (space writable now); everything else reads `importantUsageBytes`. One swap-pressure threshold pair lives here too. |
| `SwapUsage.swift` | one parser and reader | #51 + #60 parsers |
| `RunningProcesses.swift` | `struct RunningApp { bundleIdentifier, name, bundlePath }`, `protocol RunningProcessesProviding { func runningApps() -> [RunningApp]; func runningExecutablePaths() async -> [String]? }`, `isRunning(bundleIdentifier:)` as an extension, live `SystemRunningProcesses` (one `NSWorkspace` read, one `ps -axo comm=`) | #48, #50, #57, #59 (match on basenames of the full paths, so no second `ps`), `CaskLeaveHomebrew`'s typealias. `nil` still means unknown, which fails closed. |
| `Lsof.swift` | `LsofFieldParser` → `[LsofProcess { pid, command, files }]` | Both parsers. #50 and #51 keep their own arguments. |
| `Models/FindingKey.swift` | `FindingKey(path:)` (canonical, lowercased) and `ScanFinding.replacing(riskLevel:reason:annotations:)`, a copy helper that keeps every field | Four key copies and every hand-written rebuild, which also fixes the Go bug |

Rule for per-finding metadata:
- Facts known at scan time stay on `ScanFinding`: `isSizeComplete`, plus `annotations`, which gains `.regrew(days:)` so #63 stops encoding it only in `reason`.
- Display facts computed after the scan go in one `[FindingKey: FindingInsight]` dictionary on the view model. These are #67's activity, #66's per-path growth and later in-use.

### Before or after merging the stack?

| Option | Consequence |
|---|---|
| C1 Before: rewrite the seams inside the open PRs | Every rebase re-resolves the 27-PR merge that `integration/2026-10-07` already rehearsed. Stacked PRs (#46 → #49 → #57) churn three times. |
| **C2 After: merge the stack as rehearsed, then six small refactor PRs** | No behaviour changes, each PR is reviewable on its own, and the conflict work is already done. Duplicates live on master for a few days. |
| C3 Hybrid: only #66 and #67, which are outside integration, adopt `FindingKey` before merging | Needs refactor step 1 to land first. |

**Recommendation: C2, then rebase #66 and #67 onto step 1 (C3 for those two only).** None of the duplicated seams are user-visible, and all of them fail closed, so waiting costs nothing.

### Migration order (after the stack merges)

1. **`FindingKey` + `ScanFinding.replacing` + one swap parser.** No API change. Fixes the `GoCachesRule` bug.
2. **`CleanupEngineFixture`**, a test factory that injects fakes for every seam. After this, steps 3–5 touch one test file instead of about 50 call sites, and tests stop calling the real lsof and `NSWorkspace`.
3. **`VolumeCapacity`.** Repoint #48 (two consumers, one fake), then #54, #60, #53 and `VolumeUsageModel`. Delete `FreeSpaceProviding`. Phase 12.2b needs this for its pressure tiers.
4. **`RunningProcesses`.** Fold #48 into #50's type, add executables (#57), then `CodexActivity` (#59), then `CaskLeaveHomebrew`.
5. **`LsofFieldParser`.** Internal only.
6. **`FindingInsight`.** Rebase #67 (and its slice 2) and #66 onto it. Add `.regrew(days:)` for #63.

### Merge note: step 2 started early, on #50

`aa2e74e` on #50 (`feat/in-use-cleanup-gate`) adds `Tests/PareCoreTests/Support/CleanupEngineFixture.make(...)`.
It stubs the in-use gate: nothing is open and nothing is running. On that branch, 28 `CleanupEngine(` test call sites
and `HermeticCleanupFixture.makeEngine()` now use it. No test there runs the real `lsof` any more.
`InUseGateFailureTests` still runs the real provider type on purpose, but against a temp shell script.

`integration/2026-10-07` was merged from #50 at `3d87c17`, before this commit. When #50 is re-merged:

- **Expected text conflicts** are in test files that other PRs in the stack also changed:
  - `CleanupSafetyRegressionTests` (4 PRs)
  - `ScanIntegrationTests` (2)
  - `InUseGateTests` (2)
  - `ExclusionListTests` (1)

  To resolve, keep the other PR's arguments and rename `CleanupEngine(` → `CleanupEngineFixture.make(`. The argument labels are identical.
- **13 call sites from other PRs still build `CleanupEngine(` directly:**
  - `CodexStagingRuleTests`
  - `DiagnosticsFindingsTests`
  - `GoWorkingSetTests` ×2
  - `LaunchdRestartLoopRuleTests`
  - `OrphanedLaunchAgentsSafetyTests`
  - `PnpmOldStoreRuleTests`
  - `ProtectedUserDataTests`
  - `StaleUpgradeBackupsTests`
  - `TinyFileQueueRuleTests`
  - `VerifiedReclaimTests`
  - `VersionSiblingTests`
  - one new site in `CleanupSafetyRegressionTests`

  Integration has 52 `CleanupEngine(` occurrences in `Tests/`.
- **Finishing step 2 after the stack merges:**
  - Give `make()` the later init parameters, with stub defaults:
    - `gitInspector` (#41, real `git`)
    - `goCacheLocations` (#46)
    - `freeSpace` (#54)
    - `runningExecutables` (#57, real `ps`)
    - `isCodexRunning` (#59; `nil` falls back to `CodexActivity.system`, which runs `ps` and reads `NSWorkspace`)
    - `pnpmActiveStore` (#61; `nil` locates the real pnpm store)
  - Then switch those 13 sites.
  - The five `CleanupEngine()` sites in `DiskAnalyzerViewModelTests` never reach `clean`, so they spawn nothing. They still default to the shared undo store, so switch them in the same PR.

---

## D. Open questions left in PR bodies

### D1. #49: `com.google.*` / `org.mozilla.*` cache folders are protected only at scan time. Intended?

**Facts.**
- `ScanPolicy.isUserCacheFolderProtected(name:)` is called only from `UserCachesRule`.
- At cleanup time, only `GIPPseudonymousID` and `CCTClearcutLogger` are blocked, through `neverCleanUserDataComponentSequences` → `isNeverCleanPath`. Those are the two folders Google apps rewrite at about 50 MB/s.
- `ProductivityCachesRule` *deliberately* reports `Library/Caches/com.google.drivefs.finderext` (also in the markers list). The prefix check needs a dot (`com.google.`), so `com.googlecode.iterm2` here does not match it.

| Option | Consequence |
|---|---|
| **Keep scan-only (as shipped)** | The prefix is a noise filter for the generic rule. The real hazards (identity caches) are blocked at cleanup for every rule. |
| Promote the prefixes to cleanup-time never-clean | Silently breaks the Drive Finder-extension cleanup, unless that rule gets an exception carved out of a never-clean list. |

**Recommendation: keep it, it is intended.** Add a one-line comment on `userCacheProtectedFolderPrefixes` saying it is scan-time only because of `com.google.drivefs.finderext`. No other code change.

### D2. #64: `brew cleanup` deletes directly instead of using the Trash. Acceptable?

**Facts.**
- Before running, #64 re-runs `brew cleanup -n`, refuses when the result is empty, and asks for confirmation in a dialog that says "deletes directly". It never passes `--prune=all`.
- The Maintenance tab already runs native commands that delete directly (`docker system prune -f`, `docker builder prune`).
- Here, `brew cleanup -n` had nothing to remove, and `~/Library/Caches/Homebrew` is 37 MB.

| Option | Consequence |
|---|---|
| **Accept** | Homebrew acts on its own store, and everything it removes is an old keg or a download it can fetch again. There is no undo record. |
| Route through the Trash: parse the `-n` list and Trash each path via `CleanupEngine` | Moving Cellar kegs behind Homebrew's back leaves stale links and metadata. It also needs Homebrew paths allowed in `ScanPolicy`. |
| Preview only, with no execution | Safe, but the user has to run it in Terminal. |

**Recommendation: accept.**
- State the exception once in `CLAUDE.md`: "`CleanupEngine` always uses the Trash; native tool commands in Maintenance/Homebrew delete directly behind a preview and a confirmation".
- Make sure the Homebrew result card never offers Undo.

### D3. #57: the engine routes every version-shaped item through the new gate. Acceptable?

**Facts.**
- `CleanupEngine`'s routing on `integration/2026-10-07` is exclusive and ordered: never-clean → search index → advanced/diagnostics → upgrade-backup names (#56) → **version-sibling members** → pnpm (#61) → Codex staging (#59) → the generic allow-lists.
- `isVersionSiblingMember` needs three things: a semver token in the name, at least 3 sibling folders with the same prefix and suffix, and a location outside the excluded trees.
- When another rule's finding matches that shape, it is judged *only* by the stricter gate: keep the newest 2, not executed from, `~/.<dir>` or Application Support. That gate can only reject, never widen, so the worst case is an "unsafe path" skip.
- One match on this machine: `~/.cache/node/corepack/v1/pnpm/{10.9.0,12.3.4,12.9.1}`. Neither `.cache` nor `corepack` is in `versionSiblingExcludedDirectoryNames`, and depth 5 is within range. `VersionSiblingsRule` would offer `10.9.0` as `.review`. Corepack re-downloads it on demand. No other rule reports that path, so there is no conflict.
- Upgrade-backup names are checked first, so #56 is unaffected.

| Option | Consequence |
|---|---|
| **Accept the shape-based routing** | The same fail-closed pattern as #56 and pnpm. Detection does not trust the finding's origin label. |
| Route by the finding's rule ID instead | Simpler to reason about, but the engine would trust a label that a mis-reporting rule could get wrong. |
| Accept, and give these skips a clearer reason | Same safety. A skipped item says "kept: fewer than 2 newer versions" instead of "unsafe path". |

**Recommendation: accept**, and take the clearer skip reason as a small follow-up. Also add the
`isNeverCleanPath` check flagged in #57's own notes now that #46 and #49 are in the stack. The
engine already runs never-clean first, so this is only for the policy function's own callers.
