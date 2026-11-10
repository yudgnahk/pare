import Foundation

extension FolderRollup {
    /// Donut rows from per-folder records and their owners; never touches individual findings.
    public static func makeToolRollups(
        owners: [String: FolderOwner],
        records: [String: FolderRecord]
    ) -> [ToolRollup] {
        var bytes: [String: Int64] = [:]
        var items: [String: Int] = [:]
        for (id, owner) in owners {
            guard let record = records[id] else { continue }
            bytes[owner.chartLabel, default: 0] += record.bytes
            items[owner.chartLabel, default: 0] += record.itemCount
        }
        var rollups: [AppRollup] = []
        var otherBytes: Int64 = 0
        var otherItems = 0
        for (label, total) in bytes {
            if label == FolderOwner.other.chartLabel || total < minChartSliceBytes {
                otherBytes += total
                otherItems += items[label] ?? 0
            } else {
                rollups.append(AppRollup(app: label, totalBytes: total, fileCount: items[label] ?? 0))
            }
        }
        if otherItems > 0 {
            rollups.append(AppRollup(app: FolderOwner.other.chartLabel, totalBytes: otherBytes, fileCount: otherItems))
        }
        let total = rollups.reduce(Int64(0)) { $0 + $1.totalBytes }
        return rollups
            .sorted { $0.totalBytes != $1.totalBytes ? $0.totalBytes > $1.totalBytes : $0.app < $1.app }
            .map { ToolRollup(rollup: $0, total: total) }
    }

    /// Slices under this size fold into Other, as the per-finding chart did.
    static let minChartSliceBytes: Int64 = 1_048_576

    /// Renames category rows and tool groups to their owner's name, so both browse modes agree.
    public static func relabelingTools(
        _ aggregate: FolderAggregate,
        ownerByFolderId: [String: FolderOwner]
    ) -> FolderAggregate {
        var result = aggregate
        let keys = ownerByFolderId.mapValues(\.key)
        var details: [String: String] = [:]
        for owner in ownerByFolderId.values {
            details[owner.key] = owner.projectRoot.map(abbreviatePath)
        }
        for (category, rows) in aggregate.rowsByCategory {
            let relabeled = rows.map { row in
                ownerByFolderId[row.id].map { row.withToolName($0.displayName) } ?? row
            }
            result.rowsByCategory[category] = relabeled
            result.toolGroupsByCategory[category] = makeToolGroups(
                category: category, rows: relabeled, ownerKeyByFolderId: keys, detailByOwnerKey: details
            )
        }
        return result
    }
}

extension CategoryFolderRow {
    func withToolName(_ name: String) -> CategoryFolderRow {
        CategoryFolderRow(
            id: id, folderPath: folderPath, displayPath: displayPath, totalBytes: totalBytes,
            itemCount: itemCount, riskLevel: riskLevel, isSelectable: isSelectable,
            toolName: name, hasPartialSize: hasPartialSize
        )
    }
}
