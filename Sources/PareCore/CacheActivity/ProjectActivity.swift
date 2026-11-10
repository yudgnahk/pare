import Foundation

/// When a project's files were last edited; an unknown date (budget spent, unreadable) counts as active.
public struct ProjectActivityLabel: Sendable, Equatable {
    public let newestEditDate: Date?

    public init(newestEditDate: Date?) {
        self.newestEditDate = newestEditDate
    }

    public func isActive(now: Date, hotDays: Int = CacheActivityClassifier.defaultHotDays) -> Bool {
        guard let newestEditDate else { return true }
        return CacheActivityClassifier.classify(newestEntryDate: newestEditDate, now: now, hotDays: hotDays) == .hot
    }

    /// `Active today`, `Idle 1 day` or `Idle N days`; nil while the date is unknown.
    public func text(now: Date) -> String? {
        guard let newestEditDate else { return nil }
        let days = max(0, Int(now.timeIntervalSince(newestEditDate) / 86_400))
        switch days {
        case 0: return "Active today"
        case 1: return "Idle 1 day"
        default: return "Idle \(days) days"
        }
    }
}

/// Newest-edit date per project root, within a per-project and an overall time budget.
public enum ProjectActivityLabeler {
    public static let perProjectSeconds: TimeInterval = 2
    public static let totalSeconds: TimeInterval = 8

    /// Newest edit under a project root, or nil when unknown; must stop by the deadline.
    public typealias Probe = @Sendable (_ root: URL, _ deadline: Date) -> Date?

    /// Every root gets a label; roots reached after the overall budget are labelled unknown.
    public static func labels(
        forRoots roots: [String],
        homeDirectory: URL,
        now: @escaping @Sendable () -> Date = { Date() },
        perProjectSeconds: TimeInterval = perProjectSeconds,
        totalSeconds: TimeInterval = totalSeconds,
        probe: Probe? = nil
    ) -> [String: ProjectActivityLabel] {
        let overall = now().addingTimeInterval(totalSeconds)
        let probe = probe ?? { root, deadline in
            ScanPolicy.projectActivityDate(
                projectRoot: root, homeDirectory: homeDirectory,
                timeBudget: perProjectSeconds, deadline: deadline, now: now
            )
        }
        var labels: [String: ProjectActivityLabel] = [:]
        for root in roots where labels[root] == nil {
            guard now() < overall else {
                labels[root] = ProjectActivityLabel(newestEditDate: nil)
                continue
            }
            let deadline = min(overall, now().addingTimeInterval(perProjectSeconds))
            labels[root] = ProjectActivityLabel(newestEditDate: probe(URL(fileURLWithPath: root), deadline))
        }
        return labels
    }
}
