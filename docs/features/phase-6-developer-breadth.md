# Phase 6 — Developer Ecosystem Breadth

Expand Pare's developer profile from Xcode/JS-centric to full polyglot coverage, and replace the Phase 5 project artifact purge (which requires the user to specify paths) with automatic project discovery via Spotlight.

## Goals

- Add cache rules for Python, Ruby, Java/Kotlin, Rust, and Go toolchains
- Discover project roots automatically — no path configuration required
- Scan discovered project trees for build artifacts across all languages
- Give developers a complete picture of their toolchain footprint, not just Xcode

---

## Part 1 — Package Manager Cache Rules

Five new `ScanRule` implementations, each in `Sources/PareCore/Rules/`. All registered in `RuleCatalog` under the developer profile and `all`.

### PythonCachesRule

**Target directories:**

| Path | Contents | Risk |
|------|----------|------|
| `~/Library/Caches/pip/` | pip download cache (macOS location) | `.safe` |
| `~/Library/Caches/pypoetry/` | Poetry download cache | `.safe` |
| `~/Library/Caches/uv/` | uv download cache | `.safe` |
| `~/.pyenv/cache/` | pyenv build-time download cache | `.safe` |

**Do not touch:** `~/.pyenv/versions/` (installed Python runtimes) and any `site-packages/` directory.

Confidence: 0.95. Minimum age gate: none (caches are always reconstructible).

---

### RubyCachesRule

**Target directories:**

| Path | Contents | Risk |
|------|----------|------|
| `~/.gem/ruby/*/cache/` | RubyGems downloaded `.gem` archives | `.safe` |
| `~/.bundle/cache/` | Bundler download cache | `.safe` |
| `~/.rbenv/cache/` | rbenv build-time download cache | `.safe` |

**Do not touch:** `~/.gem/ruby/*/gems/` (installed gem source) and `~/.rbenv/versions/` (installed Ruby runtimes).

Confidence: 0.93.

---

### JavaBuildCachesRule

**Target directories:**

| Path | Contents | Risk |
|------|----------|------|
| `~/.gradle/caches/` | Gradle build + dependency cache | `.safe` |
| `~/.gradle/wrapper/dists/` | Gradle wrapper distributions (multiple versions) | `.safe` |
| `~/.m2/repository/` | Maven local repository | `.review` |
| `~/.ivy2/cache/` | Ivy/SBT dependency cache | `.safe` |

`~/.m2/repository/` is flagged `.review` because some teams publish internal artifacts to their local repo; auto-deleting them would break offline builds. Users on a standard Maven Central setup can safely delete it.

Confidence: 0.90.

---

### RustCachesRule

**Target directories:**

| Path | Contents | Risk |
|------|----------|------|
| `~/.cargo/registry/cache/` | Downloaded `.crate` archives | `.safe` |
| `~/.cargo/registry/src/` | Extracted crate source (reconstructible from cache) | `.safe` |
| `~/.cargo/git/db/` | Cloned git-sourced crates | `.safe` |
| `~/.cargo/git/checkouts/` | Checked-out git crates | `.safe` |
| `~/.rustup/downloads/` | rustup component download cache | `.safe` |

**Do not touch:** `~/.cargo/bin/` (installed binaries) and `~/.rustup/toolchains/` (installed toolchains).

Confidence: 0.95.

---

### GoCachesRule

**Target directories:**

| Path | Contents | Risk |
|------|----------|------|
| `~/Library/Caches/go-build/` | Go build cache (macOS location since Go 1.15) | `.safe` |
| `~/go/pkg/mod/cache/` | Go module download cache (zip archives + hash db) | `.safe` |

**Do not touch:** `~/go/pkg/mod/` root beyond the `cache/` subdirectory — the top-level module directories are the extracted module source used directly during builds.

Confidence: 0.95.

---

## Part 2 — Project Artifact Purge v2

### The Problem with Path-Based Scanning

The Phase 5 implementation asks users to point at their projects folder. This fails for two common cases:

1. The user keeps projects in a non-standard location (`~/Developer`, `~/workspace`, `~/code`, `~/src`, a mounted volume, etc.).
2. The user has projects scattered across multiple locations with no single root.

### Solution: Spotlight-Based Project Root Discovery

Use `NSMetadataQuery` to find "project signal files" anywhere in the user's home directory, then deduplicate to actual project roots. No configuration required.

#### ProjectRootDiscovery Actor

```swift
actor ProjectRootDiscovery {
    // Persists to ~/Library/Application Support/Pare/project-roots.json
    // Format: { confirmed: [String], excluded: [String], lastDiscoveredAt: Date }

    func discover() async -> [URL]       // Runs Spotlight query, returns candidate roots
    func confirmedRoots() -> [URL]       // User-approved roots (used by ProjectArtifactsRule)
    func confirm(_ url: URL)             // User opts in
    func exclude(_ url: URL)             // User opts out
    func addManual(_ url: URL)           // User-supplied path (folder picker)
    func removeManual(_ url: URL)
}
```

#### Spotlight Query

```swift
let query = NSMetadataQuery()
query.searchScopes = [NSMetadataQueryUserHomeScope]

// Signal files: each one reliably marks the root of a project
let signalNames = [
    ".git",            // universal — most projects use git
    "Package.swift",   // Swift Package
    "Cargo.toml",      // Rust
    "go.mod",          // Go
    "pyproject.toml",  // Python (modern)
    "setup.py",        // Python (legacy)
    "Gemfile",         // Ruby
    "pom.xml",         // Maven / Java
    "build.gradle",    // Gradle / Kotlin
]

// Deliberately excluded: package.json (appears inside node_modules),
// *.xcodeproj (Xcode auto-creates these inside DerivedData)
```

`kMDItemFSName` predicate joined with `||`. Run with a 10-second timeout; cancel and return partial results if exceeded.

#### Deduplication to Project Roots

1. For each Spotlight hit, compute the **project root**:
   - Signal is `.git/` (directory) → parent of `.git/` is the root
   - Otherwise → parent of the signal file is the root
2. Filter out paths containing excluded components:
   `["/Library/", "/System/", "node_modules", "vendor", "venv", ".venv", ".Trash", "site-packages"]`
3. Sort roots by path depth ascending (shallowest first).
4. **Submodule deduplication**: for each root R, discard any other root whose path starts with R's path — this collapses submodules and nested monorepo packages under the outermost repo.
   - Exception: if the nested root is > 3 path components deeper than R, treat it as an independent project (e.g. `~/code/client/` containing an unrelated vendored library at `~/code/client/tools/third_party/somelib/` — keep `somelib` only if it has its own `.git`).

#### Persistence & UI

Discovered roots are presented once in a new "Project Roots" card on the Scan tab (visible only if any roots were found). The user sees a list with opt-out checkboxes — the default is **all discovered roots are included**. They can:
- Uncheck individual roots to exclude them from artifact scanning
- "Add Folder…" to add a path Spotlight missed (NSOpenPanel, directory only)
- "Rescan" to re-run discovery (useful after cloning new projects)

The confirmed list is persisted; the card collapses to a compact summary after initial setup.

---

### ProjectArtifactsRule

Registered in `RuleCatalog` (developer profile + `all`). Uses `customScan`.

#### Artifact Patterns

| Directory name | Language/Tool | Category | Risk |
|---------------|---------------|----------|------|
| `node_modules/` | Node.js | Developer Package Caches | `.safe` |
| `target/` | Rust, Maven | Developer Build Artifacts | `.safe` |
| `venv/` or `.venv/` | Python | Developer Package Caches | `.safe` |
| `__pycache__/` | Python | Developer Package Caches | `.safe` |
| `.gradle/` | Gradle | Developer Build Artifacts | `.safe` |
| `.bundle/` | Ruby Bundler | Developer Package Caches | `.safe` |
| `.next/` | Next.js | Developer Build Artifacts | `.safe` |
| `.nuxt/` | Nuxt.js | Developer Build Artifacts | `.safe` |
| `.parcel-cache/` | Parcel | Developer Build Artifacts | `.safe` |
| `.turbo/` | Turborepo | Developer Build Artifacts | `.safe` |
| `.nx/` | Nx | Developer Build Artifacts | `.safe` |
| `dist/` | Various | Developer Build Artifacts | `.review` |
| `build/` | Various | Developer Build Artifacts | `.review` |

`dist/` and `build/` are `.review` because some projects commit these as part of a release process. Everything else is reliably reconstructible.

#### Algorithm

```
customScan(rootURL):
  for each confirmedRoot in ProjectRootDiscovery.confirmedRoots():
    walk(rootURL: confirmedRoot, maxDepth: 8):
      if entry.name in ARTIFACT_PATTERNS:
        if effectiveAgeDate(entry) < 7 days ago: skip   // age gate
        emit ScanFinding(path: entry, ...)
        skipDescendants()   // don't recurse into artifacts
      if entry.name starts with ".": skipDescendants()  // skip hidden dirs except known artifacts
```

The `skipDescendants()` call after finding an artifact is critical — it avoids double-counting `node_modules` inside `node_modules`, and keeps the scan fast.

---

## Architecture

```
Sources/PareCore/
  Rules/
    PythonCachesRule.swift
    RubyCachesRule.swift
    JavaBuildCachesRule.swift
    RustCachesRule.swift
    GoCachesRule.swift
    ProjectArtifactsRule.swift      # customScan; uses ProjectRootDiscovery
  ProjectDiscovery/
    ProjectRootDiscovery.swift      # actor; Spotlight query + persistence
    ProjectRootsStore.swift         # Codable model for project-roots.json
```

---

## Test Plan

| Test | What it verifies |
|------|-----------------|
| `PythonCachesRuleTests` — target paths exist | Rule emits findings for pip, poetry, uv dirs |
| `PythonCachesRuleTests` — pyenv versions excluded | `~/.pyenv/versions/` not emitted |
| `RustCachesRuleTests` — cargo bin excluded | `~/.cargo/bin/` not emitted |
| `JavaBuildCachesRuleTests` — m2 risk level | `~/.m2/repository/` emits `.review`, not `.safe` |
| `ProjectRootDiscoveryTests` — dedup | Nested `.git` at depth 2 drops inner root |
| `ProjectRootDiscoveryTests` — deep nested | Nested `.git` at depth > 3 keeps both roots |
| `ProjectRootDiscoveryTests` — system path excluded | `/Library/.../.git` not returned |
| `ProjectArtifactsRuleTests` — age gate | Artifact < 7 days old not emitted |
| `ProjectArtifactsRuleTests` — no double-count | `node_modules/` inside `node_modules/` not emitted twice |
| `ProjectArtifactsRuleTests` — dist is review | `dist/` emits `.review` not `.safe` |

---

## uv Cache Discovery (Phase A — report-only)

Modern Homebrew `uv` defaults to the XDG cache layout (`~/.cache/uv`), not
`~/Library/Caches/uv`, so the original `PythonCachesRule` target missed real
multi-GB caches. `UvCacheRule` now owns uv end-to-end:

**Discovery roots (discover broadly):** resolved by `CacheRootResolver`, in
explanatory-confidence order, canonicalized (standardized + symlink-resolved)
and deduplicated to one finding per physical directory:

1. `uv cache dir` output (`ToolCommandRunner`: short timeout, null stdin,
   non-fatal, skipped when uv is not installed; PATH + Homebrew locations,
   never sources shell files) — labelled `uv CLI`
2. Absolute `UV_CACHE_DIR` — labelled `environment`
3. XDG root — `XDG_CACHE_HOME` (absolute values only; relative ignored per the
   XDG spec) or `~/.cache` — labelled `XDG`
4. Foundation `.cachesDirectory` — labelled `macOS cache root`

Dangerous roots are rejected: `/`, any direct child of `/`, bare home, bare
`~/Library`, and well-known system prefixes. Tool output is validated
(single-line, absolute, no NUL, bounded length) before use.

**Cleanup (clean narrowly):** findings are `.advanced` — `CleanupEngine`
hard-blocks Trash deletion because uv requires its own cache commands
(`uv cache prune` / `uv cache clean`) to respect locks and in-use state.
`/.cache/uv` is deliberately absent from every Trash-cleanup marker list;
exact-boundary checks use `ScanPolicy.isEqualToOrDescendant(candidate:root:)`
so `~/.cache/uvicorn` / `~/.cache/uv-backup` can never match. The native
Maintenance action lands in Phase B of the uv cache plan.

`ToolCacheDescriptor` records relative child names, native discovery commands,
and cleanup posture for uv, pip, Poetry, and pyenv; only uv is wired to a rule
in Phase A.
