import SwiftUI
import PareCore

/// Explain-only diagnostics: what Pare noticed and what the user can do, with nothing to select.
struct DiagnosticNotesCard: View {
    @Environment(\.pareDisplayScale) private var scale
    let notes: [DiagnosticNote]
    @State private var isExpanded = true

    var body: some View {
        GlassCard {
            VStack(spacing: 0) {
                Button(action: { withAnimation(.spring(duration: 0.25)) { isExpanded.toggle() } }) {
                    HStack(spacing: 10) {
                        Image(systemName: CategoryStyle.symbol(for: .diagnostics))
                            .font(scale.font(15, weight: .semibold))
                            .foregroundStyle(CategoryStyle.tint(for: .diagnostics))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Worth Knowing")
                                .font(scale.font(14, weight: .semibold))
                                .foregroundStyle(AppTheme.textPrimary)
                            Text("\(notes.count) note\(notes.count == 1 ? "" : "s") · nothing here is cleaned by Pare")
                                .font(scale.font(11, weight: .medium))
                                .foregroundStyle(AppTheme.textSecondary)
                        }

                        Spacer()

                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(scale.font(10, weight: .semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                }
                .buttonStyle(.plain)

                if isExpanded {
                    Divider().opacity(0.12).padding(.top, 12)
                    VStack(spacing: 8) {
                        ForEach(notes) { noteRow($0) }
                    }
                    .padding(.top, 10)
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
    }

    private func noteRow(_ note: DiagnosticNote) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(note.headline)
                .font(scale.font(12, weight: .medium))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let action = note.action {
                Text(action)
                    .font(scale.font(11, weight: .medium))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
        .help(note.detail)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                .fill(AppTheme.panelSecondary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous)
                        .strokeBorder(AppTheme.warning.opacity(0.15), lineWidth: 1)
                )
        )
    }
}
