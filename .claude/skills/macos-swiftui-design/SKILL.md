---
name: macos-swiftui-design
description: "Use when building or refining macOS SwiftUI UI/UX with a premium visual style, design tokens, motion, and adaptive layout quality. Examples: \"Design a beautiful dashboard\", \"Polish this SwiftUI macOS UI\", \"Make this app feel like a top-tier Mac utility\""
---

# macOS SwiftUI Design Skill

## Purpose
Create beautiful, production-ready macOS SwiftUI interfaces that feel intentional, premium, and native while staying maintainable.

## When to Use
- Building new app screens in SwiftUI for macOS
- Polishing existing SwiftUI visuals and interaction quality
- Defining a design system (tokens, components, motion)
- Improving hierarchy, spacing, readability, and perceived performance

## Design Quality Bar
- Clear visual direction, not generic utility UI
- Strong hierarchy: hero metric first, actionable controls second, details third
- Premium depth: layered background, subtle materials, restrained shadows
- Purposeful motion: transitions explain state changes, not decoration
- Native macOS feel: typography, spacing, hover/selection behavior, window resizing support

## Workflow
1. Define visual direction and design tokens first.
2. Build reusable primitives (background, card, metric tile, buttons).
3. Compose screen layout with explicit hierarchy.
4. Add motion for scan lifecycle and results reveal.
5. Validate readability/performance on small and large window sizes.

## Recommended Token Set
- Color tokens: `bg.base`, `bg.elevated`, `text.primary`, `text.secondary`, `accent`, `success`, `warning`, `danger`
- Spacing scale: 4, 8, 12, 16, 24, 32
- Radius scale: 8, 12, 16, 24
- Shadow presets: subtle (`y=2`), elevated (`y=8`)
- Motion presets:
  - quick: 0.2s easeOut
  - standard: 0.3s spring (low bounce)
  - reveal stagger: 0.04-0.08s per item

## macOS SwiftUI Patterns
- Prefer `NavigationSplitView` or clear single-pane dashboard structure.
- Use `Material` backgrounds sparingly; avoid blur-heavy dense lists.
- Keep primary action always visible (`Scan`/`Rescan`).
- Use smooth number interpolation for storage metrics.
- Keep lists scan-friendly: icon, title, size, last-used metadata.

## Core Components To Implement
- `AppBackgroundView`: layered gradient + subtle noise texture
- `GlassCard`: reusable elevated container with material tint
- `MetricTile`: animated metric value + subtitle + trend/status
- `CategorySummaryRow`: color-coded category + bytes + percentage bar
- `TopFileRow`: path, size, confidence/risk badge
- `PrimaryActionButton`: prominent CTA with hover/press states

## Motion Guidance
- Scan started: gentle pulse/halo around scan CTA and status panel
- Scan progress: avoid jumpy progress indicators; prefer smooth interpolation
- Scan complete: stagger cards and top-file rows into view
- Error state: minimal shake/flash only once, then stable recovery UI

## Accessibility and Readability
- Minimum 4.5:1 contrast for body text areas
- Do not encode meaning with color only; include icon/label
- Maintain legible font sizes at narrow window widths
- Ensure keyboard navigation for primary controls

## Performance Guardrails
- Avoid large nested `blur`/`material` stacks in scroll-heavy regions
- Precompute formatted byte strings in view model, not in `body`
- Prefer lightweight gradients over expensive custom drawing loops
- Profile with Instruments when adding advanced visual effects

## Done Checklist
- [ ] Design tokens centralized (single source)
- [ ] Reusable components created for cards/metrics/actions
- [ ] Primary scan flow visually polished and state-driven
- [ ] Empty/loading/error/success states styled consistently
- [ ] Works well at compact and wide macOS window sizes
- [ ] No obvious UI jank during scanning and result updates
