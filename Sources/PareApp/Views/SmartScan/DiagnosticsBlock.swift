import SwiftUI
import PareCore

/// Explain-only diagnostics under the hero: what is wrong and what to do, nothing to tick or run.
struct DiagnosticsBlock: View {
    let lines: [DiagnosticLine]

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: scale.space(AppTheme.Spacing.sm)) {
                Text("Needs your attention")
                    .font(scale.font(11, weight: .semibold))
                    .foregroundStyle(AppTheme.textTertiary)
                ForEach(lines) { line in
                    row(line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, scale.space(AppTheme.Spacing.xs))
        }
    }

    private func row(_ line: DiagnosticLine) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: scale.space(AppTheme.Spacing.sm)) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(scale.font(11, weight: .semibold))
                .foregroundStyle(AppTheme.warning)
            (Text(line.headline).foregroundColor(AppTheme.textPrimary)
                + Text(" · ").foregroundColor(AppTheme.textTertiary)
                + Text(line.action).foregroundColor(AppTheme.textSecondary))
                .font(scale.font(12, weight: .medium))
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
struct DiagnosticsBlock_Previews: PreviewProvider {
    static var previews: some View {
        DiagnosticsBlock(lines: [
            DiagnosticLine(id: "/swap", headline: "4.1 GB of swap in use", action: "Restart Chrome", sizeBytes: 4_100_000_000),
            DiagnosticLine(id: "/del", headline: "1.2 GB held by deleted files", action: "Restart node to reclaim the space", sizeBytes: 1_200_000_000),
        ])
        .padding(24)
        .frame(width: 760)
        .background(AppTheme.base)
    }
}
#endif
