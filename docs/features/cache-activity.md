# Cache activity

Labels ("Written to recently", "Last written N days ago", "Last write unknown") come from the newest
write under each shown cache finding (`CacheActivitySampler`, mtime only: `atime` is unreliable on
APFS). Today they are display-only.

## Decision (maintainer, 2026-10-13)

- **Cut-offs stay 3 / 30 days** (`CacheActivityClassifier.defaultHotDays` / `defaultColdDays`).
  On 134 cache folders (13.3 GB, 2026-10-07) ages were bimodal: 66 written within a day, 15
  untouched for more than 90 days. N barely moves bytes; M = 30 makes `~/.cache/codex-runtimes`
  (1.5 GB, 58 days) cold.
- **Hot rows start unchecked but stay selectable, one click per row.** The confirmation sheet says
  they will be re-downloaded. No bulk "include all hot" button. Hard-skipping hot would hide nearly
  all scanned cache bytes (pnpm, Playwright, npm, bun), even at critical pressure.
- Cold `.safe` rows stay preselected; warm rows keep their risk level.

## Not built yet

Selection does not read the labels yet (roadmap: Product backlog). Labels are sampled after results
appear, for the largest shown items within a 3 s budget, so the slice has to deselect hot rows the
user has not touched and leave unlabelled rows as they are.
