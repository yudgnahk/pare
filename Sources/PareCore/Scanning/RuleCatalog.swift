import Foundation

public enum ScanProfile: String, Sendable {
    case baseline
    case developer
    case designer
    case videoBuilder = "video-builder"
}

public enum RuleCatalog {
    public static func rules(for profile: ScanProfile) -> [any ScanRule] {
        switch profile {
        case .baseline:
            return baseline
        case .developer:
            return developer
        case .designer:
            return designer
        case .videoBuilder:
            return videoBuilder
        }
    }

    public static var baseline: [any ScanRule] {
        [
            UserCachesRule(),
            TemporaryFilesRule(),
            LogsAndCrashReportsRule(),
            BrowserCachesRule(),
            InstallerFileRule()
        ]
    }

    public static var developer: [any ScanRule] {
        [
            XcodeDerivedDataRule(),
            XcodeArchivesRule(),
            PackageManagerCachesRule(),
            XcodeSimulatorCachesRule(),
            VSCodeCachesRule(),
            VSCodeDuplicateExtensionsRule(),
            VSCodeReviewRequiredStateRule(),
            JetBrainsSafeCachesRule(),
            JetBrainsStaleVersionRule(),
            JetBrainsReviewRequiredRule(),
            WrongPlatformBinariesRule(),
            DockerLogsReviewRequiredRule(),
            AIToolCachesRule(),
            HomebrewCacheRule()
        ] + baseline
    }

    public static var designer: [any ScanRule] {
        [
            DesignerCachesRule(),
            DesignerReviewRequiredMediaRule()
        ] + baseline
    }

    public static var videoBuilder: [any ScanRule] {
        [
            VideoBuilderCachesRule(),
            VideoBuilderReviewRequiredMediaRule()
        ] + baseline
    }

    /// All rules from every profile, deduplicated by rule ID.
    /// Use this for a single unified scan that covers every category.
    public static var all: [any ScanRule] {
        var seen = Set<String>()
        return (developer + designer + videoBuilder).filter { seen.insert($0.id).inserted }
    }
}
