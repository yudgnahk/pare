import Foundation

/// Samples the current user's processes and keeps what a refresh needs from the last one.
public actor ProcessMonitor {
    /// An older baseline (tab left and reopened) would average CPU over the time away.
    static let maxBaselineAgeNanos: UInt64 = 10_000_000_000

    private let provider: ProcessSnapshotProviding
    private let monotonicNanos: @Sendable () -> UInt64
    private var paseo: PaseoAgentResolver?
    /// Names are derived once per process lifetime, so argv is read once and never stored.
    private var identities: [ProcessID: ProcessIdentity] = [:]
    private var previousCPU: [ProcessID: UInt64] = [:]
    private var previousSampleNanos: UInt64?

    /// `paseo` nil disables Paseo enrichment; the default checks `~/.paseo/agents` on each lookup.
    public init(
        provider: ProcessSnapshotProviding = LibprocProcessSnapshotProvider(),
        paseo: PaseoAgentResolver? = PaseoAgentResolver(),
        monotonicNanos: @escaping @Sendable () -> UInt64 = { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
    ) {
        self.provider = provider
        self.paseo = paseo
        self.monotonicNanos = monotonicNanos
    }

    public func refresh() throws -> ProcessTree {
        let records = try provider.listProcesses()
        let sampledAt = monotonicNanos()

        let liveIDs = Set(records.map(\.id))
        identities = identities.filter { liveIDs.contains($0.key) }
        for record in records where identities[record.id] == nil {
            identities[record.id] = ProcessNamer.identify(
                executablePath: record.executablePath,
                kernelName: record.kernelName,
                arguments: provider.arguments(of: record.id.pid)
            )
        }

        let currentCPU = Dictionary(records.map { ($0.id, $0.cpuTimeNanos) }, uniquingKeysWith: { first, _ in first })
        var cpu: [ProcessID: Double] = [:]
        if let previous = previousSampleNanos, sampledAt &- previous <= Self.maxBaselineAgeNanos {
            cpu = ProcessCPUUsage.percentages(previous: previousCPU, current: currentCPU, elapsedNanos: sampledAt &- previous)
        }
        previousCPU = currentCPU
        previousSampleNanos = sampledAt

        let agents = resolveAgents()
        let inputs = records.compactMap { record -> ProcessTreeBuilder.Input? in
            guard let identity = identities[record.id] else { return nil }
            return ProcessTreeBuilder.Input(
                record: record,
                identity: identity,
                cpuPercent: cpu[record.id],
                paseoAgent: identity.paseoAgentID.flatMap { agents[$0] }
            )
        }
        return ProcessTreeBuilder.build(inputs)
    }

    private func resolveAgents() -> [UUID: PaseoAgentInfo] {
        guard var resolver = paseo else { return [:] }
        let ids = Set(identities.values.compactMap(\.paseoAgentID))
        resolver.retain(only: ids)
        var agents: [UUID: PaseoAgentInfo] = [:]
        for id in ids {
            agents[id] = resolver.resolve(id)
        }
        paseo = resolver
        return agents
    }
}
