import Foundation

/// What cleaning a row costs the user; the Smart Scan list's top level, in display order.
public enum ConsequenceGroup: Int, CaseIterable, Comparable, Sendable {
    case rebuildsItself, slowerNextBuild, needsALook, sizeOnly

    public static func < (lhs: ConsequenceGroup, rhs: ConsequenceGroup) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Nil for diagnostics, which are explained elsewhere and never listed here.
    public static func of(category: ScanCategory, risk: RiskLevel) -> ConsequenceGroup? {
        guard category != .diagnostics else { return nil }
        switch risk {
        case .review: return .needsALook
        case .advanced: return .sizeOnly
        case .safe: return category.isDeveloperWork ? .slowerNextBuild : .rebuildsItself
        }
    }

    public var isSelectable: Bool { self != .sizeOnly }
}

extension ScanCategory {
    /// Developer caches and build output: cleaning them costs a slower next build.
    public var isDeveloperWork: Bool {
        switch self {
        case .developerBuildArtifacts, .developerPackageCaches, .developerSimulatorCaches, .projectArtifacts:
            return true
        case .userCaches, .temporaryFiles, .logsAndCrashReports, .browserCaches, .designerCaches,
             .videoBuilderCaches, .aiToolCaches, .installerFiles, .applications, .deviceBackups,
             .productivityCaches, .launchAgents, .diagnostics:
            return false
        }
    }
}
