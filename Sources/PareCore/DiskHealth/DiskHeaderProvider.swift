import Foundation

/// Reads the disk header breakdown; injectable so the app and tests never depend on the live system.
public protocol DiskHeaderProviding: Sendable {
    func snapshot(volume: URL) async -> DiskHeaderSnapshot
}

/// One bounded `sysctl` and one bounded `tmutil` call, both read-only; each part is nil when its source fails.
public struct SystemDiskHeaderProvider: DiskHeaderProviding {
    public static let commandTimeoutSeconds: TimeInterval = 3

    private let sysctl: @Sendable () async -> String?
    private let tmutil: @Sendable (String) async -> String?
    private let capacity: @Sendable (URL) -> (importantUsage: Int64?, available: Int64?)

    public init() {
        let runner = ToolCommandRunner(timeoutSeconds: Self.commandTimeoutSeconds)
        self.init(
            sysctl: { await runner.capture(executable: URL(fileURLWithPath: "/usr/sbin/sysctl"), arguments: ["vm.swapusage"]) },
            tmutil: { volume in
                await runner.capture(executable: URL(fileURLWithPath: "/usr/bin/tmutil"), arguments: ["listlocalsnapshots", volume])
            },
            capacity: Self.volumeCapacity
        )
    }

    init(
        sysctl: @escaping @Sendable () async -> String?,
        tmutil: @escaping @Sendable (String) async -> String?,
        capacity: @escaping @Sendable (URL) -> (importantUsage: Int64?, available: Int64?)
    ) {
        self.sysctl = sysctl
        self.tmutil = tmutil
        self.capacity = capacity
    }

    public func snapshot(volume: URL) async -> DiskHeaderSnapshot {
        let reading = capacity(volume)
        async let swapOutput = sysctl()
        async let snapshotOutput = tmutil(volume.path)
        return DiskHeaderSnapshot(
            purgeableBytes: DiskHeaderSnapshot.purgeableBytes(importantUsage: reading.importantUsage, available: reading.available),
            swapUsedBytes: await swapOutput.flatMap(SwapUsageParser.usedBytes(fromSysctlOutput:)),
            localSnapshotCount: await snapshotOutput.flatMap(LocalSnapshotParser.count(fromTmutilOutput:))
        )
    }

    /// A fresh URL each call: resource values are cached per URL instance and would repeat the first reading.
    private static let volumeCapacity: @Sendable (URL) -> (importantUsage: Int64?, available: Int64?) = { volume in
        let values = try? URL(fileURLWithPath: volume.path).resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        )
        return (values?.volumeAvailableCapacityForImportantUsage, values?.volumeAvailableCapacity.map(Int64.init))
    }
}
