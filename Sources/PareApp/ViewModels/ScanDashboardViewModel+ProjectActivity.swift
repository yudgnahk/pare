import Foundation
import PareCore

// MARK: - Active projects (labels, reasons, confirmation copy)

extension ScanDashboardViewModel {
    /// Project roots in section order (largest first), so the budget goes to the biggest ones.
    func projectRootsForActivity() -> [String] {
        ownerSections.flatMap(\.groups).compactMap { $0.owner.kind == .project ? $0.owner.projectRoot : nil }
    }

    /// Project builds Quick Clean (safe only) or Deep Clean (safe + review) leaves for their own checkbox.
    func heldOutProjectCount(includeReview: Bool) -> Int {
        heldProjectPaths.filter { path in
            guard let risk = selection.riskLevel(for: path) else { return false }
            return risk == .safe || (includeReview && risk == .review)
        }.count
    }

    /// Shown on Quick/Deep Clean when project builds are left out.
    func heldOutProjectNotice(includeReview: Bool) -> String? {
        let count = heldOutProjectCount(includeReview: includeReview)
        guard count > 0 else { return nil }
        let days = CacheActivityClassifier.defaultHotDays
        return count == 1
            ? "1 build is from a project edited in the last \(days) days."
            : "\(count) builds are from projects edited in the last \(days) days."
    }

    static var recentlyEditedReason: String {
        "Edited in the last \(CacheActivityClassifier.defaultHotDays) days"
    }

    /// Why a row starts unticked; nil for rows that are not held.
    func holdReason(forFolderId folderId: String) -> String? {
        let hot = selection.hotPaths(inFolder: folderId)
        guard let sample = hot.sorted().first else { return nil }
        if !hot.isDisjoint(with: heldProjectPaths) { return Self.recentlyEditedReason }
        return cacheActivityText(path: sample) ?? "Written to recently"
    }

    /// Help for a group checkbox whose safe rows are all held; nil otherwise.
    func groupHoldReason(safeFolderIds: Set<String>) -> String? {
        guard !safeFolderIds.isEmpty, safeFolderIds.allSatisfy(selection.isFullyHot) else { return nil }
        let reasons = safeFolderIds.sorted().compactMap(holdReason(forFolderId:))
        guard let reason = reasons.first(where: { $0 == Self.recentlyEditedReason }) ?? reasons.first else { return nil }
        return "Held out: \(reason)"
    }
}
