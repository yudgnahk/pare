import SwiftUI
import PareCore

/// One outline row: disclosure, name (plus Paseo session details), branch memory, resident memory and CPU.
struct ProcessTreeRowView: View {
    let row: ProcessRow
    let onToggle: () -> Void

    @Environment(\.pareDisplayScale) private var scale
    @State private var isHovered = false

    private var node: ProcessNode { row.node }

    var body: some View {
        // First-line alignment keeps chevron and numbers on the name when a Paseo caption adds lines.
        HStack(alignment: .firstTextBaseline, spacing: AppTheme.Spacing.md) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                disclosure
                nameBlock
            }
            .padding(.leading, CGFloat(row.depth) * scale.space(18))
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(ProcessFormat.memory(node.branchFootprintBytes))
                .font(scale.font(13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .frame(width: ProcessColumns.memory(scale), alignment: .trailing)
            Text(ProcessFormat.memory(node.branchResidentBytes))
                .font(scale.font(13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: ProcessColumns.resident(scale), alignment: .trailing)
            Text(ProcessFormat.cpu(node.branchCPUPercent))
                .font(scale.font(13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: ProcessColumns.cpu(scale), alignment: .trailing)
        }
        .contentShape(Rectangle())
        .onTapGesture { if row.hasChildren { onToggle() } }
        .hoverableRow(isHovered: $isHovered, verticalPadding: scale.space(6))
        .help(helpText)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(row.hasChildren ? .isButton : [])
    }

    @ViewBuilder
    private var disclosure: some View {
        if row.hasChildren {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(scale.font(10, weight: .bold))
                    .foregroundStyle(AppTheme.textSecondary)
                    .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                    .frame(width: scale.space(14), height: scale.space(14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(row.isExpanded ? "Collapse" : "Expand")
        } else {
            Color.clear.frame(width: scale.space(14), height: scale.space(14))
        }
    }

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(node.name)
                    .font(scale.rowTitle)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                if node.executableName != node.name, !node.executableName.isEmpty {
                    Text(node.executableName)
                        .font(scale.font(11, design: .monospaced))
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
                if row.hasChildren {
                    Text("\(node.descendantCount + 1) processes")
                        .font(scale.rowMeta)
                        .foregroundStyle(AppTheme.textTertiary)
                        .lineLimit(1)
                }
                if let status = node.paseoAgent?.lastStatus {
                    Badge(text: status, color: status == "running" ? AppTheme.success : AppTheme.textSecondary)
                }
            }
            if let agent = node.paseoAgent {
                PaseoAgentCaption(agent: agent)
            }
        }
    }

    private var helpText: String {
        let own = "This process: \(ProcessFormat.memory(node.footprintBytes)), \(ProcessFormat.memory(node.residentBytes)) resident, CPU \(ProcessFormat.cpu(node.cpuPercent))"
        guard row.hasChildren else { return own }
        return own + "\nWith its \(node.descendantCount) child processes: \(ProcessFormat.memory(node.branchFootprintBytes)), \(ProcessFormat.memory(node.branchResidentBytes)) resident, CPU \(ProcessFormat.cpu(node.branchCPUPercent))"
    }
}

/// Paseo session title, working folder and last message time under an agent's name.
private struct PaseoAgentCaption: View {
    let agent: PaseoAgentInfo
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let title = agent.title, !title.isEmpty {
                Text(title)
                    .font(scale.rowMeta)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            if !details.isEmpty {
                Text(details)
                    .font(scale.font(11, weight: .regular))
                    .foregroundStyle(AppTheme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private var details: String {
        var parts: [String] = []
        if let cwd = agent.abbreviatedCwd() { parts.append(cwd) }
        if let date = agent.lastUserMessageAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            parts.append("last message " + formatter.localizedString(for: date, relativeTo: Date()))
        }
        return parts.joined(separator: " · ")
    }
}
