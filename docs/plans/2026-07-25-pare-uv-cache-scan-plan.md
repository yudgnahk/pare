# Plan: Pare — detect reconstructible uv (and XDG Python) caches

**Status:** Revised draft after safety review (do not implement until approved)
**Date:** 2026-07-25  
**Owner:** Pare / PareCore  
**Related investigation:** [`UV_INVESTIGATION.md`](../../UV_INVESTIGATION.md)  
**Companion plan:** [`2026-07-25-crg-uvx-pin-plan.md`](./2026-07-25-crg-uvx-pin-plan.md)  
**Parent architecture:** [`2026-07-25-pare-machine-wide-storage-intelligence-plan.md`](./2026-07-25-pare-machine-wide-storage-intelligence-plan.md)
**Primary code today:** `Sources/PareCore/Rules/PythonCachesRule.swift`, `Sources/PareCore/Scanning/ScanPolicy.swift`

---

## 1. Problem statement

This is the uv-first vertical slice of Pare's broader machine inventory and ecosystem-classification architecture. It should validate portable discovery, descriptor-driven evidence, report-only classification, and native cleanup without becoming the generic architecture itself.

On the investigator’s machine:

| Path | Status |
|------|--------|
| `uv cache dir` | `/Users/kelvin/.cache/uv` (~**20 GB**) |
| `~/Library/Caches/uv` | **Missing** |
| Pare `PythonCachesRule` | Only scans `Library/Caches/{pip,pypoetry,uv}` + `~/.pyenv/cache` |

**Result:** Pare **does not report** the real uv cache. Same class of gap as Mole’s dry-run under-reporting, but for Pare the miss is **wrong path family** (macOS Library vs XDG `~/.cache`).

### Why this matters

- Modern Homebrew `uv` defaults to **XDG-style** `~/.cache/uv` (confirmed: `uv cache dir`).
- Contents are **always reconstructible** package/tool download + env archives (not user project data).
- Large installs (e.g. `code-review-graph` + `tree-sitter-language-pack`) make this a **top disk consumer**.
- Pare has reusable package-cache policy machinery, but uv needs both **portable discovery** and a **tool-native cleanup exception**; adding one more substring marker is insufficient.

### Out of scope for this plan

- Changing how uv or CRG package dependencies work (see companion pin plan).
- Full-home dynamic “largest folders” scan as primary discovery.
- Implementing every package manager adapter in the first change; only uv is required for the initial end-to-end slice.

---

## 2. Goals

1. Discover uv caches from **platform roots**, **XDG configuration**, and `uv cache dir` instead of assuming one absolute layout.
2. Report each unique existing non-empty uv cache as one whole-folder finding.
3. Keep **discovery broader than cleanup authorization**: do not move a live uv cache to Trash directly.
4. Add a reusable cache-root/discovery layer that can cover pip, Poetry, and other tools on different machines.
5. Surface unknown or tagged cache directories conservatively as `.review`/informational findings, never automatic `.safe` cleanup.
6. Keep tests deterministic with injected fake homes, environment variables, command results, and cache roots.

### Non-goals

- Parsing uv's private cache buckets or deleting selected packages inside them.
- Scanning arbitrary `~/.cache/*` without an allowlist (too broad for `.safe`).
- Treating every directory under a cache root as automatically safe to delete.

---

## 3. Current architecture (relevant)

### `PythonCachesRule`

```swift
// Today (conceptual)
Library/Caches/pip
Library/Caches/pypoetry
Library/Caches/uv
~/.pyenv/cache
```

- `customScan` only; whole directory size via `FileSystemUtils.directorySize`.
- Category: `.developerPackageCaches`
- Risk: `.safe`, confidence `0.95`
- Empty / missing dirs skipped

### Policy gates for cleanup

Cleanup requires (among other checks):

```text
ScanPolicy.isLowImpactPath(url)
  OR CleanupEngine.isPersonaPath(url)  // includes developerPackageCacheMarkers
  OR wrong-platform / installer / project-artifact exceptions
```

Reconstructible caches:

```text
ScanPolicy.reconstructibleCachePathMarkers
  → minimumAgeSeconds = 0 (no multi-day age gate)
```

**Today:** neither `/.cache/uv` nor `/.cache/pip` appear in:

- `reconstructibleCachePathMarkers`
- `developerPackageCacheMarkers`

`ScanReportAnnotator` already special-cases `/.cache/pip` and `/.cache/opencode` for attribution-ish path matching — **not** `/.cache/uv`.

Important distinction: adding a marker would currently authorize cleanup through `path.contains(marker)`. That is too broad for new generic discovery and would also match neighboring names such as `/.cache/uvicorn`. Discovery must not depend on substring-based cleanup authorization.

---

## 4. Proposed design

### 4.1 Core principle: discover broadly, clean narrowly

Use separate concepts:

```text
Cache location discovery
  → may report a directory and its size

Cache classification
  → known tool, valid CACHEDIR.TAG, or unknown cache-root child

Cleanup strategy
  → tool-native command, Trash-eligible exact path, or report-only
```

A directory being under a cache root is strong evidence that it is non-essential storage, but it is not proof that arbitrary filesystem deletion is safe while its owning tool is running. uv explicitly requires callers to use its cache commands rather than modifying the cache directly.

### 4.2 Generic cache-root resolver

Introduce a reusable `CacheRootResolver` (name illustrative) whose inputs can be injected in tests.

Resolve these roots in order and deduplicate canonical URLs:

1. **Platform user cache root** — use Foundation:

   ```swift
   FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)
   ```

   On macOS this normally resolves the user's `~/Library/Caches` location. Do not hard-code it in production logic. For a fake `homeDirectory`, inject a fake platform root rather than consulting the real user's Foundation directory.

2. **XDG cache root**:

   - If `XDG_CACHE_HOME` is set to a non-empty **absolute** path, use it.
   - Otherwise use `environment.homeDirectory/.cache`.
   - Ignore relative `XDG_CACHE_HOME` values as required by the XDG Base Directory specification.

3. **Configured/tool-native locations** supplied by tool adapters, such as `uv cache dir`.

4. **User-added scan roots** in a later phase for caches on another volume or an unconventional home layout.

Root validation:

- Standardize/canonicalize paths and dedupe without following an untrusted symlink outside the approved root.
- Reject `/`, the bare home directory, bare `~/Library`, device/system roots, and unreadable paths.
- Record the discovery source (`platform`, `xdg`, `tool`, `tag`, `user`) for explanation and testing.
- A cache outside the user's home is report-only until explicitly approved.

### 4.3 Tool cache descriptors, not full-path lists

Represent known tools as descriptors relative to discovered roots:

```text
id: uv
candidate child names: ["uv"]
native discovery: `uv cache dir`
native cleanup: `uv cache prune` / `uv cache clean`
filesystem cleanup: forbidden
```

The descriptor catalog still contains tool identities and relative child names, but no machine-specific full paths. One descriptor automatically checks Foundation, XDG, tool-reported, and later user-added roots.

Initial descriptors:

| Tool | Child name(s) | Native discovery | Cleanup posture |
|------|---------------|------------------|-----------------|
| uv | `uv` | `uv cache dir` | Native command only |
| pip | `pip` | `python -m pip cache dir` or `pip cache dir` | Prefer native `pip cache purge`; validate separately |
| Poetry | `pypoetry` | `poetry config cache-dir` | Prefer native command if supported; otherwise review |
| pyenv | not root-relative (`.pyenv/cache`) | none | Existing exact legacy target |

Tool command discovery is not a network operation. Use a short timeout, null stdin, bounded stdout, and ignore failure. Finder-launched GUI apps may not inherit the user's shell `PATH`, so executable resolution should check the process PATH plus conventional Homebrew locations and allow injection in tests. Never source shell startup files.

### 4.4 uv discovery and reporting (MVP)

Candidate locations for uv are the union of:

- `<Foundation caches root>/uv`
- `<resolved XDG cache root>/uv`
- absolute `UV_CACHE_DIR` from the app's environment, if present
- successful, validated output from `uv cache dir`

The CLI result has highest explanatory confidence because it accounts for the configuration visible to that invocation, including `UV_CACHE_DIR` and applicable `tool.uv.cache-dir`. It cannot reveal every project-specific or per-command `--cache-dir` used elsewhere on the machine. Static root-derived candidates remain fallbacks for machines where uv is absent or not executable from the GUI; user-added roots cover known exceptional locations later.

Emit one finding per unique existing non-empty directory. Do not merge two physical roots. Suggested finding:

- Category: `.developerPackageCaches`
- Risk: `.advanced` or a new report-only/native-cleanup posture until the Maintenance action exists
- Reason: `"uv cache — reclaim with uv's cache command"`
- Metadata/source label: `uv CLI`, `XDG`, or `macOS cache root`

Do **not** add `/.cache/uv` to `developerPackageCacheMarkers` merely to make Trash cleanup pass.

### 4.5 Generic discovery inside cache roots

After the uv MVP, add a bounded `CacheDiscoveryRule`:

1. Enumerate only immediate children of approved cache roots by default.
2. Match known descriptor child names and hand them to their tool-specific classifier.
3. Recognize a valid `CACHEDIR.TAG` only when it is a regular file whose first 43 bytes equal the required signature.
4. Optionally surface other large child directories above a configurable threshold as `"Unclassified cache storage"` with `.review` risk.
5. Do not follow symlinks, descend into package/project trees, or scan the entire home directory.

On macOS, optionally reuse Pare's existing `NSMetadataQuery` pattern to search the user-home Spotlight index for files named `CACHEDIR.TAG`. This can find tagged caches outside conventional roots without walking the full home directory. Every hit must still pass regular-file/signature validation and is only a `.review` hint. Spotlight may be disabled, incomplete, or stale, so failure yields no error and bounded root enumeration remains the deterministic fallback.

`CACHEDIR.TAG` is useful portable evidence that contents are regenerable, but its own security guidance says to treat tags as hints. Therefore:

- known descriptor + tag may increase confidence;
- an unknown tagged directory is still `.review`, not automatically `.safe`;
- an unknown untagged cache-root child is informational/review only;
- no generic discovery result becomes cleanable solely because its path contains `cache`.

Use scan budgets: cancellation support, maximum root count, maximum initial depth, and elapsed-time/file-count telemetry. Large trees such as uv should be sized off the main actor and measured on representative machines.

### 4.6 Exact path policy

Replace new substring proposals with a path-component helper:

```text
isEqualToOrDescendant(candidate, root)
```

It must match:

- `/Users/a/.cache/uv`
- `/Users/a/.cache/uv/archive-v0`

It must reject:

- `/Users/a/.cache/uvicorn`
- `/Users/a/.cache/uv-backup`
- `/Users/a/.cache/pipx` when the approved root is `…/.cache/pip`

Cleanup authorization should use the exact discovered/canonical root plus its declared cleanup strategy, not a globally broad substring marker.

### 4.7 Native uv Maintenance action (required for cleanup)

Add a follow-up Maintenance action that invokes uv directly:

```text
Conservative: uv cache prune
Full reclaim: uv cache clean
```

Requirements:

- Use the same resolved uv executable and cache context as discovery.
- Show that tool-native cleanup is not Trash/undo-capable before confirmation.
- Do not pass `--force`; let uv wait for or report active uv commands.
- Stream output and surface lock timeout/non-zero exit.
- Re-scan the discovered cache afterward and report actual bytes reclaimed.

Until this exists, uv findings are detect/report-only. Pare must never move the uv cache directory to Trash directly.

---

## 5. Implementation plan (files)

| File | Change |
|------|--------|
| New `Sources/PareCore/Scanning/CacheRootResolver.swift` | Resolve injected platform, XDG, configured, tool-reported, and user-added cache roots |
| New `Sources/PareCore/Scanning/ToolCacheDescriptor.swift` | Describe relative child names, discovery adapter, and cleanup strategy |
| `Sources/PareCore/Rules/PythonCachesRule.swift` or new `UvCacheRule.swift` | Use resolved candidates; keep pyenv legacy target; emit uv as report-only/native-cleanup |
| New process helper or existing runner extraction | Short-timeout, null-stdin command capture reusable by discovery and Maintenance |
| `Sources/PareCore/Scanning/ScanPolicy.swift` | Add exact-root/component matching helper; do not add broad `/.cache/uv` cleanup marker |
| `Sources/PareCore/ScanReportAnnotator.swift` | Attribute descriptor identity, preferably without new substring checks |
| `Sources/PareCore/Maintenance/*` | Follow-up `uv cache prune/clean` native action |
| `Tests/PareCoreTests/Phase6RuleTests.swift` | Root resolution, uv discovery, dedupe, empty skip, and finding posture |
| New policy/discovery tests | Boundary negatives, malicious/relative roots, symlinks, tags, timeouts, custom paths |
| `docs/features/phase-6-developer-breadth.md` | Document resolved macOS/XDG/tool-native roots and report-only uv cleanup |
| `CLAUDE.md` / `AGENTS.md` known-state bullet (optional) | Describe generic cache discovery and native-cleanup exception |

Do not change `CleanupEngine` merely to pass uv through existing persona markers. Native-cleanup findings should remain blocked from Trash.

---

## 6. Tests (TDD-style)

Follow existing `PythonCachesRuleTests` patterns (`makeTempDir`, `createDirWithContent`, fake `ScanEnvironment.homeDirectory`).

| Test | Expectation |
|------|-------------|
| `testResolvesInjectedPlatformCacheRoot` | fake Foundation root is used; real home is never consulted |
| `testResolvesDefaultXDGRoot` | unset XDG → `<fake-home>/.cache` |
| `testResolvesAbsoluteXDGOverride` | absolute `XDG_CACHE_HOME` is used |
| `testRejectsRelativeXDGOverride` | relative XDG value is ignored |
| `testDetectsXDGUvCache` | root-derived `uv` with content → report-only/native-cleanup finding |
| `testDetectsPlatformUvCache` | injected platform cache root `/uv` works |
| `testDetectsConfiguredUvCache` | stubbed `uv cache dir` outside defaults is detected after validation |
| `testDeduplicatesUvCandidates` | XDG, environment, and CLI resolving to one URL → one finding |
| `testDetectsBothUvRootsIndependently` | two physical roots → two findings |
| `testEmptyUvSkipped` | empty directory → no finding |
| `testToolTimeoutFallsBackToRoots` | timeout/failure does not fail the scan |
| `testRejectsUnsafeToolOutput` | `/`, bare home, relative paths, system roots, and NUL/newline garbage rejected |
| `testUvFindingCannotPassTrashCleanup` | direct filesystem cleanup remains blocked |
| `testExactRootBoundary` | `uv` root/descendant matches; `uvicorn` and `uv-backup` do not |
| `testValidCacheTag` | regular file + exact signature recognized |
| `testInvalidOrSymlinkedCacheTag` | filename alone does not grant cache classification |
| Maintenance integration | stubbed `uv cache prune/clean` arguments, output, lock timeout, and rescan verified |

Run:

```bash
make build
make test
# or: swift test --filter PythonCachesRuleTests
```

---

## 7. Manual verification

On developer machines with default and customized uv cache layouts:

1. Build and run app / CLI scan.
2. Confirm default finding path `~/.cache/uv` with size of the same order as `du -sh`.
3. Set a temporary `XDG_CACHE_HOME` / `UV_CACHE_DIR` fixture or stub `uv cache dir`; confirm the custom path is found and deduplicated.
4. Confirm the UI identifies the discovery source and says cleanup is tool-native/report-only.
5. Confirm direct Trash cleanup is unavailable for uv.
6. In a temp fixture or after explicit consent, run the Maintenance `prune` action and verify uv handles active-process locking.
7. Confirm non-targets untouched: `~/.local/share/uv/tools`, `~/.local/share/uv/python`, project `.venv`, `.code-review-graph/`.

**Safety note for reviewers:** uv cache contents are reconstructible and separate from project graphs, but direct filesystem modification is unsafe while uv is active. Prefer temp fixtures and stubbed commands. Use the real cache only after the CRG pin cutover and with explicit consent.

---

## 8. Risk analysis

| Risk | Level | Mitigation |
|------|-------|------------|
| Reporting active tool state as directly trashable | High | uv finding is report-only/native-cleanup; no filesystem Trash |
| Race with active uv/uvx process | High | Invoke uv without `--force`; surface lock timeout and retry guidance |
| Broad marker matches `uvicorn`/`uv-backup` | High | Exact canonical root/component matching + negative tests |
| GUI does not inherit shell PATH/XDG variables | Medium | Platform/default roots plus executable resolver and tool fallback; never source shell files |
| Duplicate results from root/env/CLI discovery | Medium | Canonical URL dedupe and discovery-source aggregation |
| `UV_CACHE_DIR` outside home | Medium | Report-only unless validated and explicitly approved |
| Symlink escapes approved root | Medium | Do not follow symlinks; canonical containment check |
| Forged or accidental `CACHEDIR.TAG` | Medium | Validate regular file + signature; tag remains a review hint |
| Huge directory size scan time | Medium | Off-main sizing, cancellation, budgets, and representative performance measurements |
| Double-count with `UserCachesRule` | Low–Med | Central candidate registry/dedupe by canonical root before findings are emitted |

---

## 9. Explicit non-targets (must not scan as safe uv cache)

| Path | Why |
|------|-----|
| `~/.local/share/uv/tools` | Installed tools (pinned installs), not pure download cache |
| `~/.local/share/uv/python` | Managed interpreters |
| Project `.venv` / `venv` | Project environments |
| `<repo>/.code-review-graph/` | User graph data |
| Arbitrary `~/.cache/*` | May include non-reclaimable app state |

---

## 10. Success metrics

- Machine with only `~/.cache/uv` populated shows a Pare finding of correct order-of-magnitude size.
- `make test` green; new Phase 6 tests pass.
- Direct Trash cleanup rejects uv findings; the Maintenance action uses uv's own command.
- Docs explain platform, XDG, configured, tool-reported, tagged, and user-added discovery sources.

---

## 11. Implementation phases

| Phase | Scope | Ship? |
|-------|--------|-------|
| **A — Resolver + uv detection** | Platform/XDG roots, uv descriptor, stubbed `uv cache dir`, canonical dedupe, report-only finding | **Yes** |
| **B — uv Maintenance** | `uv cache prune` default + explicit full clean, locking/error UX, rescan | **Required before cleanup** |
| **C — Generic cache-root discovery** | Immediate children, descriptor catalog, valid `CACHEDIR.TAG`, optional Spotlight tag search, unknown `.review` findings | Follow-up |
| **D — More tool adapters** | pip, Poetry, npm, Cargo, Homebrew and other native discovery/cleanup commands | Incremental |
| **E — User-added roots** | External volumes/custom homes with approval and containment policy | Later |

---

## 12. Suggested code sketch (illustrative, not final)

```swift
// Illustrative only: dependencies are injectable for deterministic tests.
let roots = await cacheRootResolver.resolve(environment: environment)
let uvDescriptor = ToolCacheDescriptor(
    id: "uv",
    childNames: ["uv"],
    discovery: .command(executable: "uv", arguments: ["cache", "dir"]),
    cleanup: .nativeCommandOnly
)
let candidates = await toolCacheDiscovery.candidates(
    for: uvDescriptor,
    roots: roots,
    environment: environment
)
// Canonicalize, validate, dedupe, size off-main, then emit report-only findings.
```

```swift
// Boundary-aware policy — do not use `path.contains("/.cache/uv")`.
isEqualToOrDescendant(candidate, root: discoveredCanonicalUvRoot)
```

---

## 13. Open questions for reviewer

1. Split uv into `UvCacheRule` now, or keep a descriptor-driven implementation behind `PythonCachesRule` until more tools migrate?
2. Add a new explicit `nativeCleanupOnly` finding capability, or represent uv as `.advanced` until that model exists?
3. Should generic unknown cache-root children appear only above a size threshold (recommended) or all appear under a collapsed review section?
4. Should valid `CACHEDIR.TAG` directories default to `.review` (recommended) or informational-only?
5. Is `uv cache prune` the only v1 Maintenance action, with full `clean` behind an additional confirmation?
6. Should user-added external cache roots be persisted globally or per machine/profile?

---

## 14. Dependencies / sequencing with companion plan

| Plan | Relation |
|------|----------|
| CRG pin plan | Reduces future uv cache growth and stops long-lived uvx parents after cutover |
| This plan Phase A | Makes Pare visible to default and customized uv caches without enabling unsafe Trash cleanup |
| This plan Phase B | Adds locked, tool-native reclaim |
| Suggested order | Pin CRG first, then ship resolver/detection, then native Maintenance cleanup |

---

## 15. References

- `UV_INVESTIGATION.md` — sizes, Mole behavior, `tree-sitter-language-pack` analysis  
- `Sources/PareCore/Rules/PythonCachesRule.swift`  
- `Sources/PareCore/Scanning/ScanPolicy.swift` — `reconstructibleCachePathMarkers`, `developerPackageCacheMarkers`  
- `Sources/PareCore/Cleanup/CleanupEngine.swift` — `isPersonaPath`  
- `Tests/PareCoreTests/Phase6RuleTests.swift`  
- `docs/features/phase-6-developer-breadth.md`  
- Mole (external): `clean_uv_cache` uses `uv cache dir` + `uv cache prune` — reference only, not copy wholesale
- Apple Foundation cache-directory APIs: https://developer.apple.com/documentation/foundation/filemanager/searchpathdirectory/cachesdirectory
- XDG Base Directory specification: https://specifications.freedesktop.org/basedir/
- Cache Directory Tagging specification: https://bford.info/cachedir/
- uv cache location, safety, locking, and cleanup: https://docs.astral.sh/uv/concepts/cache/
