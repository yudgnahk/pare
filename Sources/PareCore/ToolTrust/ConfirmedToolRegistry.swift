import Foundation

/// What Settings shows for one tool.
public enum ToolTrustState: Equatable, Sendable {
    case confirmed(path: String)
    /// `changed`: an earlier confirmation no longer matches the file, so it needs confirming again.
    case available(path: String, changed: Bool)
    case rejected(path: String, reason: ToolRejection)
    case notFound(changed: Bool)
}

/// The only way a scan or cleanup gets a third-party tool to launch: a confirmed path whose file is unchanged.
public final class ConfirmedToolRegistry: @unchecked Sendable {
    public static let appBundleIdentifier = "com.yudgnahk.pare"
    /// Scans give up on a Keychain read that waits on a prompt and treat every tool as unconfirmed.
    public static let scanLoadTimeoutSeconds: TimeInterval = 2

    /// Keychain only inside the app bundle; the CLI and tests never run a tool on their own.
    public static let shared = ConfirmedToolRegistry(
        store: Bundle.main.bundleIdentifier == appBundleIdentifier ? KeychainConfirmedToolStore() : NoConfirmedToolStore()
    )

    private let store: any ConfirmedToolStoring
    private let lock = NSLock()
    private var cache: [ConfirmableTool: ConfirmedTool]?
    private var loading = false
    private var waiters: [@Sendable ([ConfirmableTool: ConfirmedTool]) -> Void] = []

    public init(store: any ConfirmedToolStoring) {
        self.store = store
    }

    /// The path to launch for `tool`, or nil when it is unconfirmed, changed, or the store is unreadable.
    public func launchURL(for tool: ConfirmableTool, timeout: TimeInterval = scanLoadTimeoutSeconds) async -> URL? {
        guard let confirmed = await entries(timeout: timeout)[tool], confirmed.isUnchanged else { return nil }
        return URL(fileURLWithPath: confirmed.path)
    }

    public func state(
        for tool: ConfirmableTool,
        environment: [String: String],
        timeout: TimeInterval = scanLoadTimeoutSeconds
    ) async -> ToolTrustState {
        let confirmed = await entries(timeout: timeout)[tool]
        if let confirmed, confirmed.isUnchanged { return .confirmed(path: confirmed.path) }
        let changed = confirmed != nil
        guard let candidate = ToolSearchPath.firstExecutable(named: tool.executableName, environment: environment) else {
            return .notFound(changed: changed)
        }
        switch ToolVetting.vet(path: candidate.path) {
        case .success(let vetted): return .available(path: vetted.path, changed: changed)
        case .failure(let reason): return .rejected(path: candidate.path, reason: reason)
        }
    }

    /// Re-vets `path` and stores it; the stored path is the symlink-resolved one.
    public func confirm(_ tool: ConfirmableTool, path: String) throws -> ConfirmedTool {
        let vetted = try ToolVetting.vet(path: path).get()
        try update { $0[tool] = vetted }
        return vetted
    }

    public func forget(_ tool: ConfirmableTool) throws {
        try update { $0[tool] = nil }
    }

    /// Writes go through a fresh read so a cache that timed out empty never overwrites other confirmations.
    private func update(_ change: (inout [ConfirmableTool: ConfirmedTool]) -> Void) throws {
        var tools = try store.load()
        change(&tools)
        try store.save(tools)
        lock.withLock { cache = tools }
    }

    /// Loaded once per process; a read slower than `timeout` yields nothing for this caller, never a hang.
    func entries(timeout: TimeInterval) async -> [ConfirmableTool: ConfirmedTool] {
        if let cached = lock.withLock({ cache }) { return cached }
        return await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { once.resume([:]) }
            whenLoaded { once.resume($0) }
        }
    }

    private func whenLoaded(_ completion: @escaping @Sendable ([ConfirmableTool: ConfirmedTool]) -> Void) {
        let (cached, start): ([ConfirmableTool: ConfirmedTool]?, Bool) = lock.withLock {
            if let cache { return (cache, false) }
            waiters.append(completion)
            defer { loading = true }
            return (nil, !loading)
        }
        if let cached { return completion(cached) }
        guard start else { return }
        DispatchQueue.global(qos: .utility).async { [self] in
            let loaded = (try? store.load()) ?? [:]
            let pending = lock.withLock {
                cache = loaded
                loading = false
                defer { waiters = [] }
                return waiters
            }
            pending.forEach { $0(loaded) }
        }
    }
}

private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<[ConfirmableTool: ConfirmedTool], Never>?

    init(_ continuation: CheckedContinuation<[ConfirmableTool: ConfirmedTool], Never>) {
        self.continuation = continuation
    }

    func resume(_ value: [ConfirmableTool: ConfirmedTool]) {
        lock.withLock {
            defer { continuation = nil }
            return continuation
        }?.resume(returning: value)
    }
}
