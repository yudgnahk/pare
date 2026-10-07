import XCTest
@testable import PareCore

/// The disk header's secondary line: purgeable space, swap and APFS local snapshots next to free space.
final class DiskHeaderTests: XCTestCase {

    private let mib: Int64 = 1024 * 1024

    func testSwapUsageParser() {
        let cases: [(name: String, output: String, used: Int64?)] = [
            ("sysctl -n format", "total = 2048.00M  used = 1031.25M  free = 1016.75M  (encrypted)", Int64(1031.25 * 1024 * 1024)),
            ("with key prefix", "vm.swapusage: total = 8192.00M  used = 6656.00M  free = 1536.00M  (encrypted)", 6656 * mib),
            ("gigabytes", "total = 10.00G  used = 6.50G  free = 3.50G  (encrypted)", Int64(6.5 * 1024 * 1024 * 1024)),
            ("kilobytes", "total = 1024.00K  used = 512.00K  free = 512.00K", 512 * 1024),
            ("no swap in use", "total = 0.00M  used = 0.00M  free = 0.00M  (encrypted)", 0),
            ("comma decimal locale", "total = 8192,00M  used = 4908,88M  free = 3283,12M  (encrypted)", Int64((4908.88 * 1024 * 1024).rounded())),
            ("garbage", "sysctl: unknown oid 'vm.swapusage'", nil),
            ("empty", "", nil),
            ("unknown unit", "total = 1.00X  used = 1.00X  free = 0.00X", nil),
        ]
        for testCase in cases {
            XCTAssertEqual(SwapUsageParser.usedBytes(fromSysctlOutput: testCase.output), testCase.used, testCase.name)
        }
    }

    func testLocalSnapshotCountParser() {
        let listing = """
        Snapshots for disk /:
        com.apple.TimeMachine.2026-10-07-101112.local
        com.apple.TimeMachine.2026-10-07-111213.local
        com.apple.os.update-4F5E3D2C1B0A
        """
        let cases: [(name: String, output: String, count: Int?)] = [
            ("snapshot names", listing, 3),
            ("older format without header", "com.apple.TimeMachine.2019-01-01-000000", 1),
            ("header only", "Snapshots for disk /:", 0),
            ("volume-group header", "Snapshots for volume group containing disk /:\ncom.apple.TimeMachine.2026-10-07-101112.local", 1),
            ("third-party snapshot", "Snapshots for disk /:\ncom.bombich.ccc.2026-10-07-101112", 1),
            ("no local snapshots", "No local snapshots found", 0),
            ("empty", "", 0),
            ("error text", "Failed to list snapshots: Operation not permitted", nil),
            ("garbage", "something unexpected\nmore text", nil),
        ]
        for testCase in cases {
            XCTAssertEqual(LocalSnapshotParser.count(fromTmutilOutput: testCase.output), testCase.count, testCase.name)
        }
    }

    func testPurgeableIsClampedAtZero() {
        let cases: [(important: Int64?, available: Int64?, purgeable: Int64?)] = [
            (100, 60, 40),
            (60, 60, 0),
            (50, 60, 0),
            (nil, 60, nil),
            (100, nil, nil),
        ]
        for testCase in cases {
            XCTAssertEqual(
                DiskHeaderSnapshot.purgeableBytes(importantUsage: testCase.important, available: testCase.available),
                testCase.purgeable,
                "\(String(describing: testCase.important)) − \(String(describing: testCase.available))"
            )
        }
    }

    func testDetailLineHidesNilAndZeroParts() {
        func format(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
        let gb: Int64 = 1_000_000_000
        let cases: [(name: String, snapshot: DiskHeaderSnapshot, line: String?)] = [
            ("all parts", DiskHeaderSnapshot(purgeableBytes: 3 * gb, swapUsedBytes: 6 * gb, localSnapshotCount: 4),
             "Purgeable \(format(3 * gb)) · Swap \(format(6 * gb)) · 4 local snapshots"),
            ("one snapshot", DiskHeaderSnapshot(purgeableBytes: nil, swapUsedBytes: nil, localSnapshotCount: 1),
             "1 local snapshot"),
            ("zeros hidden", DiskHeaderSnapshot(purgeableBytes: 0, swapUsedBytes: gb, localSnapshotCount: 0),
             "Swap \(format(gb))"),
            ("nothing to show", DiskHeaderSnapshot(purgeableBytes: 0, swapUsedBytes: nil, localSnapshotCount: nil), nil),
        ]
        for testCase in cases {
            XCTAssertEqual(testCase.snapshot.detailLine, testCase.line, testCase.name)
        }
    }

    func testSwapPressureWarningThreshold() {
        let gb: Int64 = 1_000_000_000
        let cases: [(name: String, swap: Int64?, free: Int64, warns: Bool)] = [
            ("heavy swap, low disk", 5 * gb, 8 * gb, true),
            ("heavy swap, plenty of disk", 5 * gb, 50 * gb, false),
            ("light swap, low disk", 2 * gb, 8 * gb, false),
            ("at both thresholds", DiskHeaderSnapshot.swapWarningBytes, DiskHeaderSnapshot.lowFreeSpaceWarningBytes, false),
            ("swap unknown", nil, 1 * gb, false),
        ]
        for testCase in cases {
            let snapshot = DiskHeaderSnapshot(purgeableBytes: nil, swapUsedBytes: testCase.swap, localSnapshotCount: nil)
            XCTAssertEqual(snapshot.warnsOfSwapPressure(freeBytes: testCase.free), testCase.warns, testCase.name)
        }
    }

    func testProviderFailsSoftPerPart() async {
        let provider = SystemDiskHeaderProvider(
            sysctl: { nil },
            tmutil: { _ in "Snapshots for disk /:\ncom.apple.TimeMachine.2026-10-07-101112.local" },
            capacity: { _ in (importantUsage: 100, available: 40) }
        )

        let snapshot = await provider.snapshot(volume: URL(fileURLWithPath: "/"))

        XCTAssertEqual(snapshot, DiskHeaderSnapshot(purgeableBytes: 60, swapUsedBytes: nil, localSnapshotCount: 1))
    }
}
