import AppKit
import SwiftUI

/// Brand mark for Pare — the disk-with-a-cut logo from `scripts/icon.svg`.
///
/// Loaded from the app bundle (`PareLogo.png` or `AppIcon.icns`) when packaged
/// via `make run-app` / `make release`. Falls back to a compact drawn mark if
/// the resource is missing (e.g. raw `swift run` without a `.app` wrapper).
struct PareBrandLogo: View {
    var size: CGFloat = 34

    var body: some View {
        Group {
            if let image = Self.bundledLogo {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                drawnFallback
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: AppTheme.accent.opacity(0.35), radius: max(6, size * 0.22), y: 2)
        .accessibilityHidden(true)
    }

    /// Prefer the dedicated PNG; fall back to the Dock `.icns`.
    private static var bundledLogo: NSImage? {
        if let url = Bundle.main.url(forResource: "PareLogo", withExtension: "png"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        if let image = NSImage(named: "AppIcon"), image.isValid, image.size.width > 0 {
            return image
        }
        return nil
    }

    /// Approximate the SVG when bundle resources are unavailable.
    private var drawnFallback: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.11, green: 0.20, blue: 0.28),
                            Color(red: 0.04, green: 0.08, blue: 0.13)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.60, green: 0.93, blue: 0.90),
                            Color(red: 0.36, green: 0.78, blue: 0.74),
                            Color(red: 0.12, green: 0.47, blue: 0.44)
                        ],
                        center: UnitPoint(x: 0.36, y: 0.28),
                        startRadius: 0,
                        endRadius: size * 0.55
                    )
                )
                .frame(width: size * 0.70, height: size * 0.70)
                .mask(
                    // Lower-right chord cut — matches the "pared" disk silhouette.
                    Path { path in
                        let r = size * 0.35
                        let c = CGPoint(x: size * 0.5, y: size * 0.5)
                        path.addArc(
                            center: c,
                            radius: r,
                            startAngle: .degrees(22),
                            endAngle: .degrees(117),
                            clockwise: true
                        )
                        path.closeSubpath()
                    }
                )
        }
    }

    /// Apply the brand icon to the Dock / app switcher when the bundle has one.
    @MainActor
    static func applyDockIconIfAvailable() {
        guard let image = bundledLogo else { return }
        NSApp.applicationIconImage = image
    }
}
