# Plan: Pare — machine-wide storage inventory and persona-aware classification

**Status:** Draft architecture plan (do not implement until approved)
**Date:** 2026-07-25
**Owner:** Pare / PareCore
**First vertical slice:** [`2026-07-25-pare-uv-cache-scan-plan.md`](./2026-07-25-pare-uv-cache-scan-plan.md)

---

## 1. Problem

Pare currently discovers reclaimable storage through many rules with hard-coded target directories. That works for known layouts, but it does not scale across:

- different macOS and tool versions;
- customized homes, XDG roots, package stores, and external volumes;
- developers using different languages, IDEs, build systems, and container tools;
- designers using Adobe, Figma, Sketch, Affinity, or asset pipelines;
- filmmakers using Final Cut Pro, Premiere, After Effects, or DaVinci Resolve;
- general users with browsers, downloads, installers, backups, productivity apps, and large personal files.

The existing Disk Analyzer is not a machine inventory:

- it scans one manually selected directory;
- it skips hidden entries, where many developer caches live;
- it stops building detail after depth four;
- it keeps only the largest 50 children before calculating the displayed parent total;
- it has no semantic classification or cleanup strategy;
- it exposes direct Trash without the cleanup engine's full policy model.

The existing rule scanner also is not a machine inventory:

- every rule supplies its own roots;
- overlapping trees may be traversed repeatedly;
- the normal traversal skips hidden entries;
- personas are static rule bundles;
- the app runs the union of all profiles rather than detecting the machine's actual ecosystems.

### Fundamental constraint

There is no reliable universal heuristic that can look at an arbitrary directory and prove it is safe to delete.

Names such as `cache`, `build`, `render`, `proxy`, `backup`, `.venv`, or `DerivedData` are useful evidence, but their meaning depends on the owning application and surrounding structure. A machine-wide scanner can be generic; safe cleanup must remain evidence-based and domain-aware.

---

## 2. Goals

1. Inventory relevant storage on the machine once.
2. Reuse that inventory for all personas and tools.
3. Detect installed applications, toolchains, project ecosystems, and media workflows automatically.
4. Find large or unusual storage even when Pare has no specific rule for it.
5. Move ecosystem knowledge from Swift path lists into validated descriptors where practical.
6. Keep discovery, classification, and cleanup authorization separate.
7. Incrementally update the inventory instead of rewalking millions of files for every scan.
8. Preserve Pare's local-first privacy and safety model.

### Non-goals

- Reading arbitrary file contents during the breadth scan.
- Treating all large files or cache-looking directories as reclaimable.
- Scanning other macOS users' private homes without their authorization.
- Following network volumes, disk images, Time Machine backups, or system volumes by default.
- Replacing app-native maintenance commands with filesystem deletion.

---

## 3. Product model

```text
Volumes and approved roots
        ↓
Machine inventory
        ↓
Evidence extraction
        ↓
Artifact classification
        ↓
Ownership + ecosystem detection
        ↓
Persona views
        ↓
Cleanup strategy and policy
```

### One inventory, many views

Personas should not trigger independent filesystem walks. They are overlays on the same inventory:

| View | Prioritizes |
|------|-------------|
| General | app caches, browsers, downloads, installers, duplicates, backups, large old files |
| Developer | package stores, project dependencies, build output, simulators, containers, IDE caches |
| Designer | previews, media caches, exports, temporary renders, duplicate assets |
| Filmmaker | render files, proxies, optimized media, analysis caches, backups, project bundles |
| Advanced | unknown hotspots, external roots, native maintenance, system-managed storage |

A user may match several views at once. Pare should show detected workflows such as “Swift + Node developer, Figma user, Final Cut Pro installed” rather than asking for one exclusive profile.

---

## 4. Machine scan scope

### 4.1 Volume discovery

Use Foundation volume APIs to enumerate mounted volumes and inspect resource keys such as volume identity, locality, read-only state, capacity, removability, and filesystem type where available.

Default scope:

| Scope | Default |
|-------|---------|
| Current user's home and user Library | Scan |
| `/Applications`, `~/Applications` | Inventory applications, not app bundle contents by default |
| `/Library/Caches`, `/Users/Shared` | Scan when readable and relevant |
| Local external volumes | Ask/opt in |
| Network volumes | Off |
| Time Machine, Recovery, Preboot, VM, disk-image mounts | Exclude |
| macOS sealed System volume | Exclude |
| Other users' homes | Exclude unless explicitly authorized |

Avoid scanning `/` as a naive recursive root. macOS firmlinks, mounted volumes, and data/system volume presentation can cause duplicate traversal and misleading totals.

### 4.2 Root registry

Build an approved-root registry from:

- current home and Foundation search-path APIs;
- local data-volume locations Pare supports;
- user-selected folders stored as security-scoped bookmarks if sandboxing is introduced;
- project roots discovered by manifests/Spotlight;
- descriptor-provided roots;
- tool-native queries;
- opted-in external volumes.

Each root records its provenance and policy:

```text
url
volumeID
source: system | user | spotlight | descriptor | tool
scanDepth
followPackages
includeHidden
cleanupAuthority
```

Canonicalize and deduplicate roots. Never follow symbolic links outside an approved root.

---

## 5. Inventory engine

### 5.1 Replace repeated rule walks with a single core index

Add a PareCore inventory service backed by a local SQLite database.

Suggested directory record:

```text
canonicalPath
parentPath
volumeID
resourceIdentifier
allocatedBytes
logicalBytes
directFileCount
descendantFileCount
createdAt
modifiedAt
lastInventoryAt
flags: hidden, package, symlink, sparse, purgeable, unreadable
contentHints
```

Store file-level records only for interesting or large files. Do not persist every ordinary filename unless needed for drill-down; this reduces database size and privacy exposure.

### 5.2 Two-pass scan

**Pass 1 — breadth inventory**

- Walk approved roots once.
- Include hidden entries.
- Do not follow symlinks.
- Treat mounted-volume boundaries explicitly.
- Collect allocated/logical size, dates, resource identifiers, and directory structure.
- Aggregate directory sizes in the same walk.
- Detect lightweight evidence: manifest names, bundle/package boundaries, `CACHEDIR.TAG`, directory names, file extensions, and large-file thresholds.
- Avoid opening ordinary file contents.

**Pass 2 — targeted semantic inspection**

Only inspect candidates identified in Pass 1:

- parse small project manifests and lockfiles;
- inspect app bundle metadata and bundle identifiers;
- validate cache tags and known structural signatures;
- ask installed tools for cache/store locations;
- inspect media-library bundle structure;
- detect duplicate versions or architecture-specific payloads;
- optionally hash duplicate-file candidates after grouping by size.

This makes the breadth scan generic while reserving expensive or sensitive work for high-value candidates.

### 5.3 Size correctness

- Use allocated bytes for disk-pressure reporting.
- Retain logical bytes for sparse-file explanation.
- Use volume free-space APIs as the source of truth for total capacity.
- Avoid double-counting hard links by resource identifier where feasible.
- Document that APFS clones/shared extents can make per-path attribution approximate even when volume totals are correct.
- Do not discard small children before computing a parent total; apply UI top-N limits only after aggregation.

---

## 6. Incremental updates

The first machine inventory may be expensive. Later scans should be incremental:

1. Start an FSEvents stream before or during the initial snapshot.
2. Persist the last event ID per volume.
3. Mark changed directory subtrees dirty.
4. Rescan only dirty subtrees.
5. Fall back to a full root rescan after dropped events, volume identity changes, or incompatible index versions.

FSEvents is directory-granular; it tells Pare where something changed, not exactly what changed. The inventory snapshot remains necessary.

Also support pause/cancel, I/O budgets, battery/thermal awareness, per-root progress, permission-denied accounting, cold/warm telemetry, and schema/catalog version invalidation.

---

## 7. Evidence and classification

### 7.1 Artifact classes

Classify storage independently of persona:

| Artifact class | Examples |
|----------------|----------|
| Download/cache | package downloads, HTTP cache, thumbnails |
| Derived/build | object files, compiled output, indexes, renders |
| Dependency environment | `node_modules`, `.venv`, vendor trees |
| Shared package store | pnpm, Cargo registry, Maven, Gradle, NuGet |
| Log/diagnostic | app logs, crash reports |
| Temporary/runtime | temporary exports, transient workspaces |
| Installer/archive | DMG, PKG, ZIP, XIP, ISO |
| Duplicate/superseded | old app/tool versions, duplicate files |
| Backup/recovery | device backup, autosave, application backup |
| Application state | sessions, settings, credentials, databases |
| User content | source, documents, media masters, project files |
| Unknown hotspot | large storage without sufficient evidence |

Persona answers “who cares about this?” Artifact class answers “what is it?” Cleanup strategy answers “what may Pare safely do?”

### 7.2 Evidence types

Combine several independent signals:

- location: known cache/data/support root;
- structure: neighboring files and directory shape;
- manifest: `package.json`, `pyproject.toml`, `Cargo.toml`, project bundles;
- ownership: installed app bundle ID or executable;
- tool query: native cache/store command;
- tag: valid `CACHEDIR.TAG`;
- activity: modification and recent use;
- process state: owning app/tool currently running;
- reconstructibility: lockfile or source manifest exists;
- version relationship: newer sibling installed;
- content type: UTI, extension, package/bundle metadata;
- user assertion: explicitly added root or classification override.

One path-name match should never be enough for automatic cleanup outside a platform-defined cache root.

### 7.3 Confidence and cleanup strategy

Suggested result model:

```text
classification
owner/tool
personaTags[]
evidence[]
confidence
risk
cleanupStrategy:
  trash
  nativeCommand
  reportOnly
  never
```

| Evidence | Default behavior |
|----------|------------------|
| Exact known structure + reconstructibility + inactive owner | Safe or native cleanup |
| Known cache root but uncertain owner | Review |
| Valid cache tag only | Review |
| Name/extension heuristic only | Report only |
| Application state, user content, unknown DB/bundle | Never automatic |

---

## 8. Ecosystem descriptor catalog

Move repeatable ecosystem knowledge into validated descriptors rather than scattering full paths across Swift rules.

Illustrative descriptor:

```json
{
  "id": "node",
  "personaTags": ["developer", "javascript"],
  "detectors": {
    "executables": ["node", "npm", "pnpm", "yarn"],
    "projectManifests": ["package.json"],
    "lockfiles": ["package-lock.json", "pnpm-lock.yaml", "yarn.lock"]
  },
  "artifacts": [{
    "kind": "project-dependency",
    "relativeNames": ["node_modules"],
    "requiresAncestorManifest": "package.json",
    "cleanup": "trash",
    "risk": "safe"
  }]
}
```

Descriptor capabilities:

- installed app bundle IDs and executables;
- project manifests and lockfiles;
- root resolvers and relative directory patterns;
- structural predicates;
- artifact class and persona tags;
- native discovery/cleanup commands;
- protected siblings and never-delete patterns;
- risk, confidence, minimum age, and running-process behavior;
- documentation and tests.

Use typed decoding and schema validation. Complex ecosystems such as Docker, Xcode simulators, browser profiles, and media-library bundles can keep specialized Swift classifiers behind the same descriptor/result interfaces.

---

## 9. Developer ecosystem coverage

Developer should be a family of detected ecosystems, not one profile:

| Ecosystem | Detection evidence | Candidate derived/reconstructible storage |
|-----------|--------------------|-------------------------------------------|
| Apple/Swift | `.xcodeproj`, `.xcworkspace`, `Package.swift`, Xcode bundle | DerivedData, archives, simulator caches, SwiftPM cache |
| JavaScript/TypeScript | `package.json` + lockfile | `node_modules`, npm/npx, Yarn, pnpm stores, framework build output |
| Python | `pyproject.toml`, requirements/lockfiles, Python tools | pip/uv/Poetry caches, `.venv`, tox/nox/mypy/pytest/ruff caches |
| Rust | `Cargo.toml`, `Cargo.lock` | `target`, registry/git cache, toolchain downloads |
| Go | `go.mod`, `go.work` | build cache, module download cache, project binaries |
| JVM/Android | Gradle/Maven files, Android Studio/JetBrains | Gradle, Maven, Kotlin, Android build/intermediates, emulator state |
| Ruby | `Gemfile`, gemspec | Bundler and gem caches, project vendor bundles |
| PHP | `composer.json`, lockfile | Composer cache, project vendor tree |
| .NET | solution/project files, NuGet config | `bin`, `obj`, NuGet packages/cache |
| C/C++ | CMake, Meson, Bazel, Make/Ninja files | build trees, Bazel cache/output, ccache |
| Web frameworks | framework config + language manifest | `.next`, Nuxt, Vite, Parcel, Turbo, coverage output |
| Containers | Docker/Podman/Colima apps and sockets | native prune candidates; never raw filesystem deletion |
| Editors/IDEs | bundle IDs and extension layouts | safe caches, duplicate extensions, indexes, protected settings |
| AI developer tools | app/CLI detection and catalog | model/tool caches, logs, indexes; credentials protected |

Project artifacts require structural context:

- `target` is safe only when tied to a Rust/Gradle build, not merely because of its name.
- `.venv` is reconstructible only when a Python manifest/lockfile exists and the user accepts environment recreation.
- `vendor` can contain dependencies or hand-maintained source; require ecosystem-specific evidence.
- build output on an external volume may be deliberately retained; default to review until the root is approved.

---

## 10. Other persona classifiers

### General user

- platform/app caches;
- browser caches separated from cookies/history/storage;
- Downloads installers and archives;
- old large files;
- iOS/iPadOS backups;
- duplicate applications and superseded versions;
- unknown large folders as report-only.

### Designer

- detect Adobe, Figma, Sketch, Affinity, Blender, and font/design tools;
- classify previews, thumbnails, generated exports, and temporary renders;
- never conflate source assets, linked media, fonts, plugins, or cloud-offline content with caches.

### Filmmaker and motion graphics

- Final Cut libraries: render files, proxies, optimized media, analysis files, backups;
- Premiere/After Effects: media cache, peak files, previews, conformed media, autosaves;
- DaVinci Resolve: cache clips, optimized media, proxies, gallery stills, project databases;
- distinguish camera originals and project libraries from regenerated media;
- prefer application-native cleanup where available;
- show volume placement because media caches often live on external disks.

Future detected overlays may cover photographers, audio producers, gamers, and data/ML engineers. These add classification and presentation, not independent full-disk walks.

---

## 11. Hotspot discovery without a classifier

The inventory remains useful with zero ecosystem knowledge:

- largest directories by allocated size;
- largest individual files;
- fastest-growing directories between snapshots;
- old, large, untouched files;
- large hidden directories;
- duplicate-size candidates;
- storage by volume and top-level owner;
- unclassified hotspots.

Unknown hotspots are valuable findings but are not reclaimable totals. The UI should say “inspect,” not “clean.”

Spotlight can accelerate candidate discovery for indexed content types and locations, but it is not a complete inventory: users can exclude locations and many hidden/system directories are not indexed. Use Spotlight as evidence/candidate generation, never as the sole size source.

---

## 12. Safety and privacy

- All indexing and classification remain local.
- Do not upload paths, manifests, or filenames.
- Avoid reading source/document/media contents during normal classification.
- Store only metadata needed for the feature; offer index reset.
- Respect exclusions before persistence and classification.
- Never follow symlinks blindly or delete from an unknown hotspot.
- Native-managed stores use native cleanup.
- Check running owners before destructive actions where practical.
- Revalidate path identity, evidence, and cleanup policy immediately before cleanup.
- Preserve Trash/undo for filesystem cleanup; clearly label native commands that cannot be undone.

Full Disk Access improves coverage but does not authorize other users' private data or unsafe cleanup.

---

## 13. Proposed components

| Component | Responsibility |
|-----------|----------------|
| `VolumeInventory` | Enumerate and classify mounted volumes |
| `ScanRootRegistry` | Approved roots, provenance, scope, dedupe |
| `StorageInventoryStore` | SQLite snapshot and directory aggregates |
| `MachineInventoryScanner` | One-pass breadth traversal |
| `InventoryUpdateMonitor` | FSEvents dirty-subtree tracking |
| `EvidenceExtractor` | Lightweight structural signals |
| `ArtifactClassifier` | Class/confidence/risk/strategy result |
| `EcosystemCatalog` | Validated descriptors |
| Specialized classifiers | Docker, Xcode, browsers, media bundles |
| `PersonaDetector` | Scores detected workflows from apps/tools/projects |
| `HotspotAnalyzer` | Largest, oldest, fastest-growing, unknown |
| `CleanupPlanner` | Exact path/native/report-only execution plans |

The current `ScanRule` API can remain during migration. New classifiers should consume inventory nodes rather than starting their own filesystem traversal.

---

## 14. Migration phases

| Phase | Scope |
|-------|-------|
| **0 — Measurements** | Benchmark current Disk Analyzer/rules; define correctness and scan-time budgets |
| **1 — Inventory core** | User-home inventory, hidden entries, accurate aggregation, SQLite, cancellation/progress |
| **2 — Hotspot UI** | Largest/oldest/hidden/unknown views with no cleanup authorization |
| **3 — Ecosystem descriptors** | App/tool/project detection and developer language packs |
| **4 — uv vertical slice** | Portable discovery, report-only classification, native cleanup |
| **5 — Rule migration** | Convert package managers, IDEs, browsers, designer, and video rules to inventory consumers |
| **6 — Incremental index** | FSEvents, dirty subtrees, growth history |
| **7 — Volumes and user roots** | External volumes, security-scoped roots, per-volume views |
| **8 — Advanced classifiers** | Duplicates, stale versions, media bundles, native app maintenance |

Do not attempt a big-bang rewrite of all existing rules.

---

## 15. Verification

Create synthetic homes/volumes representing a general user, several developer stacks, designer, filmmaker with external media, mixed persona, custom roots, permission failures, and symlink escapes.

Assertions:

- one physical subtree is counted once;
- parent totals include all children even when UI shows top N;
- hidden caches are included;
- packages, symlinks, mounts, sparse files, and hard links behave correctly;
- unknown hotspots never inflate reclaimable totals;
- project structure prevents false-positive `target`, `vendor`, `build`, and `.venv` classification;
- native-managed stores never receive filesystem Trash strategies;
- descriptor/catalog changes are versioned and testable.

Measure cold inventory time, warm incremental time, memory, database size, cancellation latency, energy impact, and permission coverage on small SSDs, multi-million-file developer homes, and external media disks.

---

## 16. Decisions recommended

1. Build **one inventory with multiple overlays**, not one scanner per persona.
2. Make persona detection automatic and non-exclusive.
3. Start with the current user's data; external volumes opt in.
4. Keep unknown hotspots visible but non-cleanable.
5. Use descriptors for repeated ecosystem patterns and specialized code for complex stores.
6. Make uv the first native-managed vertical slice, not the architecture itself.
7. Treat a persistent incremental inventory as the long-term performance model.

---

## 17. References

- Apple file-system guidance: https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/
- Apple allocated-size resource key: https://developer.apple.com/documentation/foundation/urlresourcekey/totalfileallocatedsizekey
- Apple Spotlight metadata scopes: https://developer.apple.com/documentation/foundation/nsmetadataqueryuserhomescope
- Apple FSEvents snapshot/update guidance: https://developer.apple.com/library/archive/documentation/Darwin/Conceptual/FSEvents_ProgGuide/UsingtheFSEventsFramework/UsingtheFSEventsFramework.html
- XDG Base Directory specification: https://specifications.freedesktop.org/basedir/
- Cache Directory Tagging specification: https://bford.info/cachedir/
- uv cache safety and location: https://docs.astral.sh/uv/concepts/cache/
