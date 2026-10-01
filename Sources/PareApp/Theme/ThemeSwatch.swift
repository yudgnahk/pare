import AppKit
import SwiftUI

/// 24-bit RGB plus alpha; the raw storage behind one appearance side of a `ThemeSwatch`.
struct RGBA: Sendable, Equatable {
    let hex: UInt32
    let alpha: Double

    init(_ hex: UInt32, alpha: Double = 1) {
        self.hex = hex
        self.alpha = alpha
    }

    var red: Double { Double((hex >> 16) & 0xFF) / 255.0 }
    var green: Double { Double((hex >> 8) & 0xFF) / 255.0 }
    var blue: Double { Double(hex & 0xFF) / 255.0 }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// A light/dark color pair that resolves per-render against the active system appearance.
struct ThemeSwatch: Sendable {
    let light: RGBA
    let dark: RGBA

    init(light: RGBA, dark: RGBA) {
        self.light = light
        self.dark = dark
    }

    /// Convenience for tokens with the same hex in both appearances.
    init(_ hex: UInt32, alpha: Double = 1) {
        self.init(light: RGBA(hex, alpha: alpha), dark: RGBA(hex, alpha: alpha))
    }

    /// Dynamic-provider `NSColor`; resolves against the appearance active at draw/query time.
    var nsColor: NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? self.dark.nsColor : self.light.nsColor
        }
    }

    /// Bridges through `nsColor` so `Canvas`, gradients and `.opacity()` all adapt for free.
    var color: Color { Color(nsColor: nsColor) }
}

/// WCAG 2.x relative-luminance contrast ratio between two opaque colors.
enum WCAG {
    static func contrastRatio(_ a: RGBA, _ b: RGBA) -> Double {
        let lighter = max(relativeLuminance(a), relativeLuminance(b))
        let darker = min(relativeLuminance(a), relativeLuminance(b))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private static func relativeLuminance(_ c: RGBA) -> Double {
        func channel(_ v: Double) -> Double {
            v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
    }
}
