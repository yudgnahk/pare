import Foundation

public struct XcodeDerivedDataRule: ScanRule {
    public let id = "xcode-derived-data"
    public let title = "Xcode DerivedData"
    public let category: ScanCategory = .developerBuildArtifacts
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.98

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Developer/Xcode/DerivedData")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        true
    }
}
