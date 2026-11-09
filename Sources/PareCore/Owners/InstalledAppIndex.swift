import Foundation

/// An installed app matched from a bundle ID.
struct InstalledAppMatch: Equatable, Sendable {
    let id: String
    let name: String
}

/// Bundle ID to display name for installed apps.
public struct InstalledAppIndex: Sendable {
    public static let empty = InstalledAppIndex(namesByBundleID: [:])

    private let names: [String: String]
    private let fallback: (any AppCopyLocating)?

    /// Keys are matched case-insensitively. `fallbackLocator` is asked only for IDs the map lacks.
    public init(namesByBundleID: [String: String], fallbackLocator: (any AppCopyLocating)? = nil) {
        var lowered: [String: String] = [:]
        for (id, name) in namesByBundleID { lowered[id.lowercased()] = name }
        self.names = lowered
        self.fallback = fallbackLocator
    }

    /// Scans app folders (one nested level) until `deadline`; never throws, partial on timeout.
    public static func load(roots: [URL], locator: any AppCopyLocating, deadline: Date) -> InstalledAppIndex {
        var found: [String: String] = [:]
        for root in roots {
            for app in appBundles(in: root, deadline: deadline) {
                if Date() >= deadline { break }
                if let info = AppBundleInfo.read(app) { found[info.id] = info.name }
            }
            if Date() >= deadline { break }
        }
        return InstalledAppIndex(namesByBundleID: found, fallbackLocator: locator)
    }

    public func name(forBundleID id: String) -> String? { match(forBundleID: id)?.name }

    /// Exact ID first, then the longest dot-boundary prefix with at least three components.
    func match(forBundleID id: String) -> InstalledAppMatch? {
        let candidates = Self.candidates(of: id.lowercased())
        for candidate in candidates {
            if let name = names[candidate] { return InstalledAppMatch(id: candidate, name: name) }
        }
        guard let fallback else { return nil }
        for candidate in candidates {
            if let url = fallback.appURLs(forBundleID: candidate).first {
                let name = AppBundleInfo.read(url)?.name ?? url.deletingPathExtension().lastPathComponent
                return InstalledAppMatch(id: candidate, name: name)
            }
        }
        return nil
    }

    private static func candidates(of id: String) -> [String] {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, !parts.contains(where: \.isEmpty) else { return [] }
        return stride(from: parts.count, through: 3, by: -1).map { parts.prefix($0).joined(separator: ".") }
    }

    private static func appBundles(in root: URL, deadline: Date) -> [URL] {
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        guard let top = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: options) else {
            return []
        }
        var apps: [URL] = []
        for url in top {
            if Date() >= deadline { break }
            if url.pathExtension == "app" {
                apps.append(url)
            } else if let nested = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: options) {
                apps.append(contentsOf: nested.filter { $0.pathExtension == "app" })
            }
        }
        return apps
    }
}

enum AppBundleInfo {
    static func read(_ appURL: URL) -> (id: String, name: String)? {
        let plist = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let id = dict["CFBundleIdentifier"] as? String, !id.isEmpty
        else { return nil }
        let name = (dict["CFBundleDisplayName"] as? String)
            ?? (dict["CFBundleName"] as? String)
            ?? appURL.deletingPathExtension().lastPathComponent
        return (id.lowercased(), name)
    }
}
