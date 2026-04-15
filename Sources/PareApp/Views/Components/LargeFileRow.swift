import SwiftUI

struct LargeFileRow: View {
    let path: String
    let sizeText: String
    let lastUsedText: String
    let canReveal: Bool
    let onReveal: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(path)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(sizeText)
                    Text("•")
                    Text(lastUsedText)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 10)

            Button("Show in Finder", action: onReveal)
                .buttonStyle(.borderedProminent)
                .tint(AppTheme.accent)
                .disabled(!canReveal)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.panelSecondary.opacity(0.7))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
