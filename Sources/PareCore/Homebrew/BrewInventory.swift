import Foundation

/// Fetches all installed Homebrew formulae and casks via `brew info --json=v2 --installed`.
public actor BrewInventory {

    public init() {}

    /// Returns (formulae, casks). Throws if Homebrew is not installed.
    public func scan(showAll: Bool = false) async throws -> (formulae: [BrewFormula], casks: [BrewCask]) {
        let output = try await BrewRunner.shared.run(["info", "--json=v2", "--installed"])
        guard let data = output.data(using: .utf8) else {
            return ([], [])
        }
        return try parse(data: data, showAll: showAll)
    }

    // MARK: - Private

    private func parse(data: Data, showAll: Bool) throws -> (formulae: [BrewFormula], casks: [BrewCask]) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ([], [])
        }

        let formulae = parseFormulae(root["formulae"] as? [[String: Any]] ?? [], showAll: showAll)
        let casks = parseCasks(root["casks"] as? [[String: Any]] ?? [])
        return (formulae, casks)
    }

    private func parseFormulae(_ items: [[String: Any]], showAll: Bool) -> [BrewFormula] {
        items.compactMap { item -> BrewFormula? in
            guard let name = item["name"] as? String,
                  let installedList = item["installed"] as? [[String: Any]],
                  let first = installedList.first,
                  let version = first["version"] as? String else { return nil }

            let installedOnRequest = first["installed_on_request"] as? Bool ?? true
            guard showAll || installedOnRequest else { return nil }

            let pinned = item["pinned"] as? Bool ?? false
            let deps = item["dependencies"] as? [String] ?? []
            let desc = item["desc"] as? String ?? ""

            var installDate: Date?
            if let timestamp = first["time"] as? TimeInterval {
                installDate = Date(timeIntervalSince1970: timestamp)
            }

            return BrewFormula(
                name: name,
                desc: desc,
                version: version,
                installedOnRequest: installedOnRequest,
                pinned: pinned,
                installDate: installDate,
                dependencies: deps
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func parseCasks(_ items: [[String: Any]]) -> [BrewCask] {
        items.compactMap { item -> BrewCask? in
            guard let token = item["token"] as? String,
                  let version = item["version"] as? String else { return nil }

            let autoUpdates = item["auto_updates"] as? Bool ?? false

            var appNames: [String] = []
            if let artifacts = item["artifacts"] as? [[String: Any]] {
                for artifact in artifacts {
                    if let apps = artifact["app"] as? [String] {
                        appNames.append(contentsOf: apps)
                    }
                }
            }

            var installDate: Date?
            if let timestamp = item["installed_time"] as? TimeInterval {
                installDate = Date(timeIntervalSince1970: timestamp)
            }

            return BrewCask(
                token: token,
                version: version,
                autoUpdates: autoUpdates,
                installedAppNames: appNames,
                installDate: installDate
            )
        }
        .sorted { $0.token.localizedCaseInsensitiveCompare($1.token) == .orderedAscending }
    }
}
