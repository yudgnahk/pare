import SwiftUI
import PareCore

/// Project group header: name, then the project folder and, once known, its activity.
struct ProjectGroupHeader: View {
    let group: OwnerGroup
    let sizeText: String
    let isExpanded: Bool
    let selection: TriSelectionState
    let activityText: String?
    let selectHelp: String
    let onToggleSelect: () -> Void
    let onToggleExpand: () -> Void
    @Environment(\.pareDisplayScale) private var scale

    var body: some View {
        DisclosureSelectRow(
            style: .category,
            title: group.owner.displayName,
            subtitle: Self.meta(root: group.owner.projectRoot, activity: activityText),
            badgeText: ScanDashboardViewModel.folderBadge(group.folderIds.count),
            sizeText: sizeText,
            isExpanded: isExpanded,
            selection: selection,
            isSelectable: group.isSelectable,
            selectHelp: selectHelp,
            onToggleSelect: onToggleSelect,
            onToggleExpand: onToggleExpand
        ) {
            OwnerGroupSection.icon(for: group.owner, scale: scale)
        }
    }

    /// `~/Code/shop · Active today`; the activity part is omitted until it is known.
    static func meta(root: String?, activity: String?) -> String? {
        guard let root else { return nil }
        let path = FolderRollup.abbreviatePath(root)
        guard let activity else { return path }
        return "\(path) · \(activity)"
    }
}
