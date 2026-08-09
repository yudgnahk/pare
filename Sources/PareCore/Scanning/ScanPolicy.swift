import Foundation

/// Static guardrail layer shared by scanning and cleanup — the ONLY place path
/// safety logic lives (never inline path checks in rules or the engine).
///
/// Split across files (R1.7), all extensions of this one namespace:
///   - `ScanPolicy+Markers.swift`  — marker/name data lists
///   - `ScanPolicy+Safety.swift`   — path safety predicates
///   - `ScanPolicy+Age.swift`      — age thresholds and gates
///   - `ScanPolicy+Platform.swift` — wrong-platform binary/native-tree logic
///   - `ScanPolicy+Docker.swift`   — Docker never-delete policy
///
/// `ScanPolicySnapshotTests` pins the exact contents of every marker collection.
public enum ScanPolicy {
    public static let largeFileThresholdBytes: Int64 = 50 * 1024 * 1024

    public static func isLargeFile(_ bytes: Int64) -> Bool {
        bytes > largeFileThresholdBytes
    }
}
