import Foundation

public struct TemporaryFilesRule: ScanRule {
    public let id = "temporary-files"
    public let title = "Temporary Files"
    public let category: ScanCategory = .temporaryFiles
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.9
    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.tempDirectory,
            environment.homeDirectory.appending(path: "Library/Caches/TemporaryItems")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        let path = fileURL.path.lowercased()
        let temporaryMarkers = ["/tmp/", "/temp/", "temporaryitems", "diagnosticreports"]
        let matchesTempPath = temporaryMarkers.contains(where: { path.contains($0) }) || fileURL.lastPathComponent.lowercased().hasPrefix("tmp")

        guard matchesTempPath, ScanPolicy.isLowImpactPath(fileURL) else {
            return false
        }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
