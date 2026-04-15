import Foundation

public enum ScanProfile: String, Sendable {
    case baseline
    case developer
}

public enum RuleCatalog {
    public static func rules(for profile: ScanProfile) -> [any ScanRule] {
        switch profile {
        case .baseline:
            return baseline
        case .developer:
            return developer
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
}
