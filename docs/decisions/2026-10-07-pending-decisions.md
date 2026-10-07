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
