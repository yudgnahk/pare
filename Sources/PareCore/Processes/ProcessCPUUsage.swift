import Foundation

/// CPU % from two samples: CPU time spent between them over the wall time between them.
public enum ProcessCPUUsage {
    /// Percent per process present in both samples; 100 = one full core, as in Activity Monitor.
    public static func percentages(
        previous: [ProcessID: UInt64],
        current: [ProcessID: UInt64],
        elapsedNanos: UInt64
    ) -> [ProcessID: Double] {
        guard elapsedNanos > 0 else { return [:] }
        var result: [ProcessID: Double] = [:]
        for (id, now) in current {
            guard let before = previous[id] else { continue }
            // A counter that went backwards is a reading glitch, not negative work.
            let spent = now >= before ? now - before : 0
            result[id] = Double(spent) / Double(elapsedNanos) * 100
        }
        return result
    }

    /// Sum of the known values; nil when none are known.
    static func sum(_ values: [Double?]) -> Double? {
        let known = values.compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(0, +)
    }
}
