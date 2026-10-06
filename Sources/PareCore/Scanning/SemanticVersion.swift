import Foundation

/// `major.minor.patch[-prerelease]` with semver precedence (so `10.0.0` > `9.9.9`, `1.0.0-rc.1` < `1.0.0`).
public struct SemanticVersion: Comparable, Hashable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: [String]

    public init?(_ text: String) {
        let parts = text.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
        let core = parts[0].split(separator: ".", omittingEmptySubsequences: false)
        guard core.count == 3, core.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              let major = Int(core[0]), let minor = Int(core[1]), let patch = Int(core[2]) else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = parts.count > 1 ? parts[1].split(separator: ".").map(String.init) : []
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        // A release outranks any prerelease of the same core version.
        if lhs.prerelease.isEmpty || rhs.prerelease.isEmpty { return !lhs.prerelease.isEmpty && rhs.prerelease.isEmpty }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            return precedes(left, right)
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    /// Numeric identifiers compare numerically and rank below alphanumeric ones.
    private static func precedes(_ left: String, _ right: String) -> Bool {
        switch (Int(left), Int(right)) {
        case let (l?, r?): return l < r
        case (.some, nil): return true
        case (nil, .some): return false
        case (nil, nil): return left < right
        }
    }
}

/// A directory name split around its first semver token, e.g. `v18.2.0` → `v` + `18.2.0` + ``.
public struct VersionedName: Hashable, Sendable {
    static let tokenPattern = #"\d+\.\d+\.\d+(-[\w.]+)?"#

    public let prefix: String
    public let token: String
    public let suffix: String
    public let version: SemanticVersion

    public init?(_ name: String) {
        guard let range = name.range(of: Self.tokenPattern, options: .regularExpression),
              let version = SemanticVersion(String(name[range])) else { return nil }
        self.prefix = String(name[..<range.lowerBound])
        self.token = String(name[range])
        self.suffix = String(name[range.upperBound...])
        self.version = version
    }

    /// Names in one sibling group differ only in their version token.
    var groupKey: String { prefix + "\u{0}" + suffix }
}
