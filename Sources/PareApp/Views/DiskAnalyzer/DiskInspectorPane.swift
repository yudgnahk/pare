import SwiftUI
import PareCore

/// Detail pane for the Disk Analyzer's selected row: hero tile, size, a details grid,
/// and actions gated by the entry's `DiskReviewResolution`.
struct DiskInspectorPane: View {
    let entry: DiskEntry?
    let resolution: DiskReviewResolution
    let formatBytes: (Int64) -> String
    let onReveal: (DiskEntry) -> Void
    let onCopyPath: (DiskEntry) -> Void
    let onAddToReview: (DiskEntry) -> Void
    let onRunSmartScan: () -> Void

    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        Group {
            if let entry {
                ScrollView {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                        hero(entry)
                        Divider().overlay(AppTheme.Hairline.standard)
                        detailsGrid(entry)
                        Divider().overlay(AppTheme.Hairline.standard)
                        actions(entry)
                    }
                    .padding(AppTheme.Spacing.lg)
                }
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppTheme.panelSecondary)
    }

    // MARK: - Empty

    private var emptyState: some View {
        VStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: "sidebar.right")
                .font(scale.font(22))
                .foregroundStyle(AppTheme.textTertiary)
            Text("Select an item to see details.")
                .font(scale.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(AppTheme.Spacing.lg)
    }

    // MARK: - Hero

    private func hero(_ entry: DiskEntry) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            IconTile(
                symbol: DiskKindStyle.symbol(for: entry.kind),
                swatch: DiskKindStyle.swatch(for: entry.kind),
                size: 56
            )

            Text(entry.name)
                .font(scale.font(15, weight: .semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(entry.isSeparateVolume ? "Not sized" : formatBytes(entry.sizeBytes))
                .font(scale.font(20, weight: .bold, design: .rounded))
                .foregroundStyle(AppTheme.accentText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Details grid

    private func detailsGrid(_ entry: DiskEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            detailRow("Items", entry.isSeparateVolume ? "—" : (entry.isDirectory ? "\(entry.itemCount)" : "1"))
            detailRow("Kind", entry.kind.label)
            detailRow("Modified", formattedDate(entry.modified))
            detailRow("Created", formattedDate(entry.creationDate))
            if entry.isSeparateVolume {
                reasonText("This is a separate volume. Open it to measure its size.")
            } else if entry.hasPartialSize {
                reasonText("Some items could not be read. The size shown is partial.")
            }
            detailRow("Location", entry.url.deletingLastPathComponent().path, wraps: true)
        }
    }

    private func detailRow(_ label: String, _ value: String, wraps: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(scale.font(11, weight: .medium))
                .foregroundStyle(AppTheme.textTertiary)
            Text(value)
                .font(scale.caption)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(wraps ? nil : 1)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: wraps)
                .help(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - Actions

    private func actions(_ entry: DiskEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SecondaryActionButton(title: "Reveal in Finder", systemImage: "arrow.right.circle") {
                onReveal(entry)
            }
            SecondaryActionButton(title: "Copy Path", systemImage: "doc.on.doc") {
                onCopyPath(entry)
            }
            reviewAction(entry)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func reviewAction(_ entry: DiskEntry) -> some View {
        switch resolution {
        case .covered:
            SecondaryActionButton(title: "Add to Review", systemImage: "tray.and.arrow.down", role: .accent) {
                onAddToReview(entry)
            }
        case .insideFinding(let finding):
            VStack(alignment: .leading, spacing: 8) {
                reasonText("Covered by a larger \(finding.category.rawValue) finding at \(finding.path).")
                // The parent finding is what gets added, not the selected item — say so explicitly.
                SecondaryActionButton(
                    title: "Add \"\(URL(fileURLWithPath: finding.path).lastPathComponent)\" (\(formatBytes(finding.sizeBytes))) to Review",
                    systemImage: "tray.and.arrow.down",
                    role: .accent
                ) {
                    onAddToReview(entry)
                }
            }
        case .notCandidate:
            reasonText("This item isn't part of any Smart Scan finding.")
        case .noScan:
            SecondaryActionButton(title: "Run Smart Scan", systemImage: "sparkle.magnifyingglass", role: .accent) {
                onRunSmartScan()
            }
        }
    }

    private func reasonText(_ text: String) -> some View {
        Text(text)
            .font(scale.caption)
            .foregroundStyle(AppTheme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
private let previewEntry = DiskEntry(
    id: "/Users/k/Library/Caches/Example",
    url: URL(fileURLWithPath: "/Users/k/Library/Caches/Example"),
    name: "Example Cache Directory With A Fairly Long Name",
    isDirectory: true,
    isPackage: false,
    sizeBytes: 14_900_000_000,
    itemCount: 92_075,
    modified: Date(),
    kind: .folder
)

private let previewFinding = ScanFinding(
    category: .userCaches,
    riskLevel: .safe,
    reason: "Cache older than 30 days",
    path: "/Users/k/Library/Caches",
    sizeBytes: 14_900_000_000,
    lastUsed: nil,
    confidence: 0.9
)

struct DiskInspectorPane_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            pane(.covered([previewFinding]))
                .environment(\.colorScheme, .light)
                .previewDisplayName("Light — Covered")
            pane(.insideFinding(previewFinding))
                .environment(\.colorScheme, .light)
                .previewDisplayName("Light — Inside Finding")
            pane(.noScan)
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Dark — No Scan")
            pane(.notCandidate, entry: nil)
                .environment(\.colorScheme, .dark)
                .previewDisplayName("Dark — Empty")
        }
        .frame(width: 280, height: 520)
    }

    static func pane(_ resolution: DiskReviewResolution, entry: DiskEntry? = previewEntry) -> some View {
        DiskInspectorPane(
            entry: entry,
            resolution: resolution,
            formatBytes: { "\($0 / 1_000_000_000) GB" },
            onReveal: { _ in },
            onCopyPath: { _ in },
            onAddToReview: { _ in },
            onRunSmartScan: {}
        )
    }
}
#endif
