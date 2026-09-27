import SwiftUI

/// Single source of truth for sidebar destination tile swatches — see "Sidebar destination tiles" in the redesign plan.
enum DestinationStyle {
    // MARK: - Swatch (light/dark tile fill)

    /// Swatch for a sidebar destination's icon tile. Reuses category hues where the plan pairs them
    /// (e.g. Smart Scan borrows userCaches teal) so the palette reads as one system.
    static func swatch(for destination: AppDestination) -> ThemeSwatch {
        switch destination {
        case .smartScan:
            return ThemeSwatch(light: RGBA(0x1F8A80), dark: RGBA(0x2A9D92))
        case .apps:
            return ThemeSwatch(light: RGBA(0x2F7FD6), dark: RGBA(0x3D8BE0))
        case .homebrew:
            return ThemeSwatch(light: RGBA(0xB86E00), dark: RGBA(0xC27A12))
        case .disk:
            return ThemeSwatch(light: RGBA(0x5A5FE0), dark: RGBA(0x6A6FE6))
        case .maintenance:
            return ThemeSwatch(light: RGBA(0x5E6B78), dark: RGBA(0x6E7C8A))
        case .history:
            return ThemeSwatch(light: RGBA(0x9A4FC8), dark: RGBA(0xA75ED2))
        case .settings:
            return ThemeSwatch(light: RGBA(0x6B7280), dark: RGBA(0x7B8392))
        }
    }

    // MARK: - Destination tint

    /// Tint for a sidebar destination — convenience for callers that only need the resolved `Color`.
    static func tint(for destination: AppDestination) -> Color {
        swatch(for: destination).color
    }
}
