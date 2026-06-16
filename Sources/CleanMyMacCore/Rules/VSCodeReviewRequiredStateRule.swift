import Foundation

public struct VSCodeReviewRequiredStateRule: ScanRule {
    public let id = "vscode-review-required-state"
    public let title = "VS Code State and Extensions (Review Required)"
    public let reason = "VS Code workspace state or extension data (review before removing)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.78

    private let vscodeReviewMarkers = [
        "/library/application support/code/user/workspacestorage",
        "/library/application support/code/user/history",
        "/.vscode/extensions/"
    ]

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Application Support/Code/User"),
            environment.homeDirectory.appending(path: ".vscode/extensions")
        ]
    }

    public func include(fileURL: URL, resourceValues: URLResourceValues) -> Bool {
        let path = fileURL.path.lowercased()

        let hasVscodeReviewMarker = vscodeReviewMarkers.contains { path.contains($0) }
        guard hasVscodeReviewMarker else {
            return false
        }

        guard ScanPolicy.matchesPersonaPath(fileURL, allowedMarkers: ScanPolicy.developerReviewPathMarkers) else {
            return false
        }

        let hasExcludedMarker = ScanPolicy.developerReviewExclusionMarkers.contains { path.contains($0) }
        guard !hasExcludedMarker else {
            return false
        }

        return ScanPolicy.passesMinimumAge(
            for: resourceValues,
            minimumAgeSeconds: ScanPolicy.defaultMinimumAgeSeconds(for: category)
        )
    }
}
