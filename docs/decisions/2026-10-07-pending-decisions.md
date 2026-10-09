# Open decisions

Still waiting on the maintainer. Measurements are from the maintainer's Mac on 2026-10-07 (8.0 GB
free of 245 GB, read-only). Settled questions moved to `docs/architecture/cleanup-safety.md` and
`docs/features/project-dependency-reclaim.md`.

## A. Cache activity: cut-offs and what "hot" does

Labels ship display-only with N = 3 days (hot) and M = 30 days (cold), in
`CacheActivityClassifier.defaultHotDays` / `defaultColdDays`. The next slice makes them act:
skip hot, preselect cold only when `.safe`, leave warm as `.review`.

Evidence from 134 cache folders (13.3 GB):
- Ages are bimodal: 66 folders written within a day, 15 untouched for more than 90 days.
- N barely moves bytes. M decides one large folder: `~/.cache/codex-runtimes` (1.5 GB, 58 days)
  is cold at M = 30 and warm at M = 60.
- Almost every byte Pare scans today is hot. The 2.6 GB of cold caches sits under `~/.cache/<tool>`
  and `~/.yarn/berry`, which no rule reports yet.

Recommendation: keep **3 / 30**. Pick 7 / 60 to preselect less on first run.

Hot rows: recommended **unchecked but selectable, one click per row**, with the confirmation sheet
saying they will be re-downloaded. Hard-skipping hot would hide nearly all scanned cache bytes
(pnpm, Playwright, npm, bun) even at critical pressure. No bulk "include all hot" button.

## B. Project discovery: `package.json` as a Spotlight signal (#45)

`package.json` matches every package inside every `node_modules`. Here: 2,080 hits, 1,875 of them in
`node_modules`, `mdfind` 0.5 s. A JS-heavy machine could hit the 10 s discovery timeout. Searching
for lockfiles instead finds 104 project folders against 201. Options: keep `package.json`, or switch
to lockfiles and accept missing lockfile-less projects.

## C. Dependency reclaim: later slices

- **"Save package list" for a venv with no manifest** would be Pare's first write into a user's
  project (`venv-packages-<date>.txt`). Allow it, or leave such venvs unreported (fail closed)?
- **Manifest-only projects** (`package.json` or `requirements.txt`, no lockfile): add them with a
  version-drift warning only if users ask.

## D. Disk Analyzer: files no scan covers

"Add to Review" accepts only paths a Smart Scan finding covers, and everything goes to the Trash.
Two questions were left open by the redesign:
- Allow a user-chosen file outside every finding? It needs its own `ScanPolicy` gate and a security
  review first.
- Offer permanent delete for large items, or stay Trash-only?
