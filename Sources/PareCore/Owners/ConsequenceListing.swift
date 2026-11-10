import Foundation

/// One folder row of the consequence list, with the owner that names and icons it.
public struct ConsequenceRow: Identifiable, Equatable, Sendable {
    public let record: FolderRecord
    public let owner: FolderOwner
    public let group: ConsequenceGroup

    public var id: String { record.id }
    /// Path below the project root for project rows (`.next`, `apps/web/dist`), else nil.
    public var projectRelativePath: String? {
        guard let root = owner.projectRoot, record.folderPath.hasPrefix(root + "/") else { return nil }
        return String(record.folderPath.dropFirst(root.count + 1))
    }
    public var isSelectable: Bool { group.isSelectable && record.itemCount > 0 }

    public init(record: FolderRecord, owner: FolderOwner, group: ConsequenceGroup) {
        self.record = record
        self.owner = owner
        self.group = group
    }
}

/// One consequence group: large rows listed, small rows folded, totals over every row.
public struct ConsequenceSection: Identifiable, Equatable, Sendable {
    public let group: ConsequenceGroup
    /// Rows at or above `smallRowMaxBytes`, largest first, capped; the rest are counted in `hiddenRowCount`.
    public let rows: [ConsequenceRow]
    public let hiddenRowCount: Int
    /// Rows under `smallRowMaxBytes`, largest first, capped.
    public let smallRows: [ConsequenceRow]
    public let hiddenSmallRowCount: Int
    /// Selectable row ids, folded and hidden rows included; empty for size-only.
    public let folderIds: Set<String>
    public let safeFolderIds: Set<String>
    public let smallFolderIds: Set<String>
    public let smallSafeFolderIds: Set<String>
    public let totalBytes: Int64
    public let smallBytes: Int64
    public let hasPartialSize: Bool
    public let smallHasPartialSize: Bool

    public var id: ConsequenceGroup { group }
    public var smallRowCount: Int { smallRows.count + hiddenSmallRowCount }
    public var isSelectable: Bool { !safeFolderIds.isEmpty }
}

/// Builds the consequence list from folder records and their owners. Pure; safe off the main actor.
public enum ConsequenceListing {
    /// Rows under this fold into one row per group; decimal MB, as sizes are displayed.
    public static let smallRowMaxBytes: Int64 = 50_000_000
    public static let defaultMaxRowsShown = 100
    static let sizeOnlyIdPrefix = "size-only|"

    /// Display-only folders for `.advanced` findings (never diagnostics); ids never match a selectable folder.
    public static func sizeOnlyRecords(from findings: [ScanFinding]) -> [FolderRecord] {
        struct Acc { var bytes: Int64 = 0; var count = 0; var partial = false }
        var byKey: [String: (category: ScanCategory, path: String, acc: Acc)] = [:]
        for finding in findings where finding.riskLevel == .advanced && finding.category != .diagnostics {
            let path = FolderRollup.rollupFolderPath(for: finding.path)
            let key = "\(sizeOnlyIdPrefix)\(finding.category.rawValue)|\(path)"
            var entry = byKey[key] ?? (finding.category, path, Acc())
            entry.acc.bytes += finding.sizeBytes
            entry.acc.count += 1
            entry.acc.partial = entry.acc.partial || !finding.isSizeComplete
            byKey[key] = entry
        }
        return byKey.map { key, entry in
            FolderRecord(
                id: key, folderPath: entry.path, category: entry.category, bytes: entry.acc.bytes,
                itemCount: entry.acc.count, riskLevel: .advanced, hasPartialSize: entry.acc.partial
            )
        }
    }

    /// One row per record that has a consequence group; a record with no owner is `Other`.
    public static func rows(records: [FolderRecord], owners: [String: FolderOwner]) -> [ConsequenceRow] {
        records.compactMap { record in
            ConsequenceGroup.of(category: record.category, risk: record.riskLevel).map {
                ConsequenceRow(record: record, owner: owners[record.id] ?? .other, group: $0)
            }
        }
    }

    /// Sections in group order; groups with no rows are left out.
    public static func sections(
        rows: [ConsequenceRow],
        maxRowsShown: Int = defaultMaxRowsShown
    ) -> [ConsequenceSection] {
        Dictionary(grouping: rows, by: \.group)
            .map { group, members in makeSection(group, members, cap: max(maxRowsShown, 0)) }
            .sorted { $0.group < $1.group }
    }

    private static func makeSection(_ group: ConsequenceGroup, _ members: [ConsequenceRow], cap: Int) -> ConsequenceSection {
        let sorted = members.sorted {
            $0.record.bytes != $1.record.bytes ? $0.record.bytes > $1.record.bytes : $0.id < $1.id
        }
        let large = sorted.filter { $0.record.bytes >= smallRowMaxBytes }
        let small = sorted.filter { $0.record.bytes < smallRowMaxBytes }
        let selectable = sorted.filter(\.isSelectable)
        let smallSelectable = small.filter(\.isSelectable)
        return ConsequenceSection(
            group: group,
            rows: Array(large.prefix(cap)),
            hiddenRowCount: max(large.count - cap, 0),
            smallRows: Array(small.prefix(cap)),
            hiddenSmallRowCount: max(small.count - cap, 0),
            folderIds: Set(selectable.map(\.id)),
            safeFolderIds: safeIds(selectable),
            smallFolderIds: Set(smallSelectable.map(\.id)),
            smallSafeFolderIds: safeIds(smallSelectable),
            totalBytes: sorted.reduce(0) { $0 + $1.record.bytes },
            smallBytes: small.reduce(0) { $0 + $1.record.bytes },
            hasPartialSize: sorted.contains { $0.record.hasPartialSize },
            smallHasPartialSize: small.contains { $0.record.hasPartialSize }
        )
    }

    private static func safeIds(_ rows: [ConsequenceRow]) -> Set<String> {
        Set(rows.filter { $0.record.riskLevel == .safe }.map(\.id))
    }
}
