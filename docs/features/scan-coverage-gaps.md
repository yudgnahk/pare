# Scan Coverage Gaps

Known defects in scan coverage and correctness, with the location of each. Phase 11 in
[`roadmap.md`](../roadmap.md) tracks the work.

## Baseline

Two machines were audited against a manual `du`/`find` sweep:

| Date | Machine | Manual sweep | Pare reported |
|------|---------|--------------|---------------|
| 2026-09-21 | Intel, 233 GB volume, 9.5 GB free, Homebrew builds from source | ~50–60 GB reclaimable | 22.7 GB (≈20.9 GB after removing confirmed double-counts) |
| 2026-09-23 | Apple Silicon, 8.9 GiB free | — | see C14 |

The 2026-09-21 figure came from `pare-cli --profile developer`, not the app's
`RuleCatalog.all`. Re-measure with the full catalog before using it as the before-number
for Phase 11.

## Correctness

### C1 — Findings are not deduplicated across rules

`BrowserReviewDataRule.swift:51` (`Default/IndexedDB`) and
`BrowserExtendedArtifactsRule.swift:80` (`IndexedDB`) resolve to the same path for
Chromium profiles. `ScanRunner` deduplicates nothing at path level, so both findings are
kept and both are counted.

Confirmed 2026-09-21: `…/Chrome/Default/IndexedDB` at 863.5 MB was emitted by both rules,
so Browser Caches reported 1.73 GB for 863.5 MB of real data.

Rules are also free to emit a folder and, separately, files inside it. Nothing collapses
that overlap either. Confirmed pair: a JetBrains Copilot plugin's
`copilot-agent/native/linux-x64` (folder, `.safe`, 86.9 MB) and
`native/linux-x64/copilot-language-server` (file, `.review`, 86.9 MB) — one 83 MB binary
counted twice. The same shape was reported for `linux-arm64`, `darwin-x64`, `darwin-arm64`
and `win32-x64`, inflating the JetBrains rollup (4.74 GB). `darwin-x64` is the native
platform on that Intel machine, so `WrongPlatformBinariesRule` should not have emitted it:
identify which rules produced each half of those pairs before fixing.

Fix: dedupe by `standardizedFileURL.path` in `ScanRunner` before aggregation, keeping the
highest risk level of the collapsed set (`AIToolCachesRule` already does this intra-rule),
then drop any finding that is a descendant of another finding's path. Regression test: the
sum of finding sizes never exceeds the allocated size of the union of their paths — this
catches both shapes.

Every total the app displays is affected. This blocks meaningful measurement of any other
gap, so it is fixed first.

## Project artifacts

### C2 — `.build` and other hidden artifact directories are unrecognised

`ScanPolicy.projectLocalArtifactDirectoryNames` (`ScanPolicy+Markers.swift:358`) lists
`target`, `build`, `dist`, `.next`, `.nuxt`, `.turbo`, `.nx`, `.gradle` and the Python
tool caches, but not `.build`.

`ProjectArtifactsRule.walk` skips any hidden directory whose name is not in that set, so
SwiftPM build output is never seen — including Pare's own. Also absent: `.swiftpm`,
`.dart_tool`, `.angular`, `.svelte-kit`, `.vite`, `.expo`, `.serverless`, `.terraform`.

### C3 — Spotlight discovery uses signals that cannot match

`SpotlightQueryRunner.signalNames` searches for `.git`, `Package.swift`, `Cargo.toml`,
`go.mod`, `pyproject.toml`, `setup.py`, `Gemfile`, `pom.xml`, `build.gradle`.

Two problems:

- `.git` is a hidden directory. Spotlight does not index hidden entries, so this signal
  returns nothing and contributes only the appearance of coverage.
- `package.json` and `pubspec.yaml` are missing. Node, Next.js and Flutter projects have
  no remaining signal, so their roots are never discovered and their artifacts never scanned.

`Package.resolved` and `composer.json` are worth adding for the same reason.

### C4 — Dependency caches are accepted as project roots

`ScanPolicy.projectDiscoveryExcludedPathComponents` (`ScanPolicy+Markers.swift:136`)
excludes `/vendor/` and `/node_modules/` but not `/go/pkg/mod/`, `/.pub-cache/` or
`/.cargo/registry/`.

Every module in the Go module cache carries a `go.mod`, so each one is discovered as a
project root. These trees are already covered by `GoCachesRule`, which makes this both
noise in the root store and a double-count risk once C1 is fixed.

Roots already persisted to `project-roots.json` need pruning when the exclusion lands.

### C5 — Discovery runs once per install

`ProjectRootDiscovery.discoverIfNeeded()` returns early on `lastDiscoveredAt != nil`.
Spotlight therefore runs exactly once and never again, so projects created after the
first scan are never discovered. There is no TTL and no user-facing refresh.

Observed 2026-09-21: the root store was dated 2026-07-29 with 498 roots. A Tauri project
whose `.git` was created 2026-09-05 was invisible, hiding a 6.3 GB `src-tauri/target`.

## Rule breadth

### C6 — Homebrew coverage stops at the user cache

`HomebrewCacheRule` targets `~/Library/Caches/Homebrew` only. Two reclaimable trees under
the Homebrew prefix are unscanned:

- `Caskroom/<cask>/<version>` — superseded cask versions accumulate beside the linked one.
- `Library/Taps` — git clones of taps; removable but a re-clone rather than a rebuild,
  so `.review` rather than `.safe`.

- `Cellar/<formula>/<old-version>` — superseded kegs. 4.4 GB on the 2026-09-21 Intel
  machine. `BrewInventory` already knows both Cellar roots and the Homebrew Manager tab
  shows them, but none of it reaches the scan total.

The prefix must come from `BrewRunner.homebrewPrefix()`; Intel installs use `/usr/local`.

Kegs and cask versions must not go to the Trash through `CleanupEngine` — Homebrew's own
bookkeeping would be left pointing at them. Surface `brew cleanup --dry-run` output as
findings so they count in the headline number, and reclaim through a `brew cleanup`
Maintenance action.

The `HomebrewCacheRule` figure itself is correct: 10.1 GB matched `du` exactly on the Intel
machine. Tier-3 (build-from-source) installs also leave `go_cache` + `go_mod_cache` inside
it (6.5 GB there), which deserves its own sub-attribution.

### C7 — No rule discovers large files

`ScanPolicy.largeFileThresholdBytes` (50 MB, `ScanPolicy.swift:15`) and `isLargeFile` are
used only to filter findings that already exist (`ScanReportPresenter.swift:31`,
`ScanDashboardItems.swift:94`, the CLI summary). No rule surfaces large stale files in
`~/Downloads`, `~/Desktop` or `~/Documents`.

`InstallerFileRule` matches only `dmg`/`pkg`/`iso`/`xip` and installer zips. On the
2026-09-21 machine it found 5.8 MB in `~/Downloads` while a 3.3 GB project zip and a
3.8 GB folder of encrypted database backups (`.tgz.gpg`, `.rdb.gpg`) went unreported.
`~/Library/ScreenRecordings` (1.0 GB, one 523 MB `.mov`) is likewise uncovered.

50 MB is a display threshold, not a discovery one — as a rule gate it would flood the
report. The rule needs its own threshold, default 500 MB.

### C8 — Log coverage is limited to `~/Library/Logs`

`LogsAndCrashReportsRule` scans the standard log directory. CLI tools that run as user
daemons write elsewhere — `~/.paseo/launchd.{stdout,stderr}.log`, `~/.codex/*.sqlite`
log databases — and are not covered.

### C9 — Stale versions are only detected under `/Applications`

`StaleAppVersionRule` handles app bundles and `JetBrainsStaleVersionRule` handles IDE
support directories. The same keep-newest-discard-rest layout appears under
`~/.local/share/<tool>/versions/` for several AI CLIs, with no rule covering it.

The layout is not uniform, so "keep the newest directory" is the wrong test. Observed
2026-09-23:

| Tool | Layout | Superseded |
|------|--------|-----------|
| Devin | `~/.local/share/devin/cli/_versions/<v>/`, a `current` symlink, a `_download/` staging dir | 4 versions + `_download`, 918 MiB |
| cursor-agent | `~/.local/share/cursor-agent/versions/<date>-<sha>/`; a superseded one was renamed to a dot-prefixed `.2026.09.10-fd3934a` | 2 of 3 |
| ACLI | `~/.local/share/acli/<v>-stable/`; binary comes from Homebrew at a newer version | `1.3.15-stable` while Homebrew ships 1.3.36 |

The live version must be resolved from the `current` symlink or from the binary on `PATH`,
not from mtime or version sort. Hidden version directories must be included, not skipped.

### C10 — Dependency trees of inactive projects are never reclaimable

`node_modules` and `.venv` are excluded outright (see Deliberately out of scope). That is
right for a project in use and wrong for one untouched for months: the tree is fully
reinstallable from the lockfile and is the largest thing left in the project.

The 2026-09-21 Intel machine had 8.5 GB of `node_modules` across 40+ project trees, most in
projects untouched for years.

Measured 2026-09-23 (last commit in brackets): `opencode/node_modules` 2.27 GiB (07-31),
`tts/vietnamese-tts-lab/.venv` 2.34 GiB and `tts/.venv` 1.37 GiB (no commits in 30 days),
`worldcup-magazine/node_modules` 0.56 GiB (07-16), `bounty-resolvers/node_modules`
0.47 GiB (08-17). Stale SwiftPM `.build` beside them — `agentbuddy` 0.70 GiB (06-06),
`starterpal` 0.62 GiB (07-09) — is C2.

Needs an inactivity signal per project root: last commit date, newest mtime outside
artifact and dependency directories, or both. A dependency tree becomes `.review` only when
the root is inactive **and** a lockfile or manifest exists to rebuild it
(`package-lock.json`, `pnpm-lock.yaml`, `uv.lock`, `requirements*.txt`, `pyproject.toml`).
Uncommitted source changes do not block this — they live outside the dependency tree — but
should be shown on the finding, along with the lockfile, so the user knows one `install`
restores it. The inactivity gate is user-configurable, default 90 days.

### C11 — Downloaded ML models have no rule

Model weights sit in tool-specific locations with no cache semantics:
`~/Library/Application Support/tts/` (Coqui XTTS, 1.75 GiB), `~/.cache/huggingface/hub`
(1.55 GiB written in the 10 days to 2026-09-23), `~/.rembg` (977 MiB). All are
redownloadable, but a model is only worth deleting once its consumer is gone, and the
consumer is a project, not an app — the XTTS model is loaded by a `TTS(model_name=...)`
call in a script in `~/Projects`.

Report as `.review` with the model name and size. Attribution to a consuming project is the
useful part; without it the user cannot decide.

### C12 — Abandoned downloads and leftover installer payloads

Three shapes, none covered:

- **Interrupted download beside a completed one.** `~/.paseo/models/local-speech/.downloads/`
  holds `<model>.tar.bz2` (482 MB) and `<model>.tar.bz2.tmp-<n>` (448 MB); the model is
  already extracted beside it. Both are dead weight.
- **Updater payloads for a superseded version.** Open Design 0.24 is installed but
  `Application Support/Open Design/namespaces/release-stable/updates/releases/0.21.0-mac-arm64-*`
  is kept. `~/Library/Caches/@getpaseodesktop-updater` regrows 0.34 GB between cleans.
- **Installer archives outside `~/Downloads`.** `actions-runner-osx-arm64-2.334.0.tar.gz`
  (121 MiB) inside the runner directory. `InstallerFileRule` only knows
  `dmg`/`pkg`/`iso`/`xip` and installer zips, not `.tar.gz`.

A `*.tmp-*` / `*.partial` / `*.download` file older than a day with no open handle is
`.safe`. Updater payloads need the installed version from the app bundle's `Info.plist`.

### C13 — App bundles outside `/Applications` are invisible

`Project Zomboid.app` — 9.9 GiB, the single largest reclaimable item on the machine — sits
in `~/Documents/Project Zomboid/`. `StaleAppVersionRule` and the App Manager only look in
`/Applications`, and C7's large-file rule, once built, works per file, so a `.app`
directory of thousands of files would still slip through.

Needs a bundle-aware walk of `~/Documents`, `~/Downloads` and `~/Desktop` reporting any
`.app` over a size threshold with its last-opened date (`kMDItemLastUsedDate`). `.review`
only — it is an installed program, not a cache.

### C14 — Pare reports a snapshot, not a trend

This is the gap that made a manual audit necessary. Free space fell from 24.85 GB
(2026-09-13) to 8.9 GiB (2026-09-23) and nothing said where it went. The same day, two
App A clean runs 7 hours apart each reclaimed ~4.2 GB. The Homebrew cache (1.3–1.5 GB)
and Chrome cache (1.2–1.5 GB) had fully regrown between them.

What answered "what grew" was summing allocated blocks of files modified since the last
known-good date, grouped by path prefix — `find -newermt` + `stat -f %b`. Pare could
store a per-directory size index at each scan and report:

- the delta since the previous scan, per top-level directory and per rule;
- a refill rate for each cache rule, so a cache that regrows in hours is labelled as
  working set rather than offered for cleanup again;
- a free-space threshold alert from a scheduled background scan, instead of waiting for
  the user to open the app.

The ~34 GB unreadable without Full Disk Access should appear as its own
"unaccounted = volume used − scanned" row so a growth there is visible even when it
cannot be attributed.

### C15 — The Docker VM disk is invisible

`Docker.raw` was the single largest file on the 2026-09-21 machine: 28 GB allocated, 60 GB
apparent. `DockerStorageRule` reports only `Data/log` (166.9 MB). Phase D was right to stop
*deleting* it but removed *visibility* too — which is what `.advanced` (detect-only)
exists for. `CHANGELOG.md` still claims "VM disk image visibility" and uses the Docker VM
disk as the example of an Advanced finding, so docs and behaviour are out of sync.

Re-add a detect-only `.advanced` finding for `…/vms/0/data/Docker.raw`:

- allocated size, with apparent size shown beside it and the finding labelled sparse —
  PR #14 showed a fake multi-TB "reclaimable" by using logical size;
- excluded from reclaimable totals, as `.advanced` findings already are;
- never cleanable — `ScanPolicy.isDockerNeverDeletePath` and the `CleanupEngine` block
  stay exactly as they are;
- the existing prune / Phase 10 guidance attached.

The same allocated-vs-apparent rule applies to any sparse finding (VM disks in C16).

### C16 — Local VM and Kubernetes disks have no rule

`~/.minikube` held 11 GB on the 2026-09-21 machine: an 11 GB
`machines/minikube/minikube.rawdisk` plus a 526 MB preloaded-images tarball for
Kubernetes v1.18.3 (2020). Nothing reports it.

Cover `~/.minikube`, `~/.lima`, `~/.colima`, `~/.vagrant.d`, `~/.local/share/containers`
(Podman) and Parallels/VMware/UTM/VirtualBox images. VM disks are `.advanced` (detect-only,
same treatment as C15); preloaded image tarballs for a Kubernetes version no cluster uses
are `.review`. Flag by last-used date — a cluster untouched for 90+ days is the signal.

### C17 — Superseded version-manager installs

`~/.asdf` (2.3 GB) and `~/.local` (2.5 GB) held old toolchain installs on the 2026-09-21
machine. Flag `asdf`/`pyenv`/`rbenv`/`nvm`/`fvm`/`rustup` versions not selected by the
global default or by any `.tool-versions` / `.python-version` / `.nvmrc` in a discovered
project root. `.review` — a reinstall is slow. Depends on C3/C5 so the root set is complete.

### C18 — Duplicate clones

Two clones of one work repository held 1.8 GB of `.git` each on the 2026-09-21 machine.
`git gc` recovers nothing there (see Deliberately out of scope); the reclaim is removing
a clone. Detect-only: group repos under discovered roots by `origin` remote and report
groups of two or more with each clone's size, last commit and dirty state.

### C19 — Database dumps and loose archives

- **Dumps in project trees.** 3.5 GB of Redis `dump.rdb` / `appendonly.aof*` sat under a
  work project's `volumes/redis/`, and a 147 MB `*-dump.sql` loose in `~`. `.review` rule
  for `*.rdb`, `*.aof`, `*.sql`, `*.dump` over 100 MB in project trees and the home
  directory top level.
- **Archive beside its extracted folder.** `Projects/<name>.zip` (253 MB, 63 MB) next to a
  `Projects/<name>/` folder. `.review` when the folder exists; show both sizes.

## AI agent directories

AI coding tools store two unrelated kinds of data under the same parent directories. The
distinction decides what Pare may look at, not just what it may delete.

### Conversation and history — never scan, never report

| Path | Contents |
|------|----------|
| `~/.local/share/opencode/storage/{part,message,session,session_diff,todo,share}` | Message bodies, per-session file diffs |
| `~/.local/share/opencode/opencode.db` | Session database |
| `~/.claude/projects/**/*.jsonl` | Session transcripts |
| `~/.codex/sessions`, `~/.codex/*.sqlite` | Session records and thread history |
| `~/.cache/github-copilot/{project-context,project-index}` | Indexed contents of private repositories |

These hold prompts, model replies, file contents and diffs from real work. They belong in
the same category as SSH keys, not in a cache category.

Path names leak independently of file contents: `~/.claude/projects/` encodes each
project's full path in its directory names, so displaying a finding for one of these
discloses the user's project list even when nothing is deleted.

Required handling: a `ScanPolicy.aiConversationDataMarkers` deny-list, checked where
`appStateSensitiveMarkers` is checked, so no current or future rule can surface them by
accident. Fail closed.

### Reconstructible — eligible

| Path | Contents |
|------|----------|
| `~/.config/opencode/node_modules` | npm dependencies |
| `~/.cache/codex-runtimes/*/dependencies` | Downloaded `bin`, `native`, `node`, `python` runtimes |
| `~/.cache/kilo/{bin,node_modules}` | Runtime and dependencies |
| `~/.cache/hyperframes/{chrome,fonts}` | Downloaded browser and fonts |
| `~/.paseo/models` | Model weights, redownloadable |
| `~/.local/share/<tool>/versions/<superseded>` | Stale release binaries |

`~/.paseo/models` holds local speech models; report as `.review`, never `.safe` —
re-downloading a 622 MB ONNX model is not free.

No conversation content; regenerated or redownloaded on next run.

`~/.config/opencode/node_modules` measured 1.94 GiB on 2026-09-23, most of it the
`opencode-gitnexus` plugin and its embedding runtime, which duplicate the GitNexus MCP
server already configured globally. Worth reporting that duplication, not just the size.

### Superseded legacy store — still denied

OpenCode migrated from the JSON `storage/` tree to `opencode.db`. On 2026-09-23
`storage/{part,message,session_diff}` held 1.42 GiB with no file written since 2026-08-01,
while the database was current. It is a dead copy, but it is still conversation content:
it stays under the deny-list. Pare must not special-case it. If the space matters, the
tool's own migration should remove it.

### Unclassified — survey before any rule

| Path | Size (2026-09-21) |
|------|-------------------|
| `~/.codex` (outside `sessions` and `*.sqlite`) | 691 MB in total |
| `~/.gemini` | 295 MB |

The 2026-09-21 audit proposed adding these as whole-directory catalog entries. That breaks
the design rule below. List their children and classify each one first.

### Design rule

Never target an AI tool's directory as a whole. Enumerate the reconstructible children by
name in `app-catalog.json` — as the `OpenCode` entry already does with `.cache/opencode`,
`.local/share/opencode/log` and `.local/share/opencode/snapshot` rather than
`.local/share/opencode`. Anything not explicitly listed stays untouched.

## Deliberately out of scope

| Area | Reason |
|------|--------|
| Deleting `Docker.raw` | Path-blocked; selective reclaim is Phase 10. See [docker-safety](docker-safety.md). Visibility is in scope: C15 |
| `node_modules` | Dependency tree, not reclaimable output. `ScanPolicy.projectDependencyDirectoryNames`. Exception for inactive projects: C10 |
| Git history bloat | A work repository's `.git` is 1.77 GiB of committed debug binaries (45–103 MB each), already packed so `git gc` recovers nothing. Fixing it means rewriting history or re-cloning, both outside a cleaner's remit |
| `~/Library/Application Support/CloudDocs` | iCloud-managed; macOS evicts under pressure |
| Deleting a duplicate clone | Detect-only (C18); which clone to keep is the user's call |
