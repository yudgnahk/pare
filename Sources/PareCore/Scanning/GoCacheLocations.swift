import Foundation

/// Go's cache directories; nil when `go env` did not report a usable absolute path.
public struct GoCachePaths: Sendable, Equatable {
    public let build: URL?
    public let module: URL?
    /// Roots declared by environment or Go's env file, known without running go.
    public let declared: [URL]

    public static let empty = GoCachePaths(build: nil, module: nil)

    public init(build: URL?, module: URL?, declared: [URL] = []) {
        self.build = build
        self.module = module
        self.declared = declared
    }

    public var all: [URL] { [build, module].compactMap { $0 } + declared }
}

/// `GOCACHE` and `GOMODCACHE` as reported by `go env`, resolved once per process, plus the roots the
/// environment and Go's env file declare, which protect the caches even while go is unconfirmed.
public final class GoCacheLocations: @unchecked Sendable {
    /// Returns raw `go env GOCACHE GOMODCACHE` stdout, or nil when go is absent, failed or timed out.
    public typealias Query = @Sendable () async -> String?

    public static let shared = GoCacheLocations()

    private let query: Query
    private let lock = NSLock()
    private let declared: [URL]
    private var paths: GoCachePaths
    private var resolved = false

    public init(
        query: Query? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) {
        self.query = query ?? Self.defaultQuery
        declared = GoDeclaredCacheRoots.roots(environment: environment, home: home)
        paths = GoCachePaths(build: nil, module: nil, declared: declared)
    }

    /// Snapshot for synchronous policy checks; declared roots only until `resolveIfNeeded()` has run.
    public var resolvedRoots: [URL] {
        lock.withLock { paths.all }
    }

    @discardableResult
    public func resolveIfNeeded() async -> GoCachePaths {
        if let cached = lock.withLock({ resolved ? paths : nil }) { return cached }
        let queried = Self.parse(await query())
        let parsed = GoCachePaths(build: queried.build, module: queried.module, declared: declared)
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

    private static let defaultQuery: Query = { await confirmedQuery(registry: .shared)() }

    /// Runs only the user-confirmed go; unconfirmed behaves as go being absent.
    static func confirmedQuery(registry: ConfirmedToolRegistry) -> Query {
        { await ToolCommandRunner().captureConfirmed(.go, arguments: ["env", "GOCACHE", "GOMODCACHE"], registry: registry) }
    }
}
