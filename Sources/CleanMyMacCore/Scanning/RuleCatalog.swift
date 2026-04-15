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
            BrowserCachesRule()
        ]
    }

    public static var developer: [any ScanRule] {
        [
            XcodeDerivedDataRule(),
            XcodeArchivesRule(),
            PackageManagerCachesRule(),
            XcodeSimulatorCachesRule()
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
}
