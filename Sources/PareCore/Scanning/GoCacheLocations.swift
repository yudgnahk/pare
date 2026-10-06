import Foundation

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
    private var roots: [URL] = []
    private var resolved = false

    public init(query: Query? = nil) {
        self.query = query ?? Self.defaultQuery
    }

    /// Snapshot for synchronous policy checks; empty until `resolveIfNeeded()` has run.
    public var resolvedRoots: [URL] {
        lock.withLock { roots }
    }

    @discardableResult
    public func resolveIfNeeded() async -> [URL] {
        if let cached = lock.withLock({ resolved ? roots : nil }) { return cached }
        let parsed = Self.parse(await query())
        lock.withLock {
            roots = parsed
            resolved = true
        }
        return parsed
    }

    /// One path per line; empty, relative (`off`) and root values are dropped.
    static func parse(_ output: String?) -> [URL] {
        (output ?? "")
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") && $0 != "/" }
            .map { URL(fileURLWithPath: $0).standardizedFileURL }
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
