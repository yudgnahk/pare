import SwiftUI
import PareCore

/// Sortable table for one Disk Analyzer level: Name (tile + name), Size (share bar + bytes),
/// Items, Modified and Kind. Drives selection and sort order via bindings so 3.15 can compose it
/// with the breadcrumb/filter bar and inspector.
struct DiskAnalyzerTable: View {
    let entries: [DiskEntry]
    let levelTotalBytes: Int64
    let kindStyle: (DiskKind) -> (symbol: String, swatch: ThemeSwatch)
    let onOpen: (DiskEntry) -> Void
    let onReveal: (DiskEntry) -> Void
    let onCopyPath: (DiskEntry) -> Void
    let onAddToReview: (DiskEntry) -> Void
    let reviewResolution: (DiskEntry) -> DiskReviewResolution

    @Binding var selection: Set<String>
    @Binding var sortOrder: DiskSortDescriptor

    @State private var tableSortOrder: [DiskColumnComparator]
    @Environment(\.pareDisplayScale) private var scale

    init(
        entries: [DiskEntry],
        levelTotalBytes: Int64,
        selection: Binding<Set<String>>,
        sortOrder: Binding<DiskSortDescriptor>,
        kindStyle: @escaping (DiskKind) -> (symbol: String, swatch: ThemeSwatch),
        onOpen: @escaping (DiskEntry) -> Void,
        onReveal: @escaping (DiskEntry) -> Void,
        onCopyPath: @escaping (DiskEntry) -> Void,
        onAddToReview: @escaping (DiskEntry) -> Void,
        reviewResolution: @escaping (DiskEntry) -> DiskReviewResolution
    ) {
        self.entries = entries
        self.levelTotalBytes = levelTotalBytes
        self._selection = selection
        self._sortOrder = sortOrder
        self.kindStyle = kindStyle
        self.onOpen = onOpen
        self.onReveal = onReveal
        self.onCopyPath = onCopyPath
        self.onAddToReview = onAddToReview
        self.reviewResolution = reviewResolution
        self._tableSortOrder = State(initialValue: [DiskColumnComparator(descriptor: sortOrder.wrappedValue)])
    }

    var body: some View {
        Table(entries, selection: $selection, sortOrder: $tableSortOrder) {
            TableColumn("Name", sortUsing: DiskColumnComparator(field: .name)) { entry in
                nameCell(entry)
            }
            .width(min: 150, ideal: 200)
            TableColumn("Size", sortUsing: DiskColumnComparator(field: .size)) { entry in
                sizeCell(entry)
            }
            .width(min: 136, ideal: 150)
            TableColumn("Items", sortUsing: DiskColumnComparator(field: .items)) { entry in
                itemsCell(entry)
            }
            .width(min: 52, ideal: 64)
            TableColumn("Modified", sortUsing: DiskColumnComparator(field: .modified)) { entry in
                Text(Self.modifiedText(entry.modified))
                    .font(scale.caption)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .width(min: 88, ideal: 100)
            TableColumn("Kind", sortUsing: DiskColumnComparator(field: .kind)) { entry in
                Text(entry.kind.label)
                    .font(scale.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .width(min: 64, ideal: 80)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenuContent(for: ids)
        } primaryAction: { ids in
            guard let id = ids.first, let entry = entry(for: id) else { return }
            if entry.isDirectory { onOpen(entry) } else { onReveal(entry) }
        }
        .onChange(of: tableSortOrder) { newValue in
            guard let first = newValue.first else { return }
            if sortOrder != first.descriptor { sortOrder = first.descriptor }
        }
        .onChange(of: sortOrder) { newValue in
            let next = [DiskColumnComparator(descriptor: newValue)]
            if tableSortOrder != next { tableSortOrder = next }
        }
    }

    // MARK: - Cells

    private func nameCell(_ entry: DiskEntry) -> some View {
        HStack(spacing: 8) {
            let style = kindStyle(entry.kind)
            IconTile(symbol: style.symbol, swatch: style.swatch, size: 18)
                .accessibilityHidden(true)
            Text(entry.name)
                .font(scale.rowTitle)
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(entry.name)
        }
    }

    private func sizeCell(_ entry: DiskEntry) -> some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule(style: .continuous)
                        .fill(AppTheme.Fill.control)
                        .frame(height: 4)
                    Capsule(style: .continuous)
                        .fill(shareBarColor(for: entry))
                        .frame(width: max(4, geo.size.width * shareOfLevel(entry)), height: 4)
                }
            }
            .frame(width: 48, height: 4)

            Text(entry.sizeBytes == 0 ? "—" : ScanReportPresenter.formatBytes(entry.sizeBytes))
                .font(scale.font(13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .frame(minWidth: 72, alignment: .trailing)
        }
    }

    private func itemsCell(_ entry: DiskEntry) -> some View {
        Text(entry.isDirectory ? "\(entry.itemCount)" : "—")
            .font(scale.caption)
            .monospacedDigit()
            .foregroundStyle(AppTheme.textSecondary)
    }

    private func shareOfLevel(_ entry: DiskEntry) -> Double {
        guard levelTotalBytes > 0 else { return 0 }
        return Double(entry.sizeBytes) / Double(levelTotalBytes)
    }

    private func shareBarColor(for entry: DiskEntry) -> Color {
        let share = shareOfLevel(entry)
        // Apricot flags the heavyweights without implying danger.
        return share > 0.25 ? AppTheme.warm : AppTheme.accentBright
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenuContent(for ids: Set<String>) -> some View {
        let selected = ids.compactMap(entry(for:))
        if selected.isEmpty {
            EmptyView()
        } else if let only = selected.first, selected.count == 1 {
            singleSelectionMenu(only)
        } else {
            ForEach(selected, id: \.id) { entry in
                reviewMenuItem(entry)
            }
        }
    }

    @ViewBuilder
    private func singleSelectionMenu(_ entry: DiskEntry) -> some View {
        if entry.isDirectory {
            Button("Open") { onOpen(entry) }
        }
        Button("Reveal in Finder") { onReveal(entry) }
        Button("Copy Path") { onCopyPath(entry) }
        Divider()
        reviewMenuItem(entry)
    }

    @ViewBuilder
    private func reviewMenuItem(_ entry: DiskEntry) -> some View {
        switch reviewResolution(entry) {
        case .covered:
            Button("Add to Review") { onAddToReview(entry) }
        case .insideFinding(let finding):
            Button("Add \(URL(fileURLWithPath: finding.path).lastPathComponent) to Review") {
                onAddToReview(entry)
            }
        case .notCandidate:
            Button("Not in Smart Scan") {}.disabled(true)
        case .noScan:
            Button("Run Smart Scan to Review") {}.disabled(true)
        }
    }

    private func entry(for id: String) -> DiskEntry? {
        entries.first { $0.id == id }
    }

    private static func modifiedText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }
}

/// Bridges the table header's tap-to-sort UI to the query's shared ordering logic.
private struct DiskColumnComparator: SortComparator, Equatable {
    var field: DiskSortField
    var order: SortOrder = .forward

    init(field: DiskSortField, order: SortOrder = .forward) {
        self.field = field
        self.order = order
    }

    init(descriptor: DiskSortDescriptor) {
        self.field = descriptor.field
        self.order = descriptor.ascending ? .forward : .reverse
    }

    var descriptor: DiskSortDescriptor {
        DiskSortDescriptor(field: field, ascending: order == .forward)
    }

    static func == (lhs: DiskColumnComparator, rhs: DiskColumnComparator) -> Bool {
        lhs.field == rhs.field && lhs.order == rhs.order
    }

    // Delegates to DiskTableQuery, which drives actual row order; this only feeds header sort-indicator state.
    func compare(_ lhs: DiskEntry, _ rhs: DiskEntry) -> ComparisonResult {
        DiskTableQuery.ordering(lhs, rhs, by: descriptor)
    }
}

#if DEBUG
private enum DiskAnalyzerTablePreviewData {
    static let entries: [DiskEntry] = [
        DiskEntry(
            id: "/Users/k/Library",
            url: URL(fileURLWithPath: "/Users/k/Library"),
            name: "Library",
            isDirectory: true,
            isPackage: false,
            sizeBytes: 11_400_000_000,
            itemCount: 19_458,
            modified: Date(timeIntervalSince1970: 1_757_754_000),
            kind: .folder
        ),
        DiskEntry(
            id: "/Users/k/Movies/vacation-with-a-very-long-descriptive-filename.mov",
            url: URL(fileURLWithPath: "/Users/k/Movies/vacation-with-a-very-long-descriptive-filename.mov"),
            name: "vacation-with-a-very-long-descriptive-filename.mov",
            isDirectory: false,
            isPackage: false,
            sizeBytes: 3_600_000_000,
            itemCount: 0,
            modified: Date(timeIntervalSince1970: 1_758_790_000),
            kind: .video
        ),
    ]

    static func style(for kind: DiskKind) -> (symbol: String, swatch: ThemeSwatch) {
        switch kind {
        case .folder: return ("folder.fill", AppTheme.Swatch.accent)
        case .video: return ("film.fill", AppTheme.Swatch.review)
        default: return ("doc.fill", AppTheme.Swatch.textTertiary)
        }
    }
}

struct DiskAnalyzerTable_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            preview.environment(\.colorScheme, .light).previewDisplayName("Light")
            preview.environment(\.colorScheme, .dark).previewDisplayName("Dark")
        }
    }

    static var preview: some View {
        DiskAnalyzerTable(
            entries: DiskAnalyzerTablePreviewData.entries,
            levelTotalBytes: 15_000_000_000,
            selection: .constant([]),
            sortOrder: .constant(.nameAscending),
            kindStyle: DiskAnalyzerTablePreviewData.style,
            onOpen: { _ in },
            onReveal: { _ in },
            onCopyPath: { _ in },
            onAddToReview: { _ in },
            reviewResolution: { _ in .noScan }
        )
        .frame(width: 700, height: 300)
        .background(AppTheme.base)
    }
}
#endif
