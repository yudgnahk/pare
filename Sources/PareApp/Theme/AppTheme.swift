import SwiftUI

enum AppTheme {
    static let base = Color(red: 0.05, green: 0.08, blue: 0.14)
    static let panel = Color(red: 0.10, green: 0.14, blue: 0.24)
    static let panelSecondary = Color(red: 0.08, green: 0.11, blue: 0.19)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.74)
    static let accent = Color(red: 0.20, green: 0.73, blue: 0.94)
    static let success = Color(red: 0.34, green: 0.83, blue: 0.55)
    static let warning = Color(red: 0.97, green: 0.74, blue: 0.31)
    static let review = Color(red: 0.98, green: 0.53, blue: 0.41)

    static let pageGradient = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.05, blue: 0.11),
            Color(red: 0.07, green: 0.14, blue: 0.22),
            Color(red: 0.12, green: 0.21, blue: 0.29)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
