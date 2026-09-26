import SwiftUI

/// Central design tokens for Pare — teal / navy premium utility aesthetic.
///
/// Color source of truth: `docs/brand-guide.html`. Semantic tokens below point
/// at the brand palette; views must never hardcode colors, radii, or paddings.
enum AppTheme {
    // MARK: - Brand palette (docs/brand-guide.html)

    /// Raw brand colors. Prefer the semantic tokens (`base`, `panel`, `accent`,
    /// `textPrimary`, …) in views; reach for `Brand` only when defining new
    /// semantic tokens.
    enum Brand {
        /// Page ground.
        static let ink = Color(hex: 0x0D1520)
        /// Recessed / secondary surface.
        static let marine = Color(hex: 0x152030)
        /// Raised surface (cards, panels).
        static let surface = Color(hex: 0x1A2D40)
        /// Primary mark — Pare seafoam accent.
        static let seafoam = Color(hex: 0x5CC8BC)
        /// Highlight ("Mist").
        static let seafoamLight = Color(hex: 0x8DE8E0)
        /// Deep accent for gradients and pressed states.
        static let seafoamDeep = Color(hex: 0x238C82)
        /// Typography.
        static let chalk = Color(hex: 0xE4EDF2)
        /// Warm typography accents.
        static let chalkWarm = Color(hex: 0xEDF2F5)
        /// Secondary text (brand); use with care on dark grounds (contrast).
        static let fog = Color(hex: 0x7A9BB0)
    }

    // MARK: - Adaptive swatches (light/dark pairs; source of truth for semantic colors)

    /// Raw light/dark pairs behind every semantic token. Tests read these directly,
    /// with no `NSColor` resolution involved — see palette table in the redesign plan.
    enum Swatch {
        static let base = ThemeSwatch(light: RGBA(0xEDF2F5), dark: RGBA(0x0D1520))
        static let panel = ThemeSwatch(light: RGBA(0xFFFFFF), dark: RGBA(0x1A2D40))
        static let panelSecondary = ThemeSwatch(light: RGBA(0xE4EBF0), dark: RGBA(0x152030))
        static let cardFill = ThemeSwatch(light: RGBA(0xFFFFFF, alpha: 0.85), dark: RGBA(0x1A2D40, alpha: 0.62))
        static let sidebar = ThemeSwatch(light: RGBA(0xE6EDF2), dark: RGBA(0x152030))
        static let sidebarSelected = ThemeSwatch(light: RGBA(0xD3EBE7), dark: RGBA(0x1F4757))

        static let textPrimary = ThemeSwatch(light: RGBA(0x152030), dark: RGBA(0xE4EDF2))
        static let textSecondary = ThemeSwatch(light: RGBA(0x44586A), dark: RGBA(0xA9BCC9))
        static let textTertiary = ThemeSwatch(light: RGBA(0x56697B), dark: RGBA(0x8499A9))

        static let accent = ThemeSwatch(light: RGBA(0x17706A), dark: RGBA(0x5CC8BC))
        static let accentDeep = ThemeSwatch(light: RGBA(0x0F5A55), dark: RGBA(0x238C82))
        static let onAccent = ThemeSwatch(light: RGBA(0xFFFFFF), dark: RGBA(0x0D1520))

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
        static let backgroundBloom = ThemeSwatch(light: RGBA(0x17706A, alpha: 0.08), dark: RGBA(0x5CC8BC, alpha: 0.22))
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
    }

    // MARK: - Background layers (page ground effects)

    enum Background {
        /// Darkening wash at the page edges; clear in light mode.
        static let vignette = Swatch.backgroundVignette.color
        /// Faint accent glow behind hero content.
        static let bloom = Swatch.backgroundBloom.color
    }

    // MARK: - Spacing

    enum Spacing {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
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
        static let xl: CGFloat = 20
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
    }

    // MARK: - Motion

    enum Motion {
        static let quick = Animation.easeOut(duration: 0.18)
        static let standard = Animation.spring(response: 0.38, dampingFraction: 0.86)
        static let gentle = Animation.spring(response: 0.55, dampingFraction: 0.88)
        static let ringPulse = Animation.easeInOut(duration: 1.4).repeatForever(autoreverses: true)
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
