import SwiftUI

/// Prominent filled CTA used for the single most important action on a screen
/// (Scan, Refresh, Upgrade All). Prefer `SecondaryActionButton` for supporting actions.
struct PrimaryActionButton: View {
    enum Style {
        case prominent
        /// Slightly smaller padding — use when multiple CTAs share a toolbar.
        case compact
    }

    enum Tint {
        case accent
        case success
        case warning
        case review

        var colors: [Color] {
            switch self {
            case .accent:
                return [AppTheme.accent, AppTheme.success]
            case .success:
                return [AppTheme.success, AppTheme.success.opacity(0.85)]
            case .warning:
                return [AppTheme.warning, AppTheme.warning.opacity(0.88)]
            case .review:
                return [AppTheme.review, Color(red: 0.92, green: 0.38, blue: 0.32)]
            }
        }

        var shadow: Color {
            switch self {
            case .accent: return AppTheme.accent
            case .success: return AppTheme.success
            case .warning: return AppTheme.warning
            case .review: return AppTheme.review
            }
        }
    }

    let title: String
    let systemImage: String
    var isLoading: Bool = false
    var style: Style = .prominent
    var tint: Tint = .accent
    var isEnabled: Bool = true
    let action: () -> Void

    @Environment(\.displayScale) private var scale
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(AppTheme.textPrimary)
                } else {
                    Image(systemName: systemImage)
                        .font(scale.font(style == .prominent ? 14 : 13, weight: .semibold))
                }

                Text(isLoading ? loadingTitle : title)
                    .font(scale.font(style == .prominent ? 14 : 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(AppTheme.textPrimary)
            .padding(.horizontal, scale.space(style == .prominent ? 16 : 12))
            .frame(minWidth: scale.space(AppTheme.Control.primaryMinWidth))
            .frame(height: scale.space(
                style == .prominent
                ? AppTheme.Control.primaryHeight
                : AppTheme.Control.secondaryHeight
            ))
            .background(
                Capsule(style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: tint.colors,
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(hovering ? 0.48 : 0.22), lineWidth: 1)
            )
            .scaleEffect(hovering && isEnabled && !isLoading ? 1.02 : 1)
            .shadow(
                color: tint.shadow.opacity(hovering ? 0.32 : 0.22),
                radius: hovering ? 12 : 7,
                x: 0,
                y: 5
            )
            .animation(.easeOut(duration: 0.16), value: hovering)
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading || !isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
        .onHover { inside in
            hovering = inside
        }
        .accessibilityLabel(title)
    }

    private var loadingTitle: String {
        if title.lowercased().contains("scan") { return "Scanning…" }
        if title.lowercased().contains("clean") { return "Cleaning…" }
        return "Working…"
    }
}

/// Secondary control for supporting actions (Force Rescan, Check Updates, Cancel).
/// Lower visual weight than `PrimaryActionButton` so toolbars stay readable at 13".
struct SecondaryActionButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    var role: Role = .neutral
    var isEnabled: Bool = true
    let action: () -> Void

    enum Role {
        case neutral
        case destructive
        case accent

        var foreground: Color {
            switch self {
            case .neutral: return AppTheme.textPrimary
            case .destructive: return AppTheme.review
            case .accent: return AppTheme.accent
            }
        }

        var fill: Color {
            switch self {
            case .neutral: return Color.white.opacity(0.10)
            case .destructive: return AppTheme.review.opacity(0.16)
            case .accent: return AppTheme.accent.opacity(0.16)
            }
        }

        var border: Color {
            switch self {
            case .neutral: return Color.white.opacity(0.14)
            case .destructive: return AppTheme.review.opacity(0.35)
            case .accent: return AppTheme.accent.opacity(0.35)
            }
        }
    }

    @Environment(\.displayScale) private var scale
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(role.foreground)
                } else if let systemImage {
                    Image(systemName: systemImage)
                        .font(scale.font(13, weight: .semibold))
                }
                Text(title)
                    .font(scale.font(13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(role.foreground)
            .padding(.horizontal, scale.space(12))
            .frame(height: scale.space(AppTheme.Control.secondaryHeight))
            .background(
                Capsule(style: .continuous)
                    .fill(role.fill)
                    .overlay(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(hovering ? 0.06 : 0))
                    )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(role.border, lineWidth: 1)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isLoading || !isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
    }
}

/// Compact icon-only toolbar control (settings, project paths, refresh glyph).
struct IconActionButton: View {
    let systemImage: String
    var help: String? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(hovering ? AppTheme.textPrimary : AppTheme.textSecondary)
                .frame(width: AppTheme.Control.iconSize, height: AppTheme.Control.iconSize)
                .background(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                        .fill(Color.white.opacity(hovering ? 0.12 : 0.06))
                )
                .contentShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.45)
        .help(help ?? "")
        .onHover { hovering = $0 }
        .accessibilityLabel(help ?? systemImage)
    }
}
