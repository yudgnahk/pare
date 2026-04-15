import Foundation

public struct TemporaryFilesRule: ScanRule {
    public let id = "temporary-files"
    public let title = "Temporary Files"
    public let category: ScanCategory = .temporaryFiles
    public let riskLevel: RiskLevel = .safe
    public let confidence: Double = 0.9
    private let minimumAgeSeconds: TimeInterval = 24 * 60 * 60

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

        guard matchesTempPath else {
            return false
        }

        if let modified = resourceValues.contentModificationDate {
            return Date().timeIntervalSince(modified) >= minimumAgeSeconds
        }

        return true
    }
}
