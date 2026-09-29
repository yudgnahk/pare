import Foundation

/// Startup-volume capacity snapshot for the disk rings (read-only).
struct VolumeUsage: Equatable, Sendable {
    let name: String
    let totalBytes: Int64
    let availableBytes: Int64

    var usedBytes: Int64 { max(totalBytes - availableBytes, 0) }

    var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }

    /// Share of the whole disk that `bytes` represents, clamped to what is actually used.
    func fraction(of bytes: Int64) -> Double {
        guard totalBytes > 0 else { return 0 }
        return Double(min(bytes, usedBytes)) / Double(totalBytes)
    }
}

@MainActor
final class VolumeUsageModel: ObservableObject {
    @Published private(set) var usage: VolumeUsage?

    private let volumeURL: URL

    init(volumeURL: URL = URL(fileURLWithPath: "/")) {
        self.volumeURL = volumeURL
    }

    /// Cheap metadata read; safe to call on appear and after scans/cleanups.
    func refresh() {
        let keys: Set<URLResourceKey> = [
            .volumeLocalizedNameKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]
        guard let values = try? volumeURL.resourceValues(forKeys: keys),
              let total = values.volumeTotalCapacity else {
            usage = nil
            return
        }
        let available = values.volumeAvailableCapacityForImportantUsage ?? 0
        usage = VolumeUsage(
            name: values.volumeLocalizedName ?? "Macintosh HD",
            totalBytes: Int64(total),
            availableBytes: available
        )
    }
}
