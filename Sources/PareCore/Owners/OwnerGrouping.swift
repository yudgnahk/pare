import Foundation

public struct OwnerRow: Identifiable, Equatable, Sendable {
    public let row: CategoryFolderRow
    public let category: ScanCategory
    /// Path relative to the project root, else the `~/` path.
    public let label: String

    public var id: String { row.id }

    public init(row: CategoryFolderRow, category: ScanCategory, label: String) {
        self.row = row
        self.category = category
        self.label = label
    }
}

public struct OwnerGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let owner: FolderOwner
    /// Largest first, capped; the rest are counted in `hiddenRowCount`.
    public let rows: [OwnerRow]
    public let hiddenRowCount: Int
    /// Every folder of the owner, hidden rows included.
    public let folderIds: Set<String>
    public let safeFolderIds: Set<String>
    public let totalBytes: Int64
    public let hasPartialSize: Bool

    public var isSelectable: Bool { !safeFolderIds.isEmpty }
}

public struct OwnerSection: Identifiable, Equatable, Sendable {
    public let kind: OwnerKind
    public let groups: [OwnerGroup]
    public let totalBytes: Int64
    public let hasPartialSize: Bool

    public var id: OwnerKind { kind }
}

/// Groups every folder of an aggregate under its owner. Pure; safe off the main actor.
public enum OwnerGrouping {
    public static let defaultMaxRowsPerGroup = 50

    private struct Bucket {
        var owner: FolderOwner
        var records: [FolderRecord] = []
        var bytes: Int64 = 0
        var partial = false
        var safeIds: Set<String> = []

        mutating func add(_ record: FolderRecord) {
            records.append(record)
            bytes += record.bytes
            partial = partial || record.hasPartialSize
            if record.riskLevel == .safe { safeIds.insert(record.id) }
        }
    }

    public static func build(
        aggregate: FolderAggregate,
        resolver: any OwnerResolving,
        maxRowsPerGroup: Int = defaultMaxRowsPerGroup
    ) -> (sections: [OwnerSection], ownerByFolderId: [String: FolderOwner]) {
        var ownerByPath: [String: FolderOwner] = [:]
        var ownerByFolderId: [String: FolderOwner] = [:]
        var buckets: [String: Bucket] = [:]

        for record in aggregate.recordsByFolderId.values {
            guard record.category != .diagnostics, record.riskLevel != .advanced else { continue }
            let owner: FolderOwner
            if let known = ownerByPath[record.folderPath] {
                owner = known
            } else {
                owner = resolver.owner(forFolderPath: record.folderPath)
                ownerByPath[record.folderPath] = owner
            }
            ownerByFolderId[record.id] = owner
            buckets[owner.key, default: Bucket(owner: owner)].add(record)
        }

        let groups = buckets.values.map { makeGroup($0, cap: maxRowsPerGroup) }
        return (makeSections(groups), ownerByFolderId)
    }

    private static func makeGroup(_ bucket: Bucket, cap: Int) -> OwnerGroup {
        let sorted = bucket.records.sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.id < $1.id }
        let shown = sorted.prefix(max(cap, 0)).map { ownerRow($0, owner: bucket.owner) }
        return OwnerGroup(
            id: "owner|\(bucket.owner.key)",
            owner: bucket.owner,
            rows: shown,
            hiddenRowCount: sorted.count - shown.count,
            folderIds: Set(sorted.map(\.id)),
            safeFolderIds: bucket.safeIds,
            totalBytes: bucket.bytes,
            hasPartialSize: bucket.partial
        )
    }

    private static func ownerRow(_ record: FolderRecord, owner: FolderOwner) -> OwnerRow {
        let row = CategoryFolderRow(
            id: record.id,
            folderPath: record.folderPath,
            displayPath: FolderRollup.abbreviatePath(record.folderPath),
            totalBytes: record.bytes,
            itemCount: record.itemCount,
            riskLevel: record.riskLevel,
            isSelectable: record.itemCount > 0,
            toolName: owner.displayName,
            hasPartialSize: record.hasPartialSize
        )
        return OwnerRow(row: row, category: record.category, label: label(record.folderPath, owner: owner, row: row))
    }

    private static func label(_ path: String, owner: FolderOwner, row: CategoryFolderRow) -> String {
        guard let root = owner.projectRoot, path.hasPrefix(root + "/") else { return row.displayPath }
        return String(path.dropFirst(root.count + 1))
    }

    private static func makeSections(_ groups: [OwnerGroup]) -> [OwnerSection] {
        Dictionary(grouping: groups, by: { $0.owner.kind })
            .map { kind, members in
                let sorted = members.sorted {
                    $0.totalBytes != $1.totalBytes ? $0.totalBytes > $1.totalBytes : $0.id < $1.id
                }
                return OwnerSection(
                    kind: kind,
                    groups: sorted,
                    totalBytes: sorted.reduce(0) { $0 + $1.totalBytes },
                    hasPartialSize: sorted.contains { $0.hasPartialSize }
                )
            }
            .sorted { $0.kind < $1.kind }
    }
}
