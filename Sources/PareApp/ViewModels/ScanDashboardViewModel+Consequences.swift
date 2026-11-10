import Foundation
import PareCore

/// Owner filter chip: one per app, plus one shared chip each for projects and developer tools.
struct OwnerChip: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    /// Icon source; projects and tools use a stand-in owner for their shared symbol.
    let owner: FolderOwner
    /// Reclaimable bytes (size-only rows excluded, as from every total).
    let bytes: Int64
}

// MARK: - Consequence list (groups, owner filter, headers, row copy)

extension ScanDashboardViewModel {
    nonisolated static let primaryChipCount = 6
    nonisolated static let projectsChipId = "projects"
    nonisolated static let toolsChipId = "tools"

    var primaryChips: [OwnerChip] { Array(ownerChips.prefix(Self.primaryChipCount)) }
    var moreChips: [OwnerChip] { Array(ownerChips.dropFirst(Self.primaryChipCount)) }
    var allChipBytes: Int64 { ownerChips.reduce(0) { $0 + $1.bytes } }

    nonisolated static func chipId(for owner: FolderOwner) -> String {
        switch owner.kind {
        case .project: return projectsChipId
        case .tool: return toolsChipId
        case .app, .macOS, .other: return owner.key
        }
    }

    nonisolated static func makeChips(from rows: [ConsequenceRow]) -> [OwnerChip] {
        var bytes: [String: Int64] = [:]
        var owners: [String: FolderOwner] = [:]
        for row in rows {
            let id = chipId(for: row.owner)
            owners[id] = owners[id] ?? chipOwner(id: id, row.owner)
            bytes[id, default: 0] += row.group == .sizeOnly ? 0 : row.record.bytes
        }
        return owners.map { id, owner in
            OwnerChip(id: id, title: owner.displayName, owner: owner, bytes: bytes[id] ?? 0)
        }
        .sorted { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.title < $1.title }
    }

    private nonisolated static func chipOwner(id: String, _ owner: FolderOwner) -> FolderOwner {
        switch id {
        case projectsChipId: return FolderOwner(kind: .project, key: id, displayName: "Projects")
        case toolsChipId: return FolderOwner(kind: .tool, key: id, displayName: "Dev tools")
        default: return owner
        }
    }

    // MARK: Group header

    func consequenceSelectionState(_ section: ConsequenceSection) -> CategorySelectState {
        selection.selectionState(of: section.safeFolderIds)
    }

    func smallRowsSelectionState(_ section: ConsequenceSection) -> CategorySelectState {
        selection.selectionState(of: section.smallSafeFolderIds)
    }

    /// `selected / total` over the visible rows; size-only shows its total alone.
    func consequenceSizeText(_ section: ConsequenceSection) -> String {
        let total = ScanReportPresenter.formatFindingSize(bytes: section.totalBytes, isComplete: !section.hasPartialSize)
        guard section.group.isSelectable else { return total }
        return Self.selectedOfTotal(selected: selection.selectedBytes(inFolders: section.folderIds), total: total)
    }

    /// `2.23 GB / 5.68 GB`; nothing selected reads `0 / 5.68 GB`, not the formatter's "Zero KB".
    static func selectedOfTotal(selected: Int64, total: String) -> String {
        "\(selected > 0 ? ScanReportPresenter.formatBytes(selected) : "0") / \(total)"
    }

    func consequenceSelectHelp(_ section: ConsequenceSection) -> String {
        switch section.group {
        case .needsALook: return "Review items: tick one by one"
        case .sizeOnly: return "Pare won't clean these"
        case .rebuildsItself, .slowerNextBuild:
            return groupHoldReason(safeFolderIds: section.safeFolderIds) ?? "Select safe folders"
        }
    }

    static func consequenceTitle(_ group: ConsequenceGroup) -> String {
        switch group {
        case .rebuildsItself: return "Rebuilds itself"
        case .slowerNextBuild: return "Slower next build"
        case .needsALook: return "Needs a look"
        case .sizeOnly: return "Size only"
        }
    }

    static func consequenceSubtitle(_ group: ConsequenceGroup) -> String {
        switch group {
        case .rebuildsItself: return "Caches and logs. Sign-ins and history stay."
        case .slowerNextBuild: return "Packages and build output. The next build takes longer."
        case .needsALook: return "May sign you out or remove data you want."
        case .sizeOnly: return "Shown for size. Pare won't clean these."
        }
    }

    static func smallRowsTitle(_ count: Int) -> String {
        count == 1 ? "1 small item" : "\(count) small items"
    }

    // MARK: Expansion (size-only starts closed, the rest open)

    func isConsequenceExpanded(_ group: ConsequenceGroup) -> Bool {
        let flipped = selection.flippedConsequenceGroups.contains(Self.expansionId(group))
        return (group != .sizeOnly) != flipped
    }

    func isSmallRowsExpanded(_ group: ConsequenceGroup) -> Bool {
        selection.expandedToolGroups.contains(Self.smallRowsId(group))
    }

    func toggleSmallRowsExpanded(_ group: ConsequenceGroup) {
        toggleExpandedGroup(Self.smallRowsId(group))
    }

    static func expansionId(_ group: ConsequenceGroup) -> String { "consequence|\(group.rawValue)" }
    private static func smallRowsId(_ group: ConsequenceGroup) -> String { "consequence-small|\(group.rawValue)" }

    // MARK: Rows

    /// The selection-facing folder row; size-only rows are never selectable.
    nonisolated static func folderRow(_ row: ConsequenceRow) -> CategoryFolderRow {
        let record = row.record
        return CategoryFolderRow(
            id: record.id, folderPath: record.folderPath, displayPath: FolderRollup.abbreviatePath(record.folderPath),
            totalBytes: record.bytes, itemCount: record.itemCount, riskLevel: record.riskLevel,
            isSelectable: row.isSelectable, toolName: row.owner.displayName, hasPartialSize: record.hasPartialSize
        )
    }

    /// `Chrome · cache`, `shop · .next`; an unknown owner is named by its folder.
    nonisolated static func rowTitle(_ row: ConsequenceRow) -> String {
        if let relative = row.projectRelativePath { return "\(row.owner.displayName) · \(relative)" }
        let name = row.owner.kind == .other
            ? URL(fileURLWithPath: row.record.folderPath).lastPathComponent
            : row.owner.displayName
        return "\(name) · \(CategoryStyle.kindLabel(for: row.record.category, risk: row.record.riskLevel))"
    }

    /// `~/path`, then project activity and why the row is held, when known.
    func rowSubtitle(_ row: ConsequenceRow) -> String {
        let parts = [
            FolderRollup.abbreviatePath(row.record.folderPath),
            projectActivityText(for: row.owner),
            holdReason(forFolderId: row.id),
        ]
        return parts.compactMap { $0 }.joined(separator: " · ")
    }

    func appIconPath(for owner: FolderOwner) -> String? {
        appIconPathByOwnerKey[owner.key]
    }

    // MARK: Decision cards

    /// Safe rows the scan found but bulk cleans leave out (written to or edited recently).
    var heldSafeCount: Int { max(foundCandidateStats.safeCount - candidateStats.safeCount, 0) }

    static func safeCardDetail(count: Int, heldCount: Int) -> String {
        let found = "\(count) items marked Safe"
        guard heldCount > 0 else { return found }
        return found + "\n\(heldCount) held back — used or edited recently"
    }
}
