import Foundation

/// Go's cache directories; nil when `go env` did not report a usable absolute path.
public struct GoCachePaths: Sendable, Equatable {
    public let build: URL?
    public let module: URL?

    public static let empty = GoCachePaths(build: nil, module: nil)

    public var all: [URL] { [build, module].compactMap { $0 } }
}

/// `GOCACHE` and `GOMODCACHE` as reported by `go env`, resolved once per process.
/// Without `go` (or on any failure) there are no custom roots and the default spellings still apply.
public final class GoCacheLocations: @unchecked Sendable {
    /// Returns raw `go env GOCACHE GOMODCACHE` stdout, or nil when go is absent, failed or timed out.
    public typealias Query = @Sendable () async -> String?

    public static let shared = GoCacheLocations()

    /// The official installer's location, which Finder-launched apps do not get on PATH.
    static let officialInstallBinDirectory = "/usr/local/go/bin"

    private let query: Query
    private let lock = NSLock()
    private var paths: GoCachePaths = .empty
    private var resolved = false

    public init(query: Query? = nil) {
        self.query = query ?? Self.defaultQuery
    }

    /// Snapshot for synchronous policy checks; empty until `resolveIfNeeded()` has run.
    public var resolvedRoots: [URL] {
        lock.withLock { paths.all }
    }

    @discardableResult
    public func resolveIfNeeded() async -> GoCachePaths {
        if let cached = lock.withLock({ resolved ? paths : nil }) { return cached }
        let parsed = Self.parse(await query())
        lock.withLock {
            paths = parsed
            resolved = true
        }
        return parsed
    }

    /// Line 1 is `GOCACHE`, line 2 `GOMODCACHE`; empty, relative (`off`) and root values become nil.
    static func parse(_ output: String?) -> GoCachePaths {
        let lines = (output ?? "")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        func path(at index: Int) -> URL? {
            guard index < lines.count, lines[index].hasPrefix("/"), lines[index] != "/" else { return nil }
            return URL(fileURLWithPath: lines[index]).standardizedFileURL
        }
        return GoCachePaths(build: path(at: 0), module: path(at: 1))
    }

    private static let defaultQuery: Query = {
        let runner = ToolCommandRunner()
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = [environment["PATH"], officialInstallBinDirectory]
            .compactMap { $0 }
            .joined(separator: ":")
        guard let go = runner.resolveExecutable(named: "go", environmentVariables: environment) else { return nil }
        return await runner.capture(executable: go, arguments: ["env", "GOCACHE", "GOMODCACHE"])
    }
}
