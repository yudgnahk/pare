import SwiftUI

/// Consistent page header for secondary modules (Apps, Homebrew, etc.).
struct ModuleChrome<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil
    @ViewBuilder var content: () -> Content

    @Environment(\.displayScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if let systemImage {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.accent.opacity(0.14))
                            .frame(width: 40, height: 40)
                        Image(systemName: systemImage)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(AppTheme.accent)
                    }
                    .transition(.scale.combined(with: .opacity))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(scale.pageTitle)
                        .foregroundStyle(AppTheme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(scale.caption)
                            .foregroundStyle(AppTheme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, AppTheme.Spacing.pageHorizontal)
            .padding(.top, AppTheme.Spacing.pageVertical)
            .padding(.bottom, AppTheme.Spacing.md)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
