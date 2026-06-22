import Foundation

/// Checks for outdated Homebrew packages via `brew outdated --json=v2 --greedy`.
public struct BrewOutdatedChecker: Sendable {

    public init() {}

    /// Returns all outdated packages. Pinned packages are included but marked.
    public func check() async throws -> [BrewOutdatedPackage] {
        let output = try await BrewRunner.shared.run(["outdated", "--json=v2", "--greedy"])
        guard let data = output.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var packages: [BrewOutdatedPackage] = []
        packages += parseFormulae(root["formulae"] as? [[String: Any]] ?? [])
        packages += parseCasks(root["casks"] as? [[String: Any]] ?? [])
        return packages.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Private

    private func parseFormulae(_ items: [[String: Any]]) -> [BrewOutdatedPackage] {
        items.compactMap { item -> BrewOutdatedPackage? in
            guard let name = item["name"] as? String,
                  let current = item["current_version"] as? String else { return nil }

            let installed: [String]
            if let arr = item["installed_versions"] as? [String] {
                installed = arr
            } else if let single = item["installed_versions"] as? String {
                installed = [single]
            } else {
                installed = []
            }

            let pinned = item["pinned"] as? Bool ?? false

            return BrewOutdatedPackage(
                name: name,
                installedVersions: installed,
                currentVersion: current,
                pinned: pinned,
                isAutoUpdate: false,
                isFormula: true
            )
        }
    }

    private func parseCasks(_ items: [[String: Any]]) -> [BrewOutdatedPackage] {
        items.compactMap { item -> BrewOutdatedPackage? in
            guard let name = item["name"] as? String,
                  let current = item["current_version"] as? String else { return nil }

            let installed: [String]
            if let arr = item["installed_versions"] as? [String] {
                installed = arr
            } else if let single = item["installed_versions"] as? String {
                installed = [single]
            } else {
                installed = []
            }

            let autoUpdates = item["auto_updates"] as? Bool ?? false

            return BrewOutdatedPackage(
                name: name,
                installedVersions: installed,
                currentVersion: current,
                pinned: false,
                isAutoUpdate: autoUpdates,
                isFormula: false
            )
        }
    }
}
