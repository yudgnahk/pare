# Roadmap

Status legend: `[ ]` todo · `[~]` in progress · `[x]` done

## Done

- **Phase 0 — Rename to Pare.** Bundle ID `com.yudgnahk.pare`.
- **Phase 1 — Quick wins.** AI tool caches, Homebrew download cache, installer files.
- **Phase 2 — Stale app versions.** Duplicate `.app` bundles grouped by bundle ID; older copies `.review`.
- **Phase 3 — App Manager.** Inventory, uninstaller with leftovers, Sparkle/MAS update checks. Doc: `docs/features/app-manager.md`.
- **Phase 4 — Homebrew Manager.** Formulae, casks, outdated, migrate, leave Homebrew. Doc: `docs/features/homebrew-manager.md`.
- **Phase 5 — Medium gaps.** Browser artifacts, project artifacts, Disk Analyzer, History export. The System Optimizer (admin tasks) is deferred: too risky without testing on several macOS versions.
- **Phase 6 — Developer breadth.** Package-manager caches, Spotlight project discovery. Doc: `docs/features/phase-6-developer-breadth.md`.
- **Phase 7 — Platform completeness.** Docker logs and build-cache actions, iOS backups, browser review data. Doc: `docs/features/phase-7-platform-completeness.md`.
- **Phase 8 — Productivity and system health.** Productivity caches, orphaned launch agents (report-only), Maintenance tab. Doc: `docs/features/phase-8-productivity-system.md`.
- **Phase 11 — UI redesign.** Adaptive light/dark tokens, category tiles, sidebar vibrancy, Disk Analyzer rewrite, "Tidewater" pass. Direction: `docs/design/ui-wow-audit.md`.
- **2026-10-07 wave (#38–#69).** Safety gates, explain-only diagnostics, scan coverage and reclaim reporting. See `CHANGELOG.md` and `docs/architecture/cleanup-safety.md`.

## Phase 9 — Distribution

Done: hardened-runtime entitlements, privacy usage strings, app icon, `scripts/release.sh`, `make release`, CHANGELOG. Distribution is a GitHub Releases DMG; the Mac App Store sandbox cannot scan the full disk.

- [ ] Code signing with a Developer ID Application certificate
- [ ] Notarize (`xcrun notarytool`) and staple (`xcrun stapler`) through `scripts/release.sh`
- [ ] Gatekeeper pass on a clean machine
- [ ] Tag v1.0.0 on GitHub with the signed `.dmg`
- [ ] Validate Maintenance actions on macOS 13, 14 and 15
- [ ] Phase 11 manual pass on real hardware: vibrancy, hover and press states, sheets, Reduce Motion

## Phase 10 — Selective Docker storage manager

Show what Docker stores and remove only exact, user-selected resources. `Docker.raw` is a sparse VM
disk: on 2026-07-30 it held 33 GB, of which only 2.9 GB (old build cache) was safely reclaimable;
18.5 GB were persistent volumes (one ArangoDB volume alone was 12.6 GB). `docs/features/docker-safety.md`
must be updated first to allow `docker volume rm <exact-name>` for a selected unused volume, while
still forbidding `docker volume prune`, `--volumes`, force removal and touching `Docker.raw`.

Removing the Maintenance `docker system prune -f` action ahead of Phase 10 was declined on 2026-10-03.

- [ ] **10.1 Read-only inventory.** `DockerStorageInventory` actor parsing `docker system df`, `docker buildx du`, lists and inspect output. Report three numbers: `Docker.raw` allocation, Docker-managed usage, Docker-reported reclaimable. Per volume: size, kind, labels, Compose project, attached containers, inferred purpose or "Unknown". Survive Docker absent, daemon stopped, timeouts and odd output.
- [ ] **10.2 Selection model.** A Docker card, never a scan finding. Sections for build cache, images, containers, volumes; every checkbox off by default; no cross-type select-all. Build cache `.safe`, stopped containers and unused images `.review`, volumes `.advanced`. Volumes attached to any container cannot be selected; named or > 1 GB volumes need the name typed.
- [ ] **10.3 Scoped actions.** Remove by exact ID or name only (Buildx ID filters, container ID, image ID, `docker volume rm <name>` without `--force`). Re-validate before each command, continue past single failures, re-measure, record to History, support cancel.
- [ ] **10.4 UX.** Stacked usage view, "Why is Docker.raw larger?" help, ownership evidence per volume, filters, offline and partial-failure states.
- [ ] **10.5 Verification.** Parser fixtures across CLI versions; tests that no command contains `system prune`, `--volumes` or volume force removal; selection empty by default; disposable Docker fixture; Intel and Apple Silicon.

## Phase 12 — Project dependency reclaim

Spec and reasons: `docs/features/project-dependency-reclaim.md`. 12.1 (SwiftPM `.build`, #44) and 12.2
slice 1 (#69) are done. Duplicate Chrome `IndexedDB` in the CLI was fixed by #39.

- [ ] Broken venvs (dangling `bin/python`): report regardless of activity when a lockfile or manifest exists
- [ ] Manifest-only projects with a version-drift warning (open decision C)
- [ ] "Save package list" export for venvs with no manifest (open decision C)
- [ ] Result card: at critical pressure, space returns only after emptying the Trash
- [ ] Check git at scan time too: a tracked `node_modules` is listed today, then refused at cleanup

## Engineering follow-ups

- [ ] Run the whole test suite under XCTest. Nothing from #38–#69 has run locally (Command Line Tools only); CI must confirm `integration/2026-10-07` before merging to `master`.
- [ ] One running-process seam: `RunningAppChecking` (#48), `RunningAppsProviding` (#50) and `RunningExecutablesProviding` (#57) overlap, plus direct `NSWorkspace` reads in `CodexStagingRule` and `CaskLeaveHomebrew`.
- [ ] One free-space seam: `FreeSpaceProviding` (#48, statfs) and `VolumeFreeSpaceProviding` (#54), plus private readers in `DiskHeaderProvider`, `MemoryPressureRule` and `VolumeUsageModel`. The swap-plus-low-disk warning uses different thresholds in `DiskHeaderSnapshot` and `MemoryPressureRule`.
- [ ] One swap parser: `SwapUsageParser` (`DiskHeaderSnapshot.swift`) and `SwapUsageRule.usedBytes` both parse `sysctl vm.swapusage`. Also two `lsof` field parsers (`OpenFileSnapshot`, `DeletedOpenFilesRule`).
- [ ] A `ScanFinding` copy helper that keeps every field. `GoCachesRule.annotated(with:)` drops `isSizeComplete`, so a cut-short Go cache loses its "at least".
- [ ] `FindingDeduplicator` should pass `.diagnostics` findings through untouched; today a diagnostics path can raise or swallow a cleanable finding.
- [ ] `isReclaimableVersionSibling` should also check `isNeverCleanPath`, and give a clearer skip reason ("kept: fewer than 2 newer versions").
- [ ] `CrashLoopRule` and `RegrowthDetector` keep their facts only in `reason`; move them to `FindingAnnotation` (e.g. `.regrew(days:)`).
- [ ] `RegrowthDetector`: a restored (undone) item looks 100 % regrown. Restores are not recorded.
- [ ] `Tests/PareAppTests/DiskAnalyzerViewModelTests.swift` still builds a real `CleanupEngine()` (5 sites); switch to the hermetic fixture.
- [ ] The discovery-timeout notice shows only on the scan that ran discovery.
- [ ] Verified reclaim measures only the first finding's volume; History keeps a stale empty-the-Trash hint.
- [ ] Category and tool totals don't say "at least" when a size was cut short.
- [ ] A symlinked home directory makes every cleanup item skip with no clear message.

## Product backlog

- [ ] Cache activity drives selection: skip hot, preselect cold `.safe` (open decision A)
- [ ] "Safe Care": scan, select `.safe` only, confirm, clean, optional light maintenance, in at most 3 clicks; never `.review` or `.advanced`
- [ ] App Manager: hide system apps by default, multi-select with bulk uninstall and update, confirm every update (a single cask update runs `brew upgrade --cask --greedy` without asking today)
- [ ] Maintenance: confirm Docker prune actions before running (they delete permanently), and fix the card layout. Needs a screenshot of the actual layout defect first.
- [ ] uv reclaim: a native `uv cache prune` / `uv cache clean` Maintenance action, never `--force`, no Undo (uv findings are `.advanced` until then). Later: adapters for pip, Poetry and pyenv (descriptors exist in `ToolCacheDescriptor`), user-added cache roots, and generic discovery by `CACHEDIR.TAG` (a hint only: tagged folders stay `.review`; check the tag's first 43 bytes)
- [ ] A "space freed over time" ledger from cleanup history
- [ ] Category-level exclusions (today exclusions are paths only)
- [ ] Login items browser; large Mail attachments
- [ ] First-launch onboarding, ⌘1–⌘7 sidebar shortcuts, VoiceOver labels across modules
- [ ] Results: a per-tool filter chip; suggest the 1-day Docker build-cache action when disk is low
- [ ] Disk Analyzer: "Run Smart Scan" should switch to the Smart Scan tab; skip reasons all read "policy check", and the review tray clears even when items were skipped
- [ ] Cap very large project-root sets (the store once held 495 roots)

## Scan coverage backlog

Not built yet, from field scans of a 228 GB Mac mini (2026-09-28 to 2026-10-03):

- [ ] `~/.cache/<tool>` caches no rule reports: `codex-runtimes` 1.5 GB, `kilo` 424 MB, `github-copilot` 274 MB, `hyperframes` 198 MB
- [ ] ML model weights (`*.safetensors`, `*.gguf`, `*.pth`), e.g. `Application Support/tts` 1.7 GB, Hugging Face
- [ ] Large old archives in Downloads (> 200 MB, > 90 days); never `.safe` for `.gpg`, `.age` or backup-named files
- [ ] Stale home dot-folders (e.g. `~/.9router` 2.1 GB, untouched > 90 days)
- [ ] VM disks: minikube (11 GB seen), lima, colima
- [ ] Partial downloads and updater payloads (`*.tmp-*`, `.partial`, stuck `com.docker.install/in_progress`)
- [ ] `.app` bundles outside `/Applications`, old Chrome `Versions`, extra Go toolchains, version managers, Homebrew `Library/Taps`, database dumps (`*.rdb`, `*.aof`, `*.sql`), duplicate clones
- [ ] A large-file rule (`largeFileThresholdBytes` only filters the detail list today)
- [ ] Discovery: skip folders named in MCP configs (`uv run --directory`), `actions-runner/externals` and a custom `GOMODCACHE`; collapse empty `.turbo` / `node_modules` rows
- [ ] Suggest `.metadata_never_index` for dependency trees (95 % of indexed `.js` files sat in `node_modules`)
- [ ] An "unaccounted space" line in the disk header; `--json` output for the CLI

## Long-term direction: machine-wide storage inventory

Not started. One inventory of the whole machine with several persona views, instead of more
special-case rules. Decisions so far: persona detection is automatic and non-exclusive; unknown
hotspots are shown but never cleanable; descriptors for repeated patterns, Swift code for complex
stores; no big-bang rewrite.

## Field notes

Measured facts that shaped the rules. Keep them in mind before changing a gate.

- **Trust `df`, not `du`.** pnpm hard links: deleting 152 artifact folders freed 7.26 GB by `df` against 8.0 GB by `du`. uv clonefiles: `du` showed 27 GB in uv's cache, `uv cache clean` freed about 1 GB. Most of it (19 GB in `archive-v0`) was 43 tool environments each carrying a 350 MB tree-sitter pack.
- **Deleted-but-open files can beat any cache.** On 2026-10-02, 18 `claude` processes held 3.85 GB of deleted binaries; swap was 10 GB.
- **Go caches are a working set.** `go-build` was trashed at 6.93 GB and was back to 1.3 GB three hours later.
- **WAL-unsafe VACUUM backfires.** One vacuum reclaimed 8 MB and left a 1.3 GB `-wal`. Messages `chat.db` is never vacuumed: a daemon keeps it open.
- **Google identity caches** (`GIPPseudonymousID`, `CCTClearcutLogger`) are rewritten at about 50 MB/s after deletion.
- **OpenCode `storage` is live:** `session_diff/` is still written even though `message/` and `part/` are legacy.
- **`Docker.raw` sizes lie.** 28 GB allocated against 60 GB apparent; reading the logical size once produced a 1.13 TB total on a 256 GB disk. Use allocated size and keep `.advanced` out of totals.
- **Reconstructible caches carry no multi-day gate** because the big ones are hot anyway: Chrome Cache about 600 MB, Service Worker 455 MB, `~/.npm/_npx` 1.18 GB, OpenCode cache 864 MB (2026-07).
- **Folder age:** `atime` is unreliable on APFS, and a dependency folder's mtime is its install date.
- **Speed:** one `git ls-files` per candidate blew the scan budget, so git evidence is one query per scan. Parallel rules with nested `withTaskGroup` plus actors returned empty results.
- **Project discovery:** the root store once held 495 roots, 356 under `go/pkg/mod`. Spotlight finds no `.git` folders at all.
- **Deliberately not artifacts:** `.swiftpm` (committed schemes), `.terraform` (backend state, needs credentials to rebuild).

## Won't build

Malware scanning, a menu-bar monitor, cloud-provider cleanup, photo or AI duplicate finders, macOS
update installation. An AI auto-approver for agent waves (Jev AI) was evaluated on 2026-09-27 and
rejected: labels with no reasoning, self-reported benchmarks, and code sent to a third party.
