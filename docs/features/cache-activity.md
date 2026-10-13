# Cache activity

Labels ("Written to recently", "Last written N days ago", "Last write unknown") come from the newest
write under each shown cache finding (`CacheActivitySampler`, mtime only: `atime` is unreliable on
APFS). Hot labels also drive the default selection (below).

## Decision (maintainer, 2026-10-13)

- **Cut-offs stay 3 / 30 days** (`CacheActivityClassifier.defaultHotDays` / `defaultColdDays`).
  On 134 cache folders (13.3 GB, 2026-10-07) ages were bimodal: 66 written within a day, 15
  untouched for more than 90 days. N barely moves bytes; M = 30 makes `~/.cache/codex-runtimes`
  (1.5 GB, 58 days) cold.
- **Hot rows start unchecked but stay selectable, one click per row.** The confirmation sheet says
  they will be re-downloaded. No bulk "include all hot" button. Hard-skipping hot would hide nearly
  all scanned cache bytes (pnpm, Playwright, npm, bun), even at critical pressure.
- Cold `.safe` rows stay preselected; warm rows keep their risk level.

## Selection (built 2026-10-13)

Labels land after results appear (largest shown items, 3 s budget). `ScanSelectionModel.applyHotPaths`
then:

- **Unticks hot rows the user has not clicked.** A row counts as clicked once its Largest-items checkbox
  or its folder row was toggled in this scan; a clicked row keeps whatever the user chose.
- **Leaves unlabelled rows alone.** No label means no change.
- **Keeps hot rows out of every bulk action.** A selected folder never covers its hot members, and
  Select All Safe, category and tool-group ticks skip them. Quick Clean All and Deep Clean All ignore
  the selection, so they leave hot rows out too and their sheets say how many. A hot row is ticked only
  by its own checkbox (a folder row whose members are all hot is that row). Unticking a category or
  tool group also unticks hot rows inside it.
- **Totals follow.** Selected count/bytes on the summary card and `CleanActionBar` subtract hot members of
  selected folders; the clean expands folders without them.
- **Clean Selected warns.** With hot rows ticked, the sheet says "N items were written to in the last
  3 days, so their apps will download or rebuild them again."
- **A new scan starts over.** Labels from an older scan are dropped by scan generation, and a new
  scan resets hot and clicked state.
