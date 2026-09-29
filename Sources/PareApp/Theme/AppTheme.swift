import SwiftUI

/// Central design tokens for Pare — "Tidewater": calm seafoam with a sunlit apricot accent.
///
/// Color source of truth: `docs/brand-guide.html` + `docs/design/ui-wow-audit.md`.
/// Views must never hardcode colors, radii, or paddings.
enum AppTheme {
    // MARK: - Adaptive swatches (light/dark pairs; source of truth for semantic colors)

    /// Raw light/dark pairs behind every semantic token. Tests read these directly,
    /// with no `NSColor` resolution involved — see palette table in the redesign plan.
    enum Swatch {
        static let base = ThemeSwatch(light: RGBA(0xF2F5F4), dark: RGBA(0x0D1520))
        static let panel = ThemeSwatch(light: RGBA(0xFFFFFF), dark: RGBA(0x1A2B3C))
        static let panelSecondary = ThemeSwatch(light: RGBA(0xE8EEEE), dark: RGBA(0x152030))
        static let cardFill = ThemeSwatch(light: RGBA(0xFFFFFF, alpha: 0.88), dark: RGBA(0x1A2B3C, alpha: 0.66))
        static let sidebar = ThemeSwatch(light: RGBA(0xE9EFEE), dark: RGBA(0x121C28))
        static let sidebarSelected = ThemeSwatch(light: RGBA(0xD3EBE7), dark: RGBA(0x1F4757))

        static let textPrimary = ThemeSwatch(light: RGBA(0x14202B), dark: RGBA(0xE4EDF2))
        static let textSecondary = ThemeSwatch(light: RGBA(0x43566A), dark: RGBA(0xA9BCC9))
        static let textTertiary = ThemeSwatch(light: RGBA(0x53677A), dark: RGBA(0x8499A9))

        static let accent = ThemeSwatch(light: RGBA(0x17706A), dark: RGBA(0x5CC8BC))
        static let accentDeep = ThemeSwatch(light: RGBA(0x0F5A55), dark: RGBA(0x238C82))
        static let onAccent = ThemeSwatch(light: RGBA(0xFFFFFF), dark: RGBA(0x0D1520))
        /// Decorative seafoam for rings and glows — never used as text.
        static let accentBright = ThemeSwatch(light: RGBA(0x3FB3A7), dark: RGBA(0x5CC8BC))
        /// Primary CTA gradient; `onAccent` must clear 3:1 (large text) on both stops.
        static let ctaTop = ThemeSwatch(light: RGBA(0x1F8A80), dark: RGBA(0x5CC8BC))
        static let ctaBottom = ThemeSwatch(light: RGBA(0x0F5A55), dark: RGBA(0x3AA99D))

        /// Apricot marks reclaimable space; `warm` is decorative, `warmText` is text-safe.
        static let warm = ThemeSwatch(light: RGBA(0xEFA06B), dark: RGBA(0xF2AE7E))
        static let warmText = ThemeSwatch(light: RGBA(0x9A4A12), dark: RGBA(0xF4B58A))

        static let success = ThemeSwatch(light: RGBA(0x1A7542), dark: RGBA(0x57DB94))
        static let warning = ThemeSwatch(light: RGBA(0x8F5500), dark: RGBA(0xF7BD4F))
        static let review = ThemeSwatch(light: RGBA(0xB8352A), dark: RGBA(0xFA7A6B))

        static let tableHeaderBackground = ThemeSwatch(light: RGBA(0x152030, alpha: 0.04), dark: RGBA(0x000000, alpha: 0.12))

        static let hairlineFaint = ThemeSwatch(light: RGBA(0x152030, alpha: 0.05), dark: RGBA(0xFFFFFF, alpha: 0.04))
        static let hairlineStandard = ThemeSwatch(light: RGBA(0x152030, alpha: 0.09), dark: RGBA(0xFFFFFF, alpha: 0.07))
        static let hairlineStrong = ThemeSwatch(light: RGBA(0x152030, alpha: 0.16), dark: RGBA(0xFFFFFF, alpha: 0.14))

        static let fillSubtle = ThemeSwatch(light: RGBA(0x152030, alpha: 0.04), dark: RGBA(0xFFFFFF, alpha: 0.06))
        static let fillControl = ThemeSwatch(light: RGBA(0x152030, alpha: 0.06), dark: RGBA(0xFFFFFF, alpha: 0.08))
        static let fillHover = ThemeSwatch(light: RGBA(0x152030, alpha: 0.08), dark: RGBA(0xFFFFFF, alpha: 0.10))
        static let fillSelected = ThemeSwatch(light: RGBA(0x152030, alpha: 0.12), dark: RGBA(0xFFFFFF, alpha: 0.18))

        static let shadowCard = ThemeSwatch(light: RGBA(0x152030, alpha: 0.08), dark: RGBA(0x000000, alpha: 0.20))
        static let backgroundVignette = ThemeSwatch(light: RGBA(0x000000, alpha: 0), dark: RGBA(0x000000, alpha: 0.22))
        static let backgroundBloom = ThemeSwatch(light: RGBA(0x3FB3A7, alpha: 0.14), dark: RGBA(0x5CC8BC, alpha: 0.16))
        static let backgroundWarmBloom = ThemeSwatch(light: RGBA(0xEFA06B, alpha: 0.12), dark: RGBA(0xF2AE7E, alpha: 0.07))
        static let cardHighlight = ThemeSwatch(light: RGBA(0xFFFFFF, alpha: 0.9), dark: RGBA(0xFFFFFF, alpha: 0.10))
    }

    // MARK: - Semantic colors

    static let base = Swatch.base.color
    static let panel = Swatch.panel.color
    static let panelSecondary = Swatch.panelSecondary.color
    static let cardFill = Swatch.cardFill.color
    static let sidebar = Swatch.sidebar.color
    static let sidebarSelected = Swatch.sidebarSelected.color
    static let textPrimary = Swatch.textPrimary.color
    static let textSecondary = Swatch.textSecondary.color
    static let textTertiary = Swatch.textTertiary.color
    /// Pare seafoam accent
    static let accent = Swatch.accent.color
    /// Accent used as text (buttons, links, active states) rather than a fill.
    static let accentText = Swatch.accent.color
    static let accentDeep = Swatch.accentDeep.color
    /// Text/glyph color drawn on top of `accent`, `success` or `review` fills.
    static let onAccent = Swatch.onAccent.color
    static let accentBright = Swatch.accentBright.color
    /// Reclaimable-space accent (arcs, bars, blooms).
    static let warm = Swatch.warm.color
    /// Reclaimable-space labels.
    static let warmText = Swatch.warmText.color
    static let success = Swatch.success.color
    static let warning = Swatch.warning.color
    static let review = Swatch.review.color

    /// Column-header strip behind sortable tables (Apps, Homebrew).
    static let tableHeaderBackground = Swatch.tableHeaderBackground.color

    static let pageGradient = LinearGradient(
        colors: [base, panelSecondary, panel],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Fill for the single most important action on a screen (Scan, Clean).
    static let ctaGradient = LinearGradient(
        colors: [Swatch.ctaTop.color, Swatch.ctaBottom.color],
        startPoint: .top,
        endPoint: .bottom
    )

    /// Seafoam sweep for disk and progress rings.
    static let ringGradient = AngularGradient(
        colors: [accentDeep, accentBright, accentBright, accentDeep],
        center: .center,
        startAngle: .degrees(-90),
        endAngle: .degrees(270)
    )

    /// Horizontal counterpart of `ringGradient` for meters and bars.
    static let barGradient = LinearGradient(
        colors: [accentDeep, accentBright],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let heroGlow = RadialGradient(
        colors: [
            accent.opacity(0.35),
            accentDeep.opacity(0.12),
            .clear
        ],
        center: .center,
        startRadius: 20,
        endRadius: 280
    )

    // MARK: - Hairlines (strokes / dividers)

    /// Consolidated hairline strokes — adapts per appearance instead of a fixed white alpha.
    enum Hairline {
        /// Barely-there separators and resting row washes.
        static let faint = Swatch.hairlineFaint.color
        /// Standard 1 pt strokes / dividers.
        static let standard = Swatch.hairlineStandard.color
        /// Emphasized strokes (hovered capsules, prominent borders).
        static let strong = Swatch.hairlineStrong.color
    }

    // MARK: - Translucent fills (chips, rows, controls)

    enum Fill {
        /// Resting chip / row background.
        static let subtle = Swatch.fillSubtle.color
        /// Slightly raised control background (capsule chips, pills).
        static let control = Swatch.fillControl.color
        /// Hover highlight for rows and controls.
        static let hover = Swatch.fillHover.color
        /// Selected segment / tab background.
        static let selected = Swatch.fillSelected.color
    }

    // MARK: - Shadows

    enum Shadow {
        /// Drop shadow under raised cards.
        static let card = Swatch.shadowCard.color
        /// One-pixel top-edge sheen on raised surfaces.
        static let highlight = Swatch.cardHighlight.color
    }

    // MARK: - Elevation

    /// Shadow presets: resting rows, raised cards, floating bars / hero CTA.
    enum Elevation {
        case subtle, raised, floating

        var radius: CGFloat {
            switch self {
            case .subtle: return 6
            case .raised: return 16
            case .floating: return 28
            }
        }

        var y: CGFloat {
            switch self {
            case .subtle: return 2
            case .raised: return 8
            case .floating: return 12
            }
        }

        var opacity: Double {
            switch self {
            case .subtle: return 0.6
            case .raised: return 1
            case .floating: return 1.4
            }
        }
    }

    // MARK: - Background layers (page ground effects)

    enum Background {
        /// Darkening wash at the page edges; clear in light mode.
        static let vignette = Swatch.backgroundVignette.color
        /// Faint accent glow behind hero content.
        static let bloom = Swatch.backgroundBloom.color
        /// Apricot counterweight, bottom-leading.
        static let warmBloom = Swatch.backgroundWarmBloom.color
    }

    // MARK: - Spacing

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
        static let xxxl: CGFloat = 48
        static let pageHorizontal: CGFloat = 28
        static let pageVertical: CGFloat = 22
        /// Default GlassCard content padding.
        static let card: CGFloat = 18
        /// Dense cards (selection bar, coaching cards).
        static let cardCompact: CGFloat = 14
        /// Fixed left nav column — always visible (not collapsible SplitView).
        static let sidebarWidth: CGFloat = 232
    }

    // MARK: - Radius

    enum Radius {
        static let sm: CGFloat = 8
        /// List / table rows and inline banners.
        static let row: CGFloat = 10
        static let md: CGFloat = 12
        /// Filter chips, sort menus, metric chips.
        static let chip: CGFloat = 10
        /// Compact chips (segmented tab highlight).
        static let chipCompact: CGFloat = 7
        /// Tiny status badges (pinned / auto / MAS).
        static let badge: CGFloat = 4
        /// Standard cards.
        static let lg: CGFloat = 16
        static let xl: CGFloat = 20
        /// Hero surfaces and the floating action bar.
        static let hero: CGFloat = 24
    }

    // MARK: - Sheets

    enum Sheet {
        /// Single-purpose confirmations (Leave Homebrew).
        static let narrowWidth: CGFloat = 460
        /// Standard management sheets (exclusions, project paths, bulk confirm).
        static let standardWidth: CGFloat = 520
        /// Detail-heavy confirmations (uninstall with leftovers, deep clean).
        static let wideWidth: CGFloat = 560
        /// Streaming operation log sheet.
        static let operationWidth: CGFloat = 620
        static let standardHeight: CGFloat = 420
        static let operationHeight: CGFloat = 480
    }

    // MARK: - Control sizes

    enum Control {
        static let primaryHeight: CGFloat = 36
        static let secondaryHeight: CGFloat = 32
        static let iconSize: CGFloat = 28
        static let primaryMinWidth: CGFloat = 112
        static let ringButtonSize: CGFloat = 96
        /// Smart Scan hero: disk ring diameter and the scan orb inside it.
        static let heroRing: CGFloat = 264
        static let heroOrb: CGFloat = 176
        static let summaryRing: CGFloat = 132
    }

    // MARK: - Motion

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.18)
        static let standard = Animation.spring(response: 0.38, dampingFraction: 0.86)
        static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.88)
        static let ringPulse = Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
        static let reveal = Animation.spring(response: 0.6, dampingFraction: 0.9)
        static let countUp = Animation.easeOut(duration: 1.1)
        static let ringFill = Animation.spring(response: 1.1, dampingFraction: 0.9)
        static let breathe = Animation.easeInOut(duration: 2.4).repeatForever(autoreverses: true)
        static let orbit = Animation.linear(duration: 2.2).repeatForever(autoreverses: false)
        static let staggerStep: Double = 0.05

        /// Staggered reveal for the nth item in a freshly shown list.
        static func stagger(_ index: Int) -> Animation {
            reveal.delay(Double(min(index, 8)) * staggerStep)
        }
    }

    // MARK: - Breakpoints

    enum Breakpoint {
        static let metricMin: CGFloat = 200
        static let cardMin: CGFloat = 300
    }

    // MARK: - Window

    enum Window {
        static let minWidth: CGFloat = 980
        static let minHeight: CGFloat = 640
        static let defaultWidth: CGFloat = 1240
        static let defaultHeight: CGFloat = 800
    }
}

// MARK: - Hex color support

extension Color {
    /// Creates an opaque sRGB color from a 24-bit `0xRRGGBB` literal.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1
        )
    }
}
