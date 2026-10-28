# Plan: Pare — Homebrew upgrade safety (classify, preview, diagnose)

**Status:** Approved for implementation (decisions recorded in §9)
**Date:** 2026-10-28
**Reference fixtures:** [`assets/2026-10-28-homebrew-fixtures/`](./assets/2026-10-28-homebrew-fixtures/) — real outputs captured on the Tier 3 Intel Mac (see §10)
**Owner:** Pare / PareCore Homebrew + Homebrew Manager UI
**Feature doc:** [`docs/features/homebrew-manager.md`](../features/homebrew-manager.md)
**Primary code today:** `Sources/PareCore/Homebrew/BrewOutdatedChecker.swift`, `BrewBulkPlanning.swift`, `BrewRunner.swift`, `Sources/PareCore/Rules/HomebrewCacheRule.swift`, `Sources/PareApp/ViewModels/HomebrewManagerViewModel.swift`, `Sources/PareApp/Views/HomebrewManagerView.swift`

---

## 1. Problem statement

The Homebrew Manager is a list-and-run front end. It shows `brew outdated --json=v2 --greedy` rows as raw strings and runs `brew upgrade <name>` after a confirmation sheet that lists only the selected names and the argv. It does no dependency, bottle, disk or health analysis.

On an Intel Mac (Homebrew Tier 3 since September 2026, so there are **no bottles**) that is dangerous. Every row below looks like an ordinary upgrade in Pare today:

| What the user sees | What actually happens |
|---|---|
| `openssl@3 3.6.5 → 3.5.9` | A **downgrade**: homebrew-core moved `openssl@3` to the 3.5 LTS line (alias `openssl@3.5`, 3.6 now lives in `openssl@3.6`). No security gain. |
| `git 2.56.0 → 2.56.0_1`, `krb5 …_2`, `libssh2 …_7`, ~15 more | **Revision-only** rebuilds with no new upstream code (mostly the openssl@4 / icu4c@79 migration). |
| `pnpm 12.5.1 → 12.15.0` | `brew upgrade --dry-run pnpm` would **install 7 new formulae** (llvm 23, openssl@4, python@3.15, icu4c@79, z3, ninja, cxxopts) and **upgrade 14** (node, rust, cmake, simdjson 4→5 …), all from source. That is hours of compiling and well over 10 GB of disk. |
| `brotli 1.2.0 → 1.2.1` | Cheap and urgent (critical CVE), but still pulls a `cmake` rebuild as a build dependency. |
| `libunistring 1.4.2 → 1.5` | Sits under git, gnupg, neovim and postgres, so it can trigger broad rebuilds. |

Failure modes the user has already hit on this machine, none of which Pare explains:

- Disk filled mid-build: `libtool: No space left on device` (node, after 30 min); cask `unzip … exited with 50`.
- Partial upgrade left a broken keg: node linked against a `libsimdutf.*.dylib` that no longer existed.
- An orphaned `/Library/Developer/CommandLineTools/usr/include/c++/v1` shadowed the SDK libc++, so every C++ build failed with `'cstddef' file not found`.
- `docker-compose` could not `brew link` because Docker Desktop owns `/usr/local/lib/docker/cli-plugins`. A manual `/usr/local/bin/docker-compose` symlink goes stale after each upgrade.
- `~/Library/Caches/Homebrew/go_cache` and `go_mod_cache` grew to 4–5 GB each. Pare reports the whole Homebrew cache as one opaque finding.

### Out of scope

- Advisory data for casks (Phase F covers formulae only; casks are a follow-up).
- Last-used inference for formulae. The feature doc deliberately excludes shell-history and file-date heuristics, and this plan keeps that decision.
- Auto-pinning, auto-fixing, or running anything with `sudo`. Pare suggests commands for health issues; it never runs them for the user.
- Changing what `brew` itself does. Pare only previews, labels and passes documented env vars.

---

## 2. Goals

1. Every outdated row says **what kind of change** it is: downgrade/line change, revision-only, patch, minor, major or unknown.
2. Before any upgrade runs, the confirmation sheet shows **everything brew will touch**: new installs, dependency upgrades, source builds, a rough cost, and a free-disk verdict.
3. The user can opt out of dependent rebuilds per operation (`HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1`).
4. Failed operations get a **specific, actionable hint** instead of a generic "failed".
5. A report-only **Homebrew Health** view surfaces broken links, stale CLT headers and broken kegs.
6. The Homebrew cache finding is **broken down** so go_cache and go_mod_cache are visible and individually cleanable, and is never cleaned while brew is running.
7. Outdated formulae with **known security fixes** in the newer version are badged, so the user can prioritise the few upgrades that matter (Phase F).
8. Build-time estimates improve over time from **measured build durations** on this machine.
9. All new logic lives in pure, `Sendable` PareCore types with fixture-driven tests, following `BrewBulkPlanning` and `BrewListFiltering`.

---

## 3. Phase A — Classify outdated entries

### 3.1 Model

Extend `BrewOutdatedPackage` (`Models/BrewOutdatedPackage.swift`) with derived, non-breaking fields:

```swift
public enum BrewBumpKind: String, Sendable {
    case downgrade      // current < installed (e.g. openssl@3 3.6.5 → 3.5.9)
    case revisionOnly   // same upstream version, only _N changes
    case patch, minor, major
    case unknown        // unparseable (dates, commit hashes, cask build ids)
}

public let bumpKind: BrewBumpKind
public let installedDependentCount: Int?   // nil = not computed yet
```

### 3.2 Version parsing

New `BrewVersion` (PareCore, pure):

- Split the Homebrew revision: `"1.11.1_7"` gives upstream `1.11.1` and revision `7`. A missing `_N` means revision 0.
- Casks: strip the `,build` suffix (`"2.26.0,6546645232517120"` → `2.26.0`). Date-style versions (`2026-10-20`, `2026.10.22-27dcf5f`) are compared lexically, and anything they do not match is classified as `.unknown`, never `.downgrade`.
- Numeric components compare numerically; trailing pre-release text falls back to `.unknown`.
- Use the highest of `installedVersions` as the baseline.

Don't reuse `FileSystemUtils.compareVersionStrings` (`Scanning/FileSystemUtils.swift:21`) as-is: it parses `"2_3"` as 0. Either add revision handling there under its own tests or keep `BrewVersion` separate. Separate is preferred, so app-version deduplication rules are unaffected.

### 3.3 Release-line change hint

For `.downgrade` formulae, show a line-change explanation when `brew info --json=v2` lists aliases or sibling formulae (for example `openssl@3` aliased to `openssl@3.5` while `openssl@3.6` exists). The copy: "Homebrew moved this formula to another release line. Upgrading installs an older version and rebuilds its dependents." This data is already available from the inventory call (`BrewInventory`), so it needs no extra process.

### 3.4 Dependent count

`installedDependentCount` comes from `brew uses --installed <name>`. That is one process per row, so:

- Compute lazily for the visible rows after the outdated list loads, with bounded concurrency (4) and a per-call timeout.
- Cache per refresh.
- Better alternative to evaluate first: derive reverse dependencies in memory from the `dependencies` arrays already parsed in `BrewInventory` (`BrewFormula.dependencies`, currently unused). That is zero extra processes. Use `brew uses` only if the in-memory graph proves incomplete (e.g. for taps).

### 3.5 UI (Outdated tab)

- A badge next to the version pair (`HomebrewManagerView.swift` ~981–996): **Downgrade** (danger), **Rebuild** (muted, for revision-only), **Major** (warning). Patch and minor rows get no badge.
- A row caption when dependents are 10 or more: "Used by N installed formulae".
- Filter chips: *Hide rebuild-only*, *Hide downgrades*. Both are on by default and persisted in `@AppStorage`; the tab header always shows how many rows are hidden ("17 rebuild-only, 1 downgrade hidden") so nothing silently disappears.
- Downgrade rows are deselected by default and excluded from Select All Visible, the same treatment pinned rows get today (`BrewBulkPlanning.selectableOutdatedIDs`).

### 3.6 Acceptance

Using today's outdated JSON from the reference machine as a fixture:
- `openssl@3` is `.downgrade`; `git`, `krb5`, `libssh2`, `coreutils`, `cryptography` (50.0.1 → 50.0.2_2 is `.patch`, not rebuild) are classified correctly.
- `ca-certificates 2026-09-25 → 2026-10-20` is not `.downgrade`.
- Casks with `,build` ids classify on the marketing version.

---

## 4. Phase B — Upgrade impact preview

### 4.1 Source of truth: `brew upgrade --dry-run`

Don't reimplement Homebrew's resolver. `brew upgrade --dry-run <names…>` already prints the full plan (verified 2026-10-28, ~12 s on this machine):

```
==> Would install 7 dependencies:
icu4c@79     79.1
openssl@4    4.1.0
llvm         23.1.4
…
==> Would upgrade 14 dependencies:
cmake           4.4.3    -> 4.4.4
node            26.7.0   -> 26.12.1_1
rust            1.98.0   -> 1.99.1
…
==> Would upgrade 1 requested outdated package
pnpm 12.5.1 -> 12.15.0
==> 1 homebrew/core formula that would build from source
pnpm
```

New pure parser `BrewUpgradePlanParser` produces:

```swift
public struct BrewUpgradePlan: Sendable, Equatable {
    public struct Item: Sendable, Equatable {
        public let name: String
        public let fromVersion: String?   // nil for new installs
        public let toVersion: String
        public let role: Role             // .requested, .dependencyUpgrade, .newDependency
        public let buildsFromSource: Bool
    }
    public let items: [Item]
    public let unparsedLines: [String]    // kept for the raw-log disclosure
}
```

Parsing rules:
- Section headers match `^==> Would (install|upgrade) \d+ (dependenc(y|ies)|requested outdated packages?)`, and the source-build header matches `formulae? that would build from source`.
- Ignore the Tier 3 banner, warnings and hints. Run with `HOMEBREW_NO_AUTO_UPDATE=1` (already set by `BrewRunner`) plus `HOMEBREW_NO_ENV_HINTS=1`.
- **Source-build detection must not trust brew's count alone.** The "would build from source" list only names the requested packages; dependencies are compiled too. Set `buildsFromSource` from bottle availability (§4.2) for every item.
- Unknown sections go into `unparsedLines`, and the sheet shows a "Pare could not fully read Homebrew's plan" note so it never claims completeness it doesn't have.

The dry-run runs when the confirmation sheet opens. The sheet shows a progress state ("Asking Homebrew what this will do…"). The **Confirm button stays enabled** during the dry run, but the sheet shows "Plan not checked yet" if the user confirms early. Dry-run failure is non-fatal: show the error and fall back to today's sheet.

### 4.2 Bottle availability

From `brew info --json=v2 <names>` (one call for all plan items): `bottle.stable.files` keys. An item has a bottle when a key matches the current OS tag (e.g. `sequoia` on Intel, `arm64_sequoia` on Apple Silicon) or `all`. Derive the tag once per session from the `macOS:` line of `brew config` (e.g. `15.8.1-x86_64` → `sequoia`, `15.x-arm64` → `arm64_sequoia`; keep a small major-version → codename table), not from `uname` (consistent with the feature doc's rule of not shelling out for arch). An empty or missing `files` dict means no bottle. That is what Tier 3 returns: in `info-sample.json` every formula's `files` is `{}`. Dry-run output is a second signal: bottled items carry a download size in parentheses (`pycparser … -> 3.12  (78.8KB)` in `dry-run-all.txt`). On Tier 3 almost everything is source; the sheet says so once at the top ("No prebuilt bottles for this Mac — everything compiles locally").

### 4.3 Cost and disk estimate

This only needs to be honest and rough, not precise:

- A `BrewBuildCostTable` (PareCore, static data) with a coarse class per known-heavy formula: **heavy** (llvm*, rust, node*, gcc*, qt*, python@*, openssl@*, icu4c@*, go@*/go, gnupg, postgresql@*, cmake), **medium** (any other formula with C/C++ build dependencies), **light** (Go/Rust CLIs whose only build dependency is go/rust and that are already installed, npm/pip resource formulae, casks).
- Approximate disk per class (heavy 8 GB, medium 1 GB, light 0.3 GB). The sheet shows the **largest single item**, not the sum, because builds run sequentially and temp space is freed between them. Example label: "Needs ~10 GB free at peak (llvm)".
- Free space comes from `volumeAvailableCapacityForImportantUsage`. Move the resource-key read from `VolumeUsageModel.swift:47-64` into a PareCore helper so tests can stub it.
- Verdict: **OK** when free ≥ 2× peak, **Tight** when ≥ peak, **Not enough** below that. "Not enough" disables Confirm unless the user ticks "I've freed space / proceed anyway".
- **Learned build durations (in scope, v1).** See §4.7.

### 4.4 Confirmation sheet changes

`PendingConfirmation` (`HomebrewManagerViewModel.swift:58-82`) gains `plan: BrewUpgradePlanState` (`.loading`, `.ready(BrewUpgradePlan)`, `.failed(String)`), attached the same way `warnsAboutAutoUpdates` is.

`HomebrewConfirmationSheet` renders:
1. A summary line: "Upgrading 1 package pulls in 7 new + 14 dependency upgrades · 22 source builds · heavy: llvm, node, rust · disk: Tight".
2. Grouped lists (requested / dependency upgrades / new dependencies), each row with its bump badge (§3) and build class.
3. Warnings:
   - Any `.downgrade` item in the plan.
   - A new dependency that is a heavy toolchain (llvm, rust, python@*, openssl@*).
   - A dependency upgrade the user didn't select that is itself heavy.
4. Toggle **"Don't rebuild installed dependents"** sets `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=1` for this operation. Default: on for library-only selections (no `installed_on_request` formula selected), off otherwise. Helper copy: "Faster. Dependents keep working against the new library if it is ABI-compatible; Pare checks linkage afterwards (Phase C)."
5. The existing command preview, now showing the env prefix when the toggle is on.

`BrewRunner.stream` / `run` need an `extraEnvironment: [String: String]` parameter, merged in `makeEnvironment()`. The default stays empty so existing call sites are unchanged.

### 4.5 Upgrade All

"Upgrade All" (`HomebrewManagerViewModel.swift:279-295`) currently runs bare `brew upgrade`. Change it so that:
- It runs the dry run without names first and shows the same sheet.
- It warns prominently when the plan contains downgrades or more than 3 heavy builds, offering **"Upgrade only safe items"**, which converts the run to an explicit per-item list excluding downgrades, revision-only bumps and items whose plan pulls heavy builds.

### 4.7 Learned build durations

Homebrew prints a per-formula summary line after each install. It includes the build time only when the formula was compiled from source:

```
🍺  /usr/local/Cellar/mole/1.64.0: 68 files, 12.1MB, built in 10 seconds
```

(see `upgrade-log-go-clis.txt`). Durations come as `N seconds`, `N minutes M seconds` or `N hours …`, so parse every unit.

- New pure `BrewBuildLogParser` extracts `(formula, version, seconds, kegSize)` from streamed lines. The formula and version come from the Cellar path (`…/Cellar/<name>/<version>`), which also handles taps and the `/opt/homebrew` prefix. Lines without `built in` are bottle pours: record `poured` and don't record a duration.
- New `BrewBuildHistoryStore` (actor) persists to `~/Library/Application Support/Pare/brew-build-history.json`:
  ```json
  { "version": 1,
    "machine": { "arch": "x86_64", "cpu": "octa-core 64-bit kabylake" },
    "builds": [ { "formula": "mole", "version": "1.64.0", "seconds": 10,
                  "kegBytes": 12100000, "at": "2026-10-27T03:12:00Z" } ] }
  ```
  Keep the last 5 builds per formula. If `machine` changes (e.g. the history file was restored from another Mac), drop the history so Apple Silicon numbers never estimate Intel builds.
- Feed the store from `runBatch` (the same line stream as Phase C), and also from **anything Pare can see brew did outside Pare**. Backfill on first launch from `~/Library/Logs/Homebrew/<formula>/` when present. Homebrew keeps only the most recent build's logs there (`00.options.out`, `01.<step>.log`, `02.<step>.log`, `fetch.*.log`). Use the spread between the earliest and latest file mtimes as a lower-bound duration and mark it `source: "logs"`. When the spread is under 60 s, treat it as unknown, not as a fast build, because mtimes only bracket the logged steps.
- The estimate the sheet uses is: median of recorded builds for that formula when there are at least 1, else the §4.3 class default (heavy 45 min, medium 5 min, light 1 min). The sheet shows the total ("~1 h 20 min, mostly node (measured 52 min)") and marks estimates from class defaults with "≈".
- Also learn **peak disk**: record free space at build start and the minimum free space seen during the build (sample `volumeAvailableCapacityForImportantUsage` every 15 s while an operation runs). Store `peakTempBytes` beside `seconds`, and prefer it over the §4.3 class disk numbers.

### 4.8 Acceptance (reference machine fixtures)

- Selecting `pnpm` shows llvm, openssl@4, python@3.15, node and rust in the sheet, with disk verdict ≥ Tight and at least one heavy warning.
- Selecting `brotli` shows only `cmake` as a dependency upgrade, and the toggle defaults to on.
- Selecting `openssl@3` shows the downgrade warning.
- Fixture tests cover the dry-run text in §4.1, an empty plan, a plan with only casks, and output with unknown sections.
- `dry-run-all.txt` parses into 14 new installs plus 56 upgrades, despite the Tier 3 banner being interleaved **in the middle** of the output (stderr arrives mixed into stdout). In bare `brew upgrade --dry-run` the upgrade header reads `Would upgrade 56 outdated packages`, and bottled items carry a trailing download size (`pycparser … -> 3.12  (78.8KB)`). Both must parse.
- `dry-run-gh.txt` (`Warning: gh 2.103.3 already installed`) produces an empty plan, not a parse failure.
- `BrewBuildLogParser` extracts 8 builds from `upgrade-log-go-clis.txt`, `mole` with 10 s among them.

---

## 5. Phase C — Diagnose failures

### 5.1 Pattern matcher

New pure `BrewFailureClassifier` over streamed log lines, fed from `runBatch` (`HomebrewManagerViewModel.swift:504-540`) as lines arrive (keep the last ~500 lines per operation):

| Pattern | Hint id | Message / suggested action |
|---|---|---|
| `No space left on device`, `ENOSPC` | `diskFull` | "Disk filled during the build." Shows current free space, offers Smart Scan, and notes that brew caches can be cleaned once brew has exited. |
| `unzip … exited with 50` (cask) | `diskFull` | same |
| `fatal error: '…' file not found` where the header is a C++ standard header (`cstddef`, `cstdlib`, `type_traits`, …) | `cltHeaderShadow` | "Command Line Tools headers are shadowing the SDK." Links to the Health check (§6). |
| `Library not loaded: …` / `dyld: … image not found` | `brokenKeg` | "A dependency was upgraded without rebuilding this formula." Suggests `brew reinstall <formula>`. |
| `Could not symlink` / `Target … already exists` | `linkConflict` | Shows the conflicting path. Suggests `brew link --overwrite --dry-run <name>` to inspect, and warns that this is not safe for paths owned by other apps (e.g. Docker Desktop's cli-plugins). |
| `Error: … is pinned` | `pinned` | informational |

The classifier returns the first high-confidence hint per operation. The operation sheet shows it above the log. It doesn't hide the raw log.

### 5.2 Post-batch linkage check

After any batch that `partiallySucceeded`, `failed`, or ran with the dependents toggle on:
- Run `brew linkage --test <dependents of the changed formulae>` (dependents from the §3.4 graph), bounded at 30 formulae and with a timeout.
- Report broken ones in the summary ("2 formulae now reference missing libraries: node, neonctl"), each with a suggested `brew reinstall` command. Never auto-reinstall.

### 5.3 Acceptance

- Fixture logs for each pattern produce the right hint, and unrelated logs produce none.
- A simulated partial failure triggers the linkage check with the expected argv (stubbed `ProcessRunning`).

---

## 6. Phase D — Homebrew Health (report-only)

A new **Health** tab in the Homebrew Manager: add `case health = "Health"` to `HomebrewManagerViewModel.Tab` (currently Formulae / Casks / Outdated / Migrate). It has no selection and no bulk actions, so `TabState`, the bulk toolbar and `BrewBulkPlanning.selectable…` must treat it as non-selectable. When any check fails, the sidebar `homebrew` destination (`Navigation/AppRouter.swift`) shows a small issue-count badge, so problems are visible without opening the tab. The checks run on tab open and after every brew operation; "Run full check" adds the slow ones. Each check is a pure function over injected filesystem/process seams:

| Check | Method | Finding |
|---|---|---|
| Stale CLT libc++ headers | `/Library/Developer/CommandLineTools/usr/include/c++/v1` exists **and** lacks `cstddef` (or is far smaller than the SDK copy) | "Orphaned C++ headers from an older CLT", with the suggested `sudo mv` command shown and never run |
| Dangling links under the prefix | Scan `<prefix>/bin`, `<prefix>/lib/docker/cli-plugins`, `<prefix>/opt` for symlinks whose target doesn't exist. Flag links into `Cellar/<name>/<version>` where that version is no longer installed **and** a newer version is | "docker-compose → Cellar/docker-compose/5.6.0 (removed); current 5.6.1", with the suggested relink command |
| Broken kegs | `brew linkage --test` for `installed_on_request` formulae. This is slow, so it only runs **on demand** ("Run full check") | "Formula references missing library …" |
| `brew missing` | One call | Missing dependencies |
| Disk headroom | Free space versus the heavy-build threshold | "Less than 10 GB free — large source builds will fail" |

The dangling-link scan is a candidate for a reusable rule shape similar to `OrphanedLaunchAgentsRule`, but it stays inside the Homebrew module because the fix is brew-specific.

### 6.1 Acceptance

- Temp-dir fixtures with a fake CLT include dir (with and without `cstddef`) and a fake prefix with good, dangling and stale-version links.
- No check writes to disk or runs anything with `sudo`.

---

## 7. Phase E — Homebrew cache breakdown

- `HomebrewCacheRule.customScan` (`Rules/HomebrewCacheRule.swift:18-28`) emits **separate findings** for the large known children: `go_cache`, `go_mod_cache`, `downloads`, `Cask`, `api`, `bootsnap`, plus one "other" finding for the rest. Reasons are specific, e.g. "Go build cache used by Homebrew source builds — regenerated on next Go formula build".
- `go_mod_cache` files are read-only (Go's default). Moving the directory to Trash works, but emptying the Trash fails on read-only files. Before moving, `CleanupEngine` must either clear write bits (through a `ScanPolicy`-approved helper) or the finding must say "Use Maintenance → Clean Homebrew Go caches". Prefer the Maintenance action for this one.
- **Never clean while brew is running.** If a `brew` process is alive (check through the existing process-listing seam, or `pgrep -x brew` / Ruby `brew.rb`), mark these findings as "Homebrew is running — skipped" and exclude them from Quick Clean. Deleting `downloads` mid-upgrade removes the tarball of the formula being built.
- Make sure the `ScanPolicy` markers (`ScanPolicy+Markers.swift` 18, 199, 406, 442) still match the child paths; add tests.
- New Maintenance actions (`Maintenance/MaintenanceAction.swift`):
  - **Clean Homebrew Go caches**: `chmod -R u+w` then remove `go_cache` and `go_mod_cache`. Guarded by the brew-running check.
  - **Homebrew cleanup**: `brew cleanup --prune=all`. Guarded the same way; shows a dry-run (`brew cleanup -n`) summary before running.

### 7.1 Acceptance

- Fixture cache tree produces per-child findings whose sizes sum to the old single finding.
- The brew-running stub makes the findings non-cleanable.
- The rule count in CLAUDE.md is unchanged (same rule, more findings).

---

## 8. Phase F — Security fix badges (OSV)

### 8.1 Why

The 2026-10-28 audit of the reference machine found that out of ~50 outdated formulae, only a handful carried real security fixes: brotli (critical RCE, CVE-2026-111497), c-ares (11 advisories), node (10 CVEs), uv (critical, a trusted compromised root CA), python@3.13/3.14 and tor. Everything else was rebuild noise. The Outdated tab should make those few stand out.

### 8.2 Data source

[OSV](https://osv.dev) `POST https://api.osv.dev/v1/querybatch` (no auth, batch up to 1000 queries). Homebrew isn't an OSV ecosystem, so each formula needs a mapping. New `BrewAdvisoryResolver` tries, in order:

1. **Curated map** (`BrewAdvisoryMap.swift`, static data, reviewed in PRs). Formula name to OSV `(ecosystem, package)`, e.g.:

   | Formula | OSV query |
   |---|---|
   | `uv`, `cryptography`, `pre-commit`, `magic-wormhole` | `PyPI` / same name |
   | `vite`, `neonctl`, `pnpm`, `yarn` | `npm` / same name |
   | `gh`, `glab`, `helm`, `k6`, `kubernetes-cli`, `docker-compose`, `prometheus` | `Go` / module path (e.g. `github.com/cli/cli/v2`), plus the Go **stdlib** at the toolchain version (see 4) |
   | `rust` | `GIT` / `https://github.com/rust-lang/rust` (not `crates.io`, which covers crates, not the toolchain) |
   | `node`, `openssl@*`, `python@*`, `postgresql@*`, `git`, `sqlite`, `curl` | `Bitnami` ecosystem names (`node`, `openssl`, `python`, `postgresql`, `git`, `sqlite`) — **verify each name against OSV before shipping** |

2. **`GIT` ecosystem fallback.** When the formula's `urls.stable.url` or `head.url` is a GitHub repository and the version maps to a tag, query `{"package": {"ecosystem": "GIT", "name": "https://github.com/<owner>/<repo>"}, "version": "<tag>"}`. Try both `v<version>` and `<version>`. This covers many C libraries (c-ares, brotli, libssh2, libgit2…). **Verify the GIT-version query shape against the OSV API docs first;** if it isn't supported, fall back to commit-based queries only when the tag resolves via the GitHub API, or drop this tier.
3. **Unmapped:** no badge, and a "no advisory data" tooltip. Never imply "safe".
4. **Go binaries:** `go version -m <binary>` gives the toolchain version (e.g. `go1.27.0`). Query OSV `Go` / `stdlib` at that version. This is how the audit found kubectl, migrate and prometheus carrying 13 stdlib advisories fixed in go1.27.2. The binary path comes from the keg (`<prefix>/opt/<name>/bin/*`), first Mach-O file only. This needs `go` installed; skip it when go isn't there.

Always use the **upstream** version (strip `_N`, §3.2). A revision-only bump never gets a security badge from OSV, although Homebrew patches can carry fixes (e.g. `libssh2 1.11.1_7` adds a backported CVE fix). Show that case as "Homebrew-patched — check the formula changelog" only when the formula's `patches` list changed, which needs no OSV lookup; it is a v2 nicety and may be skipped.

### 8.3 Logic

For each outdated formula, query both installed and current versions. A badge appears when some advisory **affects the installed version and not the current version** ("fixed by this upgrade"). Severity is the highest CVSS from `severity[]` or `database_specific.severity`. Badge levels: **Security · Critical/High** (danger colour) or **Security** (warning colour, for Medium/Low/unknown). The tooltip lists ids (CVE/GHSA) and summaries, linking to `https://osv.dev/vulnerability/<id>`.

Also surface **"vulnerable, no fix in Homebrew yet"**: advisories that affect both versions. Show these as a muted badge, so the user knows upgrading won't help.

### 8.4 Caching, privacy, failure

- Cache responses for 24 h in `~/Library/Application Support/Pare/osv-cache.json`, keyed by `(ecosystem, package, version)`, like the cask catalog cache (`MigrationAdvisor.swift:9-11`).
- Only package names and versions leave the machine. No paths, no hostnames. State this in Settings with a toggle **"Check for security advisories (osv.dev)"**, default **on**.
- Offline or HTTP errors: no badges, and a quiet "Advisory data unavailable" line in the tab header. Never block the outdated list.

### 8.5 Sort and filter

- New sort **"Security first"**, which becomes the default sort on the Outdated tab when any badge exists.
- A filter chip **"Security fixes only"**.
- The upgrade sheet (§4.4) shows the badges next to the plan items. The summary line says "3 upgrades fix known vulnerabilities".
- **"Upgrade only safe items"** (§4.5) gains a sibling **"Upgrade security fixes only"**. It selects badged items whose plan isn't heavy, and turns on the "Don't rebuild dependents" toggle for library-only items. On the reference machine that resolves to exactly `brotli` + `c-ares`.

### 8.6 Acceptance

- A stubbed OSV client with recorded responses (add them to the fixtures directory when implementing) badges `brotli 1.2.0` Critical and `c-ares 1.34.8` High, and gives `git 2.56.0 → 2.56.0_1` no badge.
- Network failure gives no badges and no error dialogs.
- The Settings toggle off means zero requests (assert on the stub).

---

## 9. Decisions, delivery order and open questions

### 9.1 Decisions (owner, 2026-10-28)

1. **Health is its own Homebrew tab** (§6), with an issue badge on the sidebar destination. A separate sidebar destination was also acceptable; the tab won because every check is Homebrew-specific.
2. **Security badges are in scope** (Phase F, §8).
3. **Learned build durations are in scope** (§4.7), including peak-disk learning.

### 9.2 Delivery order

| PR | Phase | Value | Risk | Size |
|---|---|---|---|---|
| 1 | A — classify | High: stops the openssl-style trap immediately | Low (pure parsing + badges) | S |
| 2 | B — preview (§4.1–4.6) | Highest: shows the cascade before it starts | Medium (dry-run latency, parser drift across brew versions) | M–L |
| 3 | F — security badges | High: tells the user which few upgrades matter | Medium (OSV mapping quality) | M |
| 4 | B — learned durations (§4.7) + C — diagnose | Medium; both consume the same streamed log | Low | M |
| 5 | E — cache breakdown | Medium | Low | S |
| 6 | D — Health tab | Medium | Low (report-only) | M |

Land `BrewRunner`'s `extraEnvironment` as its own small commit inside PR 2. PRs 3 and 4 only depend on PR 1 (`BrewVersion`) and can run in parallel after it.

Each PR follows the repo's always-on checklist: `make build`, `make test`, `make run-app` smoke test, `gitnexus_impact` before editing any symbol and `gitnexus_detect_changes` before commit. Update `docs/features/homebrew-manager.md` (in particular the "Upgrade All" section, which currently documents bare `brew upgrade`) and `docs/roadmap.md`.

### 9.3 Open questions (resolve during implementation)

1. **Does `--dry-run` show dependents that brew will rebuild?** On 2026-10-28, `brew upgrade --dry-run brotli` and `--dry-run openssl@3` listed no dependent rebuilds, with and without `HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK`. Yet openssl@3 has ~20 installed dependents. Read Homebrew's `cmd/upgrade.rb` / `Upgrade.check_installed_dependents` to learn whether dry-run skips that step. If it does, the sheet must add the dependents from the §3.4 graph under "May also rebuild (Homebrew decides at run time)".
2. **Dry-run parser stability.** The output is human text, not JSON. Pin the parser with fixtures and degrade gracefully (§4.1 `unparsedLines`). Check whether the installed brew offers machine-readable plan output and prefer it when it exists.
3. **OSV mapping coverage** (§8.2). Verify the Bitnami names and the GIT-ecosystem version query before shipping. Report the coverage share ("advisory data for 31 of 42 formulae") in the tab header so gaps are visible.

---

## 10. Notes for the implementer

- **You probably can't reproduce the reference machine.** It is an Intel Mac where Homebrew is Tier 3: no bottles, everything builds from source, and the Tier 3 banner is printed on every command. An Apple Silicon Mac has bottles for nearly everything, so live `brew` output there looks different: shorter dry-runs, "Pouring" instead of "built in", no banner. Build and test against the **fixtures**, not your machine's live brew output. Treat live runs only as a smoke test.
- **Fixtures** live in [`assets/2026-10-28-homebrew-fixtures/`](./assets/2026-10-28-homebrew-fixtures/). Home paths are anonymised as `/Users/USER`. Copy what the tests need into `Tests/PareCoreTests/Fixtures/Homebrew/` and wire them as SwiftPM test resources (`resources: [.copy("Fixtures")]` on the test target), or embed them as string literals if the test target has no resources yet. Don't read them from `docs/` at test time.

  | File | What it is | Used by |
  |---|---|---|
  | `outdated-greedy.json` | `brew outdated --json=v2 --greedy` with ~50 formulae and casks: openssl@3 downgrade, many `_N` bumps, cask `,build` ids, date versions | §3 classifier |
  | `info-sample.json` | `brew info --json=v2 openssl@3 openssl@3.6 brotli pnpm node git`: aliases (`openssl@3` → `openssl@3.5`), dependency lists; `bottle.stable.files` is **empty** for all six on this Tier 3 machine (on Apple Silicon it is populated, so test both shapes) | §3.3, §3.4, §4.2 |
  | `dry-run-pnpm.txt` | 7 new deps + 14 dep upgrades + 1 requested | §4.1 parser, §4.8 |
  | `dry-run-brotli.txt` | `cmake` dependency upgrade only | §4.8 |
  | `dry-run-openssl-at-3.txt` | the downgrade, no dependents listed | §4.8, §9.3 Q1 |
  | `dry-run-gh.txt` | "already installed", empty plan | §4.8 |
  | `dry-run-all.txt` | bare `brew upgrade --dry-run`: 14 installs, 56 upgrades, the banner in the middle, bottle sizes | §4.1, §4.8 |
  | `upgrade-log-go-clis.txt` | streamed log from a real 11-formula upgrade: `built in` lines, cleanup lines, caveats, the docker-compose shadowing warning | §4.7, §5 |
  | `brew-config.txt` | `brew config` on the reference machine (`macOS: 15.8.1-x86_64`, CLT-only) | §4.2 OS tag derivation |

- **The machine-readable fields are from Homebrew 7.0.11.** Decoders must ignore unknown keys and tolerate missing optional ones. The existing code uses `JSONSerialization` with optional casts; keep that style rather than strict `Codable` for brew JSON.
- **No new ways to mutate the system.** The only new actions that change anything are the Maintenance actions in §7 and the env toggle in §4.4. Both go through the existing confirmation-sheet pattern. Health (§6) and failure hints (§5) only display suggested commands, as copyable text.
- **Process budget.** Opening the Outdated tab must stay under the current cost plus one batched `brew info` call. Per-row `brew uses` calls are a fallback only (§3.4). The dry run runs only when a confirmation sheet opens. OSV is one `querybatch` request per refresh, cached for 24 h.
