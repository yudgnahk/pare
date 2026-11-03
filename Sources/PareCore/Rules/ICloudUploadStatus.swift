import Foundation

/// iCloud Drive uploads blocked by a full quota, summarised without file names or subfolders.
public struct ICloudUploadBacklog: Sendable, Equatable {
    public let itemCount: Int
    public let totalBytes: Int64
    public let oldestPendingHours: Double
    /// `Desktop`, `Documents` or `iCloud Drive`, in order of first appearance.
    public let topLevelFolders: [String]
}

/// Loose readers for undocumented `brctl` output: anything unrecognised yields nil rather than a guess.
public enum ICloudUploadStatusParser {
    static let maxPlausibleBytes: Int64 = 100_000_000_000_000
    static let syncedTopLevelFolders: Set<String> = ["Desktop", "Documents"]
    static let otherFolderName = "iCloud Drive"
    static let quotaMarkers = ["pending-quota", "Quota exceeded", "CKErrorDomain:25"]

    private static let bytesPerUnit: [String: Double] = ["bytes": 1, "kb": 1e3, "mb": 1e6, "gb": 1e9, "tb": 1e12]
    private static let quotaPattern = try? NSRegularExpression(
        pattern: #"([0-9][0-9.,]*)\s*(bytes|KB|MB|GB|TB)\s+of quota remaining"#, options: [.caseInsensitive]
    )
    private static let sizePattern = try? NSRegularExpression(pattern: #"sz:[^(\n]*\((\d+)\)"#)
    private static let agePattern = try? NSRegularExpression(pattern: #"last:([0-9.]+)(s|m|h|d) ago"#)

    public static func stripANSI(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]", with: "", options: .regularExpression)
    }

    /// The smallest "<n> <unit> of quota remaining" in `brctl quota` output, in decimal units.
    public static func remainingQuotaBytes(fromQuotaOutput output: String) -> Int64? {
        let amounts = captures(of: quotaPattern, in: stripANSI(output)).compactMap { groups -> Int64? in
            guard groups.count == 2, let multiplier = bytesPerUnit[groups[1].lowercased()] else { return nil }
            // "1,024 bytes" groups digits; "2,3 GB" uses a decimal comma.
            let number = multiplier == 1
                ? Double(groups[0].filter(\.isNumber))
                : Double(groups[0].replacingOccurrences(of: ",", with: "."))
            return number.map { Int64(($0 * multiplier).rounded()) }
        }
        return amounts.min()
    }

    /// Items `brctl status` lists as needing upload and blocked by quota; nil when the output looks unfamiliar.
    public static func backlog(fromStatusOutput output: String) -> ICloudUploadBacklog? {
        let text = stripANSI(output)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let blocked = pendingItems(in: text).filter(\.isQuotaBlocked)
        let sizes = blocked.compactMap(\.bytes)
        guard blocked.isEmpty || !sizes.isEmpty else { return nil }
        let total = sizes.reduce(0, +)
        guard total <= maxPlausibleBytes else { return nil }
        let folders = blocked.map(\.folder).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        return ICloudUploadBacklog(
            itemCount: blocked.count,
            totalBytes: total,
            oldestPendingHours: blocked.compactMap(\.pendingHours).max() ?? 0,
            topLevelFolders: folders
        )
    }

    // MARK: - Items

    private struct PendingItem {
        let folder: String
        let bytes: Int64?
        var isQuotaBlocked = false
        var pendingHours: Double?
    }

    /// An item starts at its `up:needs-upload` line and runs to the next item, folder header or blank line.
    private static func pendingItems(in text: String) -> [PendingItem] {
        var items: [PendingItem] = []
        var current: PendingItem?
        var folder = otherFolderName
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("Under /") || line.contains("up:needs-upload") {
                current.map { items.append($0) }
                current = nil
            }
            if line.hasPrefix("Under /") {
                folder = topLevelFolder(ofHeader: line)
            } else if line.contains("up:needs-upload") {
                current = PendingItem(folder: folder, bytes: captures(of: sizePattern, in: line).first.flatMap { Int64($0[0]) })
            }
            guard var item = current else { continue }
            item.isQuotaBlocked = item.isQuotaBlocked || quotaMarkers.contains { line.contains($0) }
            if let hours = pendingHours(in: line) {
                item.pendingHours = max(item.pendingHours ?? 0, hours)
            }
            current = item
        }
        current.map { items.append($0) }
        return items
    }

    private static func topLevelFolder(ofHeader line: String) -> String {
        let first = line.dropFirst("Under /".count).split(separator: "/").first.map(String.init) ?? ""
        return syncedTopLevelFolders.contains(first) ? first : otherFolderName
    }

    private static func pendingHours(in line: String) -> Double? {
        guard let groups = captures(of: agePattern, in: line).first, let value = Double(groups[0]) else { return nil }
        switch groups[1] {
        case "s": return value / 3600
        case "m": return value / 60
        case "d": return value * 24
        default: return value
        }
    }

    private static func captures(of pattern: NSRegularExpression?, in text: String) -> [[String]] {
        guard let pattern else { return [] }
        let range = NSRange(text.startIndex..., in: text)
        return pattern.matches(in: text, range: range).map { match in
            (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
        }
    }
}
