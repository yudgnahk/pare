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
        onAddToReview: @escaping (DiskEntry) -> Void
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
        self._tableSortOrder = State(initialValue: [DiskColumnComparator(descriptor: sortOrder.wrappedValue)])
    }

    var body: some View {
        Table(entries, selection: $selection, sortOrder: $tableSortOrder) {
            TableColumn("Name", sortUsing: DiskColumnComparator(field: .name)) { entry in
                nameCell(entry)
            }
            TableColumn("Size", sortUsing: DiskColumnComparator(field: .size)) { entry in
                sizeCell(entry)
            }
            TableColumn("Items", sortUsing: DiskColumnComparator(field: .items)) { entry in
                itemsCell(entry)
            }
            TableColumn("Modified", sortUsing: DiskColumnComparator(field: .modified)) { entry in
                Text(Self.modifiedText(entry.modified))
                    .font(scale.rowMono)
                    .foregroundStyle(AppTheme.textSecondary)
            }
            TableColumn("Kind", sortUsing: DiskColumnComparator(field: .kind)) { entry in
                Text(Self.kindLabel(entry.kind))
                    .font(scale.rowMono)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: String.self) { ids in
            contextMenuContent(for: ids)
        } primaryAction: { ids in
            guard let id = ids.first, let entry = entry(for: id) else { return }
            onOpen(entry)
        }
        .onChange(of: tableSortOrder) { newValue in
            guard let first = newValue.first else { return }
            sortOrder = first.descriptor
        }
        .onChange(of: sortOrder) { newValue in
            tableSortOrder = [DiskColumnComparator(descriptor: newValue)]
        }
    }

    // MARK: - Cells

    private func nameCell(_ entry: DiskEntry) -> some View {
        HStack(spacing: 8) {
            if !entry.isRemainder {
                let style = kindStyle(entry.kind)
                IconTile(symbol: style.symbol, swatch: style.swatch, size: 18)
            }
            Text(entry.name)
                .font(scale.rowTitle)
                .foregroundStyle(entry.isRemainder ? AppTheme.textTertiary : AppTheme.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(entry.name)
        }
    }

    private func sizeCell(_ entry: DiskEntry) -> some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(AppTheme.Fill.subtle)
                        .frame(height: 3)
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(shareBarColor(for: entry))
                        .frame(width: max(3, geo.size.width * shareOfLevel(entry)), height: 3)
                }
            }
            .frame(width: 60, height: 3)

            Text(entry.sizeBytes == 0 ? "—" : ScanReportPresenter.formatBytes(entry.sizeBytes))
                .font(scale.font(13, weight: .semibold, design: .rounded))
                .foregroundStyle(AppTheme.textPrimary)
                .frame(minWidth: 64, alignment: .trailing)
        }
    }

    private func itemsCell(_ entry: DiskEntry) -> some View {
        Text(entry.isDirectory || entry.isRemainder ? "\(entry.itemCount)" : "—")
            .font(scale.rowMono)
            .foregroundStyle(AppTheme.textSecondary)
    }

    private func shareOfLevel(_ entry: DiskEntry) -> Double {
        guard levelTotalBytes > 0 else { return 0 }
        return Double(entry.sizeBytes) / Double(levelTotalBytes)
    }

    private func shareBarColor(for entry: DiskEntry) -> Color {
        let share = shareOfLevel(entry)
        if share > 0.5 { return AppTheme.review }
        if share > 0.25 { return AppTheme.warning }
        return AppTheme.accent
    }

    // MARK: - Context menu

    @ViewBuilder
    private func contextMenuContent(for ids: Set<String>) -> some View {
        let selected = ids.compactMap(entry(for:)).filter { !$0.isRemainder }
        if selected.isEmpty {
            EmptyView()
        } else if let only = selected.first, selected.count == 1 {
            singleSelectionMenu(only)
        } else {
            Button("Add to Review") {
                selected.forEach(onAddToReview)
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
        Button("Add to Review") { onAddToReview(entry) }
    }

    private func entry(for id: String) -> DiskEntry? {
        entries.first { $0.id == id }
    }

    private static func modifiedText(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(Date.FormatStyle(date: .abbreviated, time: .omitted))
    }

    private static func kindLabel(_ kind: DiskKind) -> String {
        switch kind {
        case .folder: return "Folder"
        case .application: return "Application"
        case .image: return "Image"
        case .video: return "Video"
        case .audio: return "Audio"
        case .document: return "Document"
        case .archive: return "Archive"
        case .diskImage: return "Disk Image"
        case .other: return "Other"
        }
    }
}

/// Bridges the table header's tap-to-sort UI to `DiskSortDescriptor`. Reimplements
/// `DiskTableQuery`'s field comparisons (its helpers are private) since `DiskEntry.modified`
/// (`Date?`) isn't `Comparable`, which rules out a plain `KeyPathComparator`.
private struct DiskColumnComparator: SortComparator {
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

    // Delegates to DiskTableQuery, which drives actual row order; this only feeds header sort-indicator state.
    func compare(_ lhs: DiskEntry, _ rhs: DiskEntry) -> ComparisonResult {
        let ascendingResult = DiskTableQuery.primaryOrdering(lhs, rhs, field: field)
        guard ascendingResult != .orderedSame else { return .orderedSame }
        return order == .forward ? ascendingResult : ascendingResult.reversed
    }
}

private extension ComparisonResult {
    var reversed: ComparisonResult {
        switch self {
        case .orderedAscending: return .orderedDescending
        case .orderedDescending: return .orderedAscending
        case .orderedSame: return .orderedSame
        }
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
        DiskEntry.remainder(count: 214, sizeBytes: 40_000_000, in: URL(fileURLWithPath: "/Users/k"))
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
            onAddToReview: { _ in }
        )
        .frame(width: 700, height: 300)
        .background(AppTheme.base)
    }
}
#endif
