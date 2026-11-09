import Foundation

/// The `major.minor` of `git --version` output such as `git version 2.54.0 (Apple Git-157)`.
struct GitVersion: Comparable {
    /// `--no-lazy-fetch`, which keeps a scanned repo's promisor remote from being contacted, arrived in 2.45.
    static let noLazyFetchSupport = GitVersion(major: 2, minor: 45)

    let major: Int
    let minor: Int

    init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    init?(output: String) {
        let prefix = "git version "
        guard let line = output.split(whereSeparator: \.isNewline).first, line.hasPrefix(prefix) else { return nil }
        let numbers = line.dropFirst(prefix.count).split(separator: " ").first?.split(separator: ".") ?? []
        guard numbers.count >= 2, let major = Int(numbers[0]), let minor = Int(numbers[1]) else { return nil }
        self.init(major: major, minor: minor)
    }

    static func < (lhs: GitVersion, rhs: GitVersion) -> Bool {
        (lhs.major, lhs.minor) < (rhs.major, rhs.minor)
    }
}

/// Whether a git executable predates `--no-lazy-fetch`, kept for one `statuses(for:)` call so a Command Line Tools update is seen next scan.
final class GitSupportCache: @unchecked Sendable {
    private let lock = NSLock()
    private var tooOld: [String: Bool] = [:]

    func value(for path: String) -> Bool? { lock.withLock { tooOld[path] } }
    func store(_ value: Bool, for path: String) { lock.withLock { tooOld[path] = value } }
}
