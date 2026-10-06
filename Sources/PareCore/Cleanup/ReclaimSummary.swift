import Foundation

/// A cleanup's estimated reclaim next to what the disk actually gained, as user-facing text.
public struct ReclaimSummary: Sendable, Equatable {
    public let estimatedBytes: Int64
    /// Free-space delta measured around the cleanup; nil when it was not measured (dry run, old record).
    public let measuredBytes: Int64?

    /// Below this share of the estimate, the space most likely still sits in the Trash on the same disk.
    public static let trashHintRatio = 0.5

    public init(estimatedBytes: Int64, measuredBytes: Int64?) {
        self.estimatedBytes = estimatedBytes
        self.measuredBytes = measuredBytes
    }

    public init(transaction: CleanupTransaction) {
        self.init(estimatedBytes: transaction.totalBytesFreed, measuredBytes: transaction.measuredBytesFreed)
    }

    public var text: String {
        let estimate = "Estimated \(Self.format(estimatedBytes))"
        guard let measured = measuredBytes else { return estimate }
        if measured > 0 { return estimate + " · Disk actually gained \(Self.format(measured))" }
        if measured == 0 { return estimate + " · Disk actually gained nothing" }
        return estimate + " · Disk actually gained nothing (free space fell by \(Self.format(-measured)))"
    }

    public var trashHint: String? {
        guard let measured = measuredBytes, estimatedBytes > 0,
              Double(measured) < Double(estimatedBytes) * Self.trashHintRatio else { return nil }
        return "Items are in the Trash on the same disk — empty the Trash to free the space."
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
