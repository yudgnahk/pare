import SwiftUI
import PareCore

/// Processes that run many copies (MCP servers under each agent) totalled by name, wherever they sit in the tree.
struct ProcessKindStrip: View {
    let kinds: [ProcessKindTotal]
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        GlassCard(padding: AppTheme.Spacing.cardCompact, elevation: .subtle) {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.sm) {
                    Text("Repeated processes")
                        .font(scale.font(13, weight: .semibold))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text("All copies of each, across every branch")
                        .font(scale.rowMeta)
                        .foregroundStyle(AppTheme.textTertiary)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: scale.scaled(210)), spacing: AppTheme.Spacing.sm)],
                    alignment: .leading,
                    spacing: AppTheme.Spacing.sm
                ) {
                    ForEach(kinds) { ProcessKindTile(kind: $0) }
                }
            }
        }
    }
}

private struct ProcessKindTile: View {
    let kind: ProcessKindTotal
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(kind.name)
                    .font(scale.font(12, weight: .semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Text("×\(kind.processCount)")
                    .font(scale.font(12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ProcessFormat.memory(kind.footprintBytes))
                    .font(scale.font(15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textPrimary)
                    .help(ProcessFormat.memoryHelp)
                Text("\(ProcessFormat.memory(kind.residentBytes)) resident")
                    .font(scale.rowMeta)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
                    .help(ProcessFormat.residentHelp)
            }
        }
        .padding(.horizontal, AppTheme.Spacing.sm)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Fill.subtle, in: RoundedRectangle(cornerRadius: AppTheme.Radius.row, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(kind.name), \(kind.processCount) processes, \(ProcessFormat.memory(kind.footprintBytes)) memory, \(ProcessFormat.memory(kind.residentBytes)) resident"
        )
    }
}

#if DEBUG
struct ProcessKindStrip_Previews: PreviewProvider {
    static var previews: some View {
        ProcessKindStrip(kinds: [
            ProcessKindTotal(name: "code-review-graph serve", processCount: 20, footprintBytes: 1_600 << 20, residentBytes: 420 << 20),
            ProcessKindTotal(name: "gitnexus mcp", processCount: 20, footprintBytes: 860 << 20, residentBytes: 310 << 20),
            ProcessKindTotal(name: "Claude Code", processCount: 6, footprintBytes: 2_100 << 20, residentBytes: 980 << 20)
        ])
        .frame(width: 760)
        .padding(24)
        .background(AppTheme.base)
        .previewDisplayName("ProcessKindStrip")
    }
}
#endif
