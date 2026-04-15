import Foundation

public struct XcodeArchivesRule: ScanRule {
    public let id = "xcode-archives"
    public let title = "Xcode Archives"
    public let category: ScanCategory = .developerBuildArtifacts
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.9

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Developer/Xcode/Archives")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        true
    }
}
