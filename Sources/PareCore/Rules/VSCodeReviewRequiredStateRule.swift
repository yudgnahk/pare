import Foundation

/// VS Code workspace/history state that may hold project-specific data.
/// Does **not** flag installed extensions under `~/.vscode/extensions/` —
/// those are live installs; only duplicate/old versions are handled separately.
public struct VSCodeReviewRequiredStateRule: ScanRule {
    public let id = "vscode-review-required-state"
    public let title = "VS Code State (Review Required)"
    public let reason = "VS Code workspace state or local history (review before removing)"
    public let category: ScanCategory = .developerPackageCaches
    public let riskLevel: RiskLevel = .review
    public let confidence: Double = 0.78

    private let vscodeReviewMarkers = [
        "/library/application support/code/user/workspacestorage",
        "/library/application support/code/user/history",
    ]

    public init() {}

    public func targetDirectories(environment: ScanEnvironment) -> [URL] {
        [
            environment.homeDirectory.appending(path: "Library/Application Support/Code/User/workspaceStorage"),
            environment.homeDirectory.appending(path: "Library/Application Support/Code/User/History"),
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
