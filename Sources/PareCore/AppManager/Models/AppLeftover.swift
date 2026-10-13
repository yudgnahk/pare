import Foundation

public enum AppLeftoverCategory: String, Sendable, CaseIterable {
    case support = "Application Support"
    case caches = "Caches"
    case preferences = "Preferences"
    case logs = "Logs"
    case containers = "Containers"
    case groupContainers = "Group Containers"
    case savedState = "Saved Application State"
    case launchAgents = "Launch Agents"
    case launchDaemons = "Launch Daemons"
    case webkit = "WebKit Storage"
    case httpStorage = "HTTP Storage"
    case cookies = "Cookies"
    case applicationScripts = "Application Scripts"
    case other = "Other"
}

public struct AppLeftover: Identifiable, Sendable {
    public let id = UUID()
    public let path: String
    public let sizeBytes: Int64
    public let category: AppLeftoverCategory
    /// Group containers are shared across app suites — never auto-select.
    public let isGroupContainer: Bool
    /// Ticked when the confirmation sheet opens; ambiguous matches start unticked.
    public let isSelectedByDefault: Bool
    /// Set when Pare only shows the item and will never trash it.
    public let reportOnlyReason: String?

    public var isReportOnly: Bool { reportOnlyReason != nil }

    public init(
        path: String,
        sizeBytes: Int64,
        category: AppLeftoverCategory,
        isGroupContainer: Bool = false,
        isSelectedByDefault: Bool? = nil,
        reportOnlyReason: String? = nil
    ) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.category = category
        self.isGroupContainer = isGroupContainer
        self.isSelectedByDefault = reportOnlyReason == nil && (isSelectedByDefault ?? !isGroupContainer)
        self.reportOnlyReason = reportOnlyReason
    }
}
