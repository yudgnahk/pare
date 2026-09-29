# Pare UI "wow" pass — audit and direction

Branch `feat/ui-wow`, built on the Phase 11 redesign (adaptive `ThemeSwatch` tokens, icon tiles,
vibrant sidebar, Disk Analyzer table). Screens were audited from DEBUG snapshots rendered by
`SnapshotRenderer` (see "Screenshots" below), in light and dark.

## 1. Audit

| Area | What we saw | Impact |
|---|---|---|
| **Hierarchy — Smart Scan idle** | Hero is a generic drive glyph in a box, then a small white 96 pt "Scan" ring. Nothing tells you *how full your disk is*, the one number people open a cleaner for. A second "Settings" link sits bottom-right. | High |
| **Hierarchy — Smart Scan results** | The reclaimable number appears twice (header and the first metric tile). "Clean selected" appears twice (header and Review & Clean). The header row holds four buttons in four colors (teal, grey, green, red). "Status: Complete" and "Top candidates: 13" tiles carry no decision value. | High |
| **Scanning state** | Honest progress (rule counts), but it's a thin 280 pt `ProgressView` below a spinner inside the ring. The ring spinner and the linear bar say the same thing twice. | Medium |
| **Result moment** | "Cleaned 12 GB" is a one-line `StatusBanner` — the most satisfying moment in the app gets the same weight as a warning. | High |
| **Typography** | The scale is sound (`DisplayScale`), but heroes are 26–28 pt; there's no display size for the headline number. Uppercase eyebrows are used inconsistently. | Medium |
| **Spacing rhythm** | Mixes 4/5/6/7/8/9/10/12/14/18/22/28 literals. Cards use 18, pages use 28/22, and headers pick their own paddings. | Medium |
| **Color** | Light-mode page ground has a heavy grey-teal blob bottom-left (`accentDeep @ 0.28`) that reads as dirt. There's no warm counterweight, so the whole UI is one cold hue. The primary button gradient runs accent→*success* (teal→green) — two semantics in one fill. | High |
| **Module headers** | Apps, Homebrew, Maintenance, History and Settings each hand-roll a header with a flat accent-tinted glyph. Disk Analyzer has no icon at all. None use the sidebar's destination colors, so the sidebar and the page don't match. | Medium |
| **Density** | Results page is dense at 13" (header + selection card + 3 tiles before the first category). Long helper paragraphs ("Expand a category → tool …") repeat instructions the UI already shows. | Medium |
| **Motion** | Hero fades in, the ring rotates, some rows animate. No count-ups, no reveal of results, no Reduce Motion handling anywhere (`repeatForever` pulses run regardless). | Medium |
| **Empty / loading states** | Grey 36 pt glyph + text. Apps/Homebrew loading is a bare spinner and a sentence. | Medium |
| **Destructive affordances** | Good fundamentals: every clean goes through `CleanConfirmationSheet` → `CleanupCoordinator` → `CleanupEngine` (Trash only), and the confirm button has no default-key shortcut. Problem: "Deep Clean all…" sits beside Rescan in the header at the same visual weight, and nothing on the page says "goes to Trash, undoable" until the sheet. | High (trust) |
| **Sidebar** | Selected row is a neutral grey fill that barely separates from the vibrancy. The brand header crowds the traffic lights. The "Text size ⌘+ ⌘− ⌘0" footer is utility copy in prime space. | Low–Medium |

## 2. Direction — "Tidewater"

**Calm seafoam, a touch of sunlit apricot.** Seafoam stays the brand primary (see `docs/brand-guide.html`),
desaturated slightly on large fills. It's paired with one warm accent, apricot, which marks *what you
can reclaim*. Everything else is quiet mist (light) or ink-navy (dark) neutrals, with native
materials and generous whitespace. The warm/cool split is the story: cool = your disk, warm = space
you can take back, green = done.

### Palette (light / dark hex)

| Token | Light | Dark | Use |
|---|---|---|---|
| `base` | `#F2F5F4` | `#0D1520` | Page ground |
| `panel` | `#FFFFFF` | `#1A2B3C` | Cards, sheets |
| `panelSecondary` | `#E8EEEE` | `#152030` | Nested wells |
| `textPrimary` | `#14202B` | `#E4EDF2` | Body, titles |
| `textSecondary` | `#43566A` | `#A9BCC9` | Supporting copy |
| `textTertiary` | `#53677A` | `#8499A9` | Meta, eyebrows |
| `accent` (text-safe seafoam) | `#17706A` | `#5CC8BC` | Links, active text |
| `accentBright` (decorative) | `#3FB3A7` | `#5CC8BC` | Ring/used arc, glows |
| `accentDeep` | `#0F5A55` | `#238C82` | Gradient foot |
| `ctaTop → ctaBottom` | `#1F8A80 → #0F5A55` | `#5CC8BC → #3AA99D` | Scan button fill |
| `warm` (decorative apricot) | `#EFA06B` | `#F2AE7E` | Reclaimable arc, warm bloom |
| `warmText` | `#9A4A12` | `#F4B58A` | Reclaimable labels |
| `success` / `warning` / `review` | `#1A7542` / `#8F5500` / `#B8352A` | `#57DB94` / `#F7BD4F` / `#FA7A6B` | Unchanged semantics |

Every text token is gated at ≥ 4.5:1 on `base`/`panel`/`panelSecondary` in both modes by
`ThemeContrastTests`; the CTA fill is gated at ≥ 3:1 (large text) against `onAccent`.

### Type scale (points before `DisplayScale`)

`display 44 bold rounded` (hero numbers) · `heroTitle 26 bold rounded` · `pageTitle 21 bold rounded` ·
`sectionTitle 16 semibold rounded` · `body 14 medium` · `caption 13 medium` · `micro 12 semibold` ·
`eyebrow 11 bold, tracking 1.1, uppercase`. Numbers use `.monospacedDigit()` so count-ups don't jitter.

### Spacing / radius / elevation

- Spacing: 4 · 8 · 12 · 16 · 24 · 32 · 48 (`xs…xxxl`); page gutters 28 × 22.
- Radius: 8 (controls) · 10 (rows/chips) · 12 (wells) · 16 (cards) · 24 (hero surfaces), all `.continuous`.
- Elevation: `subtle` = y 2 / r 6 at `shadowCard × 0.6`; `raised` = y 8 / r 16 (+ 1 px top highlight);
  `floating` = y 12 / r 28 (bottom action bar, hero CTA).

### Motion

| Token | Curve | Used for |
|---|---|---|
| `quick` | easeOut 0.18 s | Hover, press |
| `standard` | spring 0.38 / 0.86 | Selection, toggles |
| `gentle` | spring 0.55 / 0.88 | Hero entrance |
| `reveal` | spring 0.6 / 0.9 + 0.05 s stagger | Results cards |
| `countUp` | easeOut 1.1 s | Byte totals |
| `ringFill` | spring 1.1 / 0.9 | Disk/progress rings |
| `breathe` | easeInOut 2.4 s, repeat | CTA halo while idle |

All looping or travelling motion goes through `MotionPolicy` and turns into a plain fade (or a static
state) when **Reduce Motion** is on.

## 3. Implementation map

- **Smart Scan hero**: `DiskUsageRing` (live startup-volume usage via `VolumeUsageModel`) wraps a big
  gradient `ScanOrbButton`. While scanning, the same ring becomes an honest rule-count progress ring
  with a travelling highlight, a percentage count-up and step chips. Trust chips under the headline:
  Trash-first, risk-labelled, undoable.
- **Smart Scan results**: `ScanSummaryHero` (compact ring, count-up total, stacked category bar with
  legend, Rescan + overflow menu), decision tiles (Safe / Needs review / Selected), and a floating
  `CleanActionBar` that holds every clean action in one place. Deep Clean stays behind its
  confirmation sheet, rendered as a quiet destructive control, not a peer of Rescan.
- **Result moment**: `CleanResultCard`, a drawn check ring, "12 GB freed" count-up, one-shot sparkle
  burst, Undo, and "moved to Trash" reassurance.
- **Shell**: sidebar accent-pill selection + hover, storage mini-meter footer; calmer page ground
  (seafoam top-right, apricot bottom-left, no grey blob).
- **Everywhere**: `PageHeader` with destination-colored `IconTile` for every module, refreshed
  `GlassCard` elevation, `EmptyStateView` halo tiles, `LoadingStateView`.

## Screenshots

`docs/design/screenshots/ui-wow/*.png`, rendered with:

```bash
make build
PARE_SNAPSHOT_DIR=docs/design/screenshots/ui-wow .build/debug/PareApp   # DEBUG builds only; quits when done
```

Scenes come from `Sources/PareApp/Debug/SnapshotRenderer.swift`, and scan data from `SnapshotFixtures`
(nothing is scanned or cleaned). Disk usage in the ring is the real startup volume.
