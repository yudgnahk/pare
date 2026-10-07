# Merge rehearsal — 2026-10-07

Branch `integration/2026-10-07` (from `origin/master` 86eb5e0), every open PR merged with `git merge --no-ff`, no rebases. Rehearsal only — no PR. Final state builds (`make build`, CLT SDK); XCTest is not available locally, so the test suites were checked with `swiftc -parse` only and still need CI.

## Order and result

All 30 branches merged, in this order:
1. #39 `fix/scan-dedupe-findings`, #40 `feat/scan-incomplete-warning`, #38 `fix/discovery-exclusions`, #45 `feat/discovery-refresh-signals`
2. #41 `fix/git-gate-project-artifacts`, #44 `feat/hidden-project-artifacts`
3. #46 `fix/go-caches-working-set`, #49 `fix/protect-opencode-and-google-identity`
4. #47 `fix/remove-lsregister-demote-launch-agents`, #42 `fix/carry-over-0918`, #43 `docs/neutral-reference-tool-wording`, #48 `fix/wal-safe-vacuum`
5. #50 `feat/in-use-cleanup-gate`, #51 `feat/diagnostics-open-deleted-and-swap`, #53 `feat/memory-pressure-diagnosis`, #55 `feat/launchd-restart-loops`, #62 `feat/tiny-file-queues`, #52 `feat/crash-loops-runaway-logs`
6. #54 `feat/verified-reclaim`, #56 `feat/stale-upgrade-backups`, #57 `feat/version-sibling-detector`, #58 `feat/directory-size-deadline`, #59 `feat/codex-staging-leftovers`, #60 `feat/disk-header-breakdown`, #61 `feat/pnpm-old-store-versions`, #63 `feat/regrowth-learning`, `feat/brew-cleanup-preview`, then #57's review fix `100bf4f`

Clean merges: #39, #40, #47, #42, #43, #53, #60, `feat/brew-cleanup-preview`, #57's `100bf4f`.

## Conflicts and resolutions (per merge)

- #38: ProjectRootDiscovery.swift — took abb9916 resolution (seam + timeout flag from #40, needsSave pruning from #38; discoverIfNeeded saves pending prune then returns Bool)
- #45: ProjectRootDiscovery.swift — took #45's side (abb9916 resolution + C5 TTL/markStale/in-flight + C3 signal mapping; superset)
- #41: ProjectArtifactsRule.swift — hand-merged: init takes gitInspector + timeBudget + now; ungated artifacts sized inline per root under #40's budget (keeps #40's call-order test), gated build/dist/target deferred to ONE git query per scan (keeps #41's "inspector called once" test), then sized under the same budget; roots with unsized gated candidates count as not fully scanned. CleanupSafetyRegressionTests.swift — union of #38's pruned-Go-root test and #41's git-evidence tests.
- #44: CleanupSafetyRegressionTests.swift — union (#38 pruned-root test + #44 sibling-manifest tests). ScanPolicySnapshotTests.swift — digests recomputed from merged source: projectLocalArtifactDirectoryNames 22c7cc588d03e967:24 (#44), projectArtifactNamesRequiringGitIgnoreEvidence e248168fd9663d3c:4 (#41 final, incl. coverage), projectArtifactRequiredSiblingMarkers 1148dc4920103d3e:11. ProjectArtifactsRule auto-merged: sibling-marker + child-mtime age gates sit before the git deferral.
- #46: CleanupEngine.swift — union: gitInspector (#41) and goCacheLocations (#46) both stored, both init params (gitInspector, goCacheLocations), git statuses and Go cache roots both resolved before the loop; NeverClean gate stays ahead of every allow-list. ScanPolicySnapshotTests.swift — kept merged digests, added neverCleanComponentSequences 5b8498f0d86a979c:2, developerPackageCacheMarkers recomputed 613683649b3a72b1:20.
- #49: ScanPolicySnapshotTests.swift — merged digest table (union of keys); developerPackageCacheMarkers recomputed 0a9650438f6953f4:21, reconstructibleCachePathMarkers 75a6f80e10997f85:16 (auto-merged).
- #48: MaintenanceRunner.swift — took #48's SQLiteVacuumRunner call (supersedes #42's catch-all vacuum loop, which #48's runner also does per database). #42/#43 merged cleanly (see UV_INVESTIGATION check below).
- MIDWAY make build after #48: Build complete.
- #50: CleanupEngine.swift — union: gitInspector + goCacheLocations + openFiles + runningApps all stored/injected; in-use batch check created alongside git statuses and Go roots (in-use check runs at the trash step, after every policy gate).
- #51: FindingAnnotation.swift — union of cases (.workingSet from #46, .explainOnly from #51). GoCachesRule's exhaustive switch gained an .explainOnly arm (never produced there) so it compiles.
- #55: RuleCatalog.swift — union (MemoryPressureRule + LaunchdRestartLoopRule). CLAUDE.md — merged both diagnostics sentences into one list. Rule counts recomputed at the end.
- #62: RuleCatalog.swift — union (+TinyFileQueueRule). CLAUDE.md — TinyFileQueueRule clause appended to the merged diagnostics list.
- #52: RuleCatalog.swift — union (+CrashLoopRule, RunawayLogsRule). CLAUDE.md / ScanRunnerTests counts — kept HEAD placeholder, recomputed at the end from RuleCatalog.
- #54: CleanupEngine.swift — union: freeSpace (VolumeFreeSpaceProviding) added after the gitInspector/goCacheLocations/openFiles/runningApps params; helpers kept. Two free-space seams now coexist: #48 FreeSpaceProviding (statfs, one number) and #54 VolumeFreeSpaceProviding (both URL capacities) — follow-up: consider unifying.
- #56 (incl. W2 review fix a14cd16): CleanupEngine.swift — upgrade-backup gate is a MANDATORY refusal before #41's policyRejection: backup-named paths pass only via isReclaimableUpgradeBackup, everything else via policyRejection; NeverClean check still earlier. RuleCatalog union; CLAUDE.md paragraphs unioned; counts recomputed at end.
- #57 (at 88db1c9 — rehearsal predates W2's review fixes): CleanupEngine.swift — runningExecutables seam added to the union; version-sibling branch is a MANDATORY gate in the chain (upgrade backup → version sibling → policyRejection), never a plain || allow term; NeverClean still earlier. Markers: versionSiblingExcludedDirectoryNames appended next to projectDiscoverySignalNames. Snapshot digest kept (f985d82c39c8652c:45, verified). Third running-process seam now exists (#48 RunningAppChecking, #50 RunningAppsProviding, #57 RunningExecutablesProviding) — follow-up: consider consolidating.
- #58: ScanModels.swift — ScanFinding keeps both annotations (#46) and isSizeComplete (#58), init params in that order. ProjectArtifactsRule.swift — kept the #40/#41/#44 walk; makeFinding now sizes via directorySizeResult and reports deadline-cut sizes with isSizeComplete=false (#58 behaviour).
- #59: CleanupEngine.swift — isCodexRunning seam added to the union; codex route merged as an extra ALLOW arm (codexIdle AND isReclaimableCodexStagingEntry, both kept) placed after the mandatory upgrade-backup / version-sibling gates and before policyRejection. RuleCatalog union; CLAUDE.md paragraphs unioned.
- #61 (incl. W2 review fix 7e58e66): CleanupEngine.swift — pnpmActiveStore seam in the union; pnpm guard is a MANDATORY refusal arm (passes only isReclaimableOldPnpmStore or wrong-platform) placed after the version-sibling arm and before the Codex allow arm and policyRejection. Final chain: NeverClean (earlier) → upgrade backup → version sibling → pnpm → [codexIdle && codex staging = allow] → policyRejection. #60 merged clean.
- #63: ScanRunnerTests.swift — union (dedupe/incomplete tests + regrowth test). ScanRunner.swift — regrowth post-pass now sits after FindingDeduplicator (comment updated). FIX in rehearsal: RegrowthDetector.demoted() now copies annotations (#46) and isSizeComplete (#58) instead of dropping them — must be carried into #63 before/at merge.
- #57 review fix 100bf4f (version siblings only inside the rule's own roots; refuses protected locations and iCloud Drive) merged after landing — clean.

## CleanupEngine gate order (W2 safety review rules, applied)

1. User exclusions → Docker never-delete → **NeverClean** (#46/#49, Go caches + OpenCode/Google identity data) → search-index → `.advanced` block.
2. Mandatory refusal chain — each class passes **only** through its own predicate, never through the generic allow-lists:
   - upgrade-backup names → `isReclaimableUpgradeBackup` (#56)
   - version-sibling members → `isReclaimableVersionSibling` with one running-executables snapshot (#57)
   - pnpm store / pnpm home paths → `isReclaimableOldPnpmStore` or wrong-platform (#61)
3. Extra allow route: `codexIdle && isReclaimableCodexStagingEntry` (#59; both conditions kept).
4. Otherwise `policyRejection` (#41): project artifacts must have git-ignore evidence; generic allow-lists for the rest.
5. Then existence, symlink, age gates, and the in-use check (#50) at the trash step.

## Collisions resolved globally

- **Rule counts:** recomputed from `RuleCatalog`: baseline **21**, unified **47** unique ids (verified unique). Updated in `CLAUDE.md` and `ScanRunnerTests`.
- **`FindingAnnotation`:** union of `.workingSet(selfTrimDays:)` (#46) and `.explainOnly(action:)` (#51); `GoCachesRule`'s exhaustive switch got an `.explainOnly` arm.
- **`ScanFinding.init`:** has both `annotations` (#46) and `isSizeComplete` (#58).
- **Finding rebuilds (fixed in the rehearsal):** `RegrowthDetector.demoted()` (#63) and `FindingDeduplicator.raising` (#39) rebuilt `ScanFinding` without `annotations`/`isSizeComplete`; both now copy them (commit "fix: carry annotations and size completeness through finding rebuilds; recount rules"). The real PRs need the same one-line change when they land after #46/#58.
- **Snapshot digests:** recomputed from the merged `ScanPolicy*.swift` source with the FNV-1a script (verified against known digests first).
- **`UV_INVESTIGATION.md` line 6:** #42's correction note and #43's neutral wording merged cleanly; no tool name remains (`git grep -iw` clean).

## Follow-ups

- Two free-space seams coexist: #48 `FreeSpaceProviding` (statfs, one number) and #54 `VolumeFreeSpaceProviding` (both URL capacities).
- Three running-process seams: #48 `RunningAppChecking`, #50 `RunningAppsProviding`, #57 `RunningExecutablesProviding`.
- #57's version-sibling cleanup gate should also consult `isNeverCleanPath` (now available on the merged base).
- #52 / #63: switch to `.explainOnly` / `.workingSet` annotations now that `FindingAnnotation` has both.
- W2 review fixes: #56 (`a14cd16`), #61 (`7e58e66`) and #57 (`100bf4f`) are all included; nothing in this rehearsal predates them.
- CI never ran on this branch (Actions minutes exhausted); run the full suite before merging for real.
