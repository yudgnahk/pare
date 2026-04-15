import SwiftUI

struct TopFileRow: View {
    let path: String
    let category: String
    let sizeText: String
    let confidenceText: String
    let lastUsedText: String
    let confidenceColor: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(AppTheme.panelSecondary)
                    .frame(width: 34, height: 34)

                Image(systemName: "doc.fill")
                    .foregroundStyle(AppTheme.accent)
                    .font(.system(size: 14, weight: .medium))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(path)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(category)
                    Text("•")
                    Text(lastUsedText)
                }
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 4) {
                Text(sizeText)
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.textPrimary)

                Text(confidenceText)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(confidenceColor.opacity(0.24), in: Capsule(style: .continuous))
                    .foregroundStyle(confidenceColor)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(AppTheme.panelSecondary.opacity(0.76))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}
