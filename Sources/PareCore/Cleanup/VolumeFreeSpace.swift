import Foundation

/// One reading of a volume's free space.
public struct VolumeFreeSpace: Sendable, Equatable {
    /// What Finder reports: includes purgeable space the system frees on demand.
    public let importantUsageBytes: Int64?
    /// Space free right now, purgeable excluded.
    public let availableBytes: Int64?

    public init(importantUsageBytes: Int64?, availableBytes: Int64?) {
        self.importantUsageBytes = importantUsageBytes
        self.availableBytes = availableBytes
    }
}

/// Reads a volume's free space; injectable so cleanup tests use canned readings.
public protocol VolumeFreeSpaceProviding: Sendable {
    func freeSpace(forVolumeContaining url: URL) -> VolumeFreeSpace?
}

public struct SystemVolumeFreeSpace: VolumeFreeSpaceProviding {
    public init() {}

    public func freeSpace(forVolumeContaining url: URL) -> VolumeFreeSpace? {
        // A fresh URL each call: resource values are cached per URL instance and would repeat the first reading.
        let fresh = URL(fileURLWithPath: url.path)
        guard let values = try? fresh.resourceValues(
            forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey]
        ) else { return nil }
        let reading = VolumeFreeSpace(
            importantUsageBytes: values.volumeAvailableCapacityForImportantUsage,
            availableBytes: values.volumeAvailableCapacity.map(Int64.init)
        )
        return reading.importantUsageBytes == nil && reading.availableBytes == nil ? nil : reading
    }
}
