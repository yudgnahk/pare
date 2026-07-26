import SwiftUI

/// Inline dismissible error banner (History, Disk Analyzer). Warning triangle,
/// message, and an optional trailing dismiss control.
struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.warning)

            Text(message)
                .font(scale.caption)
                .foregroundStyle(AppTheme.textPrimary)

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(scale.font(11, weight: .semibold))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss error")
            }
        }
    }
}

#Preview("ErrorBanner") {
    ErrorBanner(message: "Could not load cleanup history.", onDismiss: {})
        .padding(24)
        .background(AppTheme.base)
        .frame(width: 480)
}
