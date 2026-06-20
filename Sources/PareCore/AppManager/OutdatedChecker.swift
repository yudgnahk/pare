import Foundation

/// Checks for available updates via Sparkle (third-party apps) and Mac App Store.
/// Both channels run in parallel; results are merged by bundle ID.
public struct OutdatedChecker: Sendable {

    private static let masLookupBase = "https://itunes.apple.com/lookup"
    private static let networkTimeout: TimeInterval = 10

    public init() {}

    /// Checks all apps for updates. Returns a dictionary of bundleID → UpdateInfo.
    public func checkAll(_ apps: [InstalledApp]) async -> [String: UpdateInfo] {
        let checkable = apps.filter { !$0.isSystemApp && $0.bundleID != nil }

        async let sparkleResults = checkSparkle(checkable)
        async let masResults = checkMAS(checkable.filter { $0.isMAS })

        var combined: [String: UpdateInfo] = [:]
        for (bundleID, info) in await sparkleResults { combined[bundleID] = info }
        for (bundleID, info) in await masResults { combined[bundleID] = info }
        return combined
    }

    // MARK: - Sparkle

    private func checkSparkle(_ apps: [InstalledApp]) async -> [String: UpdateInfo] {
        var results: [String: UpdateInfo] = [:]
        await withTaskGroup(of: (String, UpdateInfo)?.self) { group in
            for app in apps {
                guard let bundleID = app.bundleID else { continue }
                let plistURL = URL(fileURLWithPath: app.path)
                    .appendingPathComponent("Contents/Info.plist")
                guard let plist = NSDictionary(contentsOf: plistURL),
                      let feedURLString = plist["SUFeedURL"] as? String,
                      let feedURL = URL(string: feedURLString) else { continue }

                let installed = app.buildVersion
                group.addTask {
                    guard let available = await Self.fetchSparkleVersion(feedURL: feedURL) else { return nil }
                    return (bundleID, UpdateInfo(
                        bundleID: bundleID,
                        installedVersion: installed,
                        availableVersion: available.version,
                        channel: .sparkle,
                        updateURL: available.downloadURL
                    ))
                }
            }
            for await result in group {
                if let (id, info) = result { results[id] = info }
            }
        }
        return results
    }

    private static func fetchSparkleVersion(feedURL: URL) async -> (version: String, downloadURL: URL?)? {
        var request = URLRequest(url: feedURL, timeoutInterval: networkTimeout)
        request.httpMethod = "GET"
        guard let (data, _) = try? await URLSession.shared.data(for: request) else { return nil }

        let parser = AppcastParser()
        return parser.parse(data)
    }

    // MARK: - Mac App Store

    private func checkMAS(_ apps: [InstalledApp]) async -> [String: UpdateInfo] {
        guard !apps.isEmpty else { return [:] }

        var results: [String: UpdateInfo] = [:]
        let batches = apps.chunked(into: 25)

        await withTaskGroup(of: [(String, UpdateInfo)].self) { group in
            for batch in batches {
                group.addTask {
                    await Self.fetchMASBatch(batch)
                }
            }
            for await batch in group {
                for (id, info) in batch { results[id] = info }
            }
        }
        return results
    }

    private static func fetchMASBatch(_ apps: [InstalledApp]) async -> [(String, UpdateInfo)] {
        let bundleIDs = apps.compactMap { $0.bundleID }
        guard !bundleIDs.isEmpty else { return [] }

        let joined = bundleIDs.joined(separator: ",")
        guard let url = URL(string: "\(masLookupBase)?bundleId=\(joined)&entity=macSoftware&country=us") else {
            return []
        }

        var request = URLRequest(url: url, timeoutInterval: networkTimeout)
        request.httpMethod = "GET"

        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let resultItems = json["results"] as? [[String: Any]] else {
            return []
        }

        var output: [(String, UpdateInfo)] = []
        let appsByID = Dictionary(uniqueKeysWithValues: apps.compactMap { app -> (String, InstalledApp)? in
            guard let id = app.bundleID else { return nil }
            return (id, app)
        })

        for item in resultItems {
            guard let bundleID = item["bundleId"] as? String,
                  let availableVersion = item["version"] as? String,
                  let installedApp = appsByID[bundleID] else { continue }

            let storeID = item["trackId"] as? Int
            let masURL = storeID.flatMap { URL(string: "macappstore://apps.apple.com/app/id\($0)") }

            output.append((bundleID, UpdateInfo(
                bundleID: bundleID,
                installedVersion: installedApp.version,
                availableVersion: availableVersion,
                channel: .mas,
                updateURL: masURL
            )))
        }
        return output
    }
}

// MARK: - Appcast XML Parser

private final class AppcastParser: NSObject, XMLParserDelegate {
    private var currentVersion: String?
    private var currentDownloadURL: URL?
    private var bestVersion: String?
    private var bestDownloadURL: URL?
    private var inItem = false

    func parse(_ data: Data) -> (version: String, downloadURL: URL?)? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        guard let version = bestVersion else { return nil }
        return (version, bestDownloadURL)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String]) {
        if elementName == "item" {
            inItem = true
            currentVersion = nil
            currentDownloadURL = nil
        } else if elementName == "enclosure" && inItem {
            let version = attributes["sparkle:version"] ?? attributes["sparkle:shortVersionString"]
            if let v = version { currentVersion = v }
            if let urlStr = attributes["url"], let url = URL(string: urlStr) {
                currentDownloadURL = url
            }
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        if elementName == "item" && inItem {
            if let v = currentVersion, shouldReplace(candidate: v, best: bestVersion) {
                bestVersion = v
                bestDownloadURL = currentDownloadURL
            }
            inItem = false
        }
    }

    private func shouldReplace(candidate: String, best: String?) -> Bool {
        guard let best else { return true }
        return FileSystemUtils.compareVersionStrings(candidate, best) == .orderedDescending
    }
}

// MARK: - Array chunking helper

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
