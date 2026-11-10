import Foundation

/// An installed app matched from a bundle ID.
struct InstalledAppMatch: Equatable, Sendable {
    let id: String
    let name: String
    var url: URL? = nil
}

/// Bundle ID to display name and app location for installed apps.
public struct InstalledAppIndex: Sendable {
    public static let empty = InstalledAppIndex(namesByBundleID: [:])

    private let names: [String: String]
    private let urls: [String: URL]
    private let fallback: (any AppCopyLocating)?
    private let budget: FallbackBudget
    private let fallbackHits = FallbackMemo()

    /// Keys are matched case-insensitively. `fallbackLocator` is asked only for IDs the map lacks,
    /// until `fallbackBudgetSeconds` of lookups in total have been spent.
    public init(
        namesByBundleID: [String: String],
        appURLsByBundleID: [String: URL] = [:],
        fallbackLocator: (any AppCopyLocating)? = nil,
        fallbackBudgetSeconds: TimeInterval = 1
    ) {
        self.budget = FallbackBudget(seconds: fallbackBudgetSeconds)
        var lowered: [String: String] = [:]
        for (id, name) in namesByBundleID { lowered[id.lowercased()] = name }
        self.names = lowered
        self.urls = Dictionary(appURLsByBundleID.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
        self.fallback = fallbackLocator
    }

    /// Scans app folders (one nested level) until `deadline`; never throws, partial on timeout.
    /// An index that found nothing gets no fallback, so a failed load labels the same every time.
    public static func load(
        roots: [URL],
        locator: any AppCopyLocating,
        deadline: Date,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> InstalledAppIndex {
        let expired = { Date() >= deadline || isCancelled() }
        var found: [String: String] = [:]
        var locations: [String: URL] = [:]
        for root in roots {
            for app in appBundles(in: root, expired: expired) {
                if expired() { break }
                if let info = AppBundleInfo.read(app) {
                    found[info.id] = info.name
                    locations[info.id] = app
                }
            }
            if expired() { break }
        }
        return InstalledAppIndex(
            namesByBundleID: found, appURLsByBundleID: locations, fallbackLocator: found.isEmpty ? nil : locator
        )
    }

    public func name(forBundleID id: String) -> String? { match(forBundleID: id)?.name }

    /// The installed app's bundle location, matched like `name(forBundleID:)`.
    public func appURL(forBundleID id: String) -> URL? { match(forBundleID: id)?.url }

    /// Exact ID first, then the longest dot-boundary prefix with at least three components.
    func match(forBundleID id: String) -> InstalledAppMatch? {
        let candidates = Self.candidates(of: id.lowercased())
        for candidate in candidates {
            if let name = names[candidate] { return InstalledAppMatch(id: candidate, name: name, url: urls[candidate]) }
        }
        guard let fallback else { return nil }
        for candidate in candidates {
            if let known = fallbackHits.value(for: candidate) {
                if let hit = known { return hit }
                continue
            }
            guard budget.hasTime else { return nil }
            let found = budget.timed { fallback.appURLs(forBundleID: candidate) }
            // A removed app sits in the Trash and belongs in Other.
            let hit = found.first(where: { !AppUninstaller.isInTrash($0.path) }).map { url in
                InstalledAppMatch(
                    id: candidate, name: AppBundleInfo.read(url)?.name ?? url.deletingPathExtension().lastPathComponent,
                    url: url
                )
            }
            fallbackHits.store(hit, for: candidate)
            if let hit { return hit }
        }
        return nil
    }

    private static func candidates(of id: String) -> [String] {
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, !parts.contains(where: \.isEmpty) else { return [] }
        return stride(from: parts.count, through: 3, by: -1).map { parts.prefix($0).joined(separator: ".") }
    }

    private static func appBundles(in root: URL, expired: () -> Bool) -> [URL] {
        let fm = FileManager.default
        let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles]
        guard let top = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: nil, options: options) else {
            return []
        }
        var apps: [URL] = []
        for url in top {
            if expired() { break }
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

/// Total time the fallback may spend per index; a call that overruns still ends the lookups.
final class FallbackBudget: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: TimeInterval

    init(seconds: TimeInterval) { remaining = seconds }

    var hasTime: Bool { lock.lock(); defer { lock.unlock() }; return remaining > 0 }

    func timed<T>(_ work: () -> T) -> T {
        let start = Date()
        let result = work()
        lock.lock()
        remaining -= Date().timeIntervalSince(start)
        lock.unlock()
        return result
    }
}

/// Locator answers already paid for, so a second lookup of the same ID never spends budget again.
final class FallbackMemo: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [String: InstalledAppMatch?] = [:]

    func value(for id: String) -> InstalledAppMatch?? { lock.lock(); defer { lock.unlock() }; return answers[id] }

    func store(_ match: InstalledAppMatch?, for id: String) { lock.lock(); answers[id] = .some(match); lock.unlock() }
}
