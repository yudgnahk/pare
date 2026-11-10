import Foundation

/// The Smart Scan list's top level: familiar domains, in display order.
public enum CleanCategory: Int, CaseIterable, Comparable, Sendable {
    case appCaches, communication, developerTools, projects, aiTools, siteData, oldVersions, system, sizeOnly

    public static func < (lhs: CleanCategory, rhs: CleanCategory) -> Bool { lhs.rawValue < rhs.rawValue }

    public var isSelectable: Bool { self != .sizeOnly }

    /// Where a folder is listed. Nil for diagnostics, which are explained elsewhere.
    /// Order: size only, then projects, then category-fixed domains, then owner traits, then the scan category.
    public static func classify(category: ScanCategory, risk: RiskLevel, owner: FolderOwner) -> CleanCategory? {
        guard let domain = Domain(category) else { return nil }
        switch risk {
        case .advanced: return .sizeOnly
        case .safe, .review: break
        }
        if owner.kind == .project { return .projects }
        switch domain {
        case .leftovers: return .oldVersions
        case .ai: return .aiTools
        case .browser where risk == .review: return .siteData
        case .browser, .app, .logs, .temp, .developer: break
        }
        if owner.traits.contains(.ai) { return .aiTools }
        if owner.traits.contains(.communication) { return .communication }
        switch owner.kind {
        case .macOS: return .system
        case .tool: return .developerTools
        case .app, .project, .other: break
        }
        switch domain {
        case .developer: return .developerTools
        case .temp: return .oldVersions
        case .browser, .app, .logs, .leftovers, .ai: return .appCaches
        }
    }

    /// Scan categories folded into the few distinctions `classify` needs.
    private enum Domain {
        case app, browser, logs, temp, developer, ai, leftovers

        init?(_ category: ScanCategory) {
            switch category {
            case .userCaches, .productivityCaches, .designerCaches, .videoBuilderCaches: self = .app
            case .browserCaches: self = .browser
            case .logsAndCrashReports: self = .logs
            // macOS temp is caught by its owner first; the rest is wrong-platform downloads.
            case .temporaryFiles: self = .temp
            case .developerBuildArtifacts, .developerPackageCaches, .developerSimulatorCaches, .projectArtifacts:
                self = .developer
            case .aiToolCaches: self = .ai
            case .installerFiles, .applications, .deviceBackups, .launchAgents: self = .leftovers
            case .diagnostics: return nil
            }
        }
    }
}
