import Foundation
@testable import PareCore

/// Answers every directory with one fixed status (nil = no answer) and records each call.
final class StubGitInspector: GitArtifactInspecting, @unchecked Sendable {
    private let status: GitArtifactStatus?
    private let lock = NSLock()
    private var recorded: [[String]] = []

    init(status: GitArtifactStatus?) {
        self.status = status
    }

    var calls: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func statuses(for directories: [URL]) async -> [String: GitArtifactStatus] {
        lock.lock()
        recorded.append(directories.map(\.path))
        lock.unlock()
        guard let status else { return [:] }
        return Dictionary(directories.map { ($0.path, status) }, uniquingKeysWith: { first, _ in first })
    }
}
