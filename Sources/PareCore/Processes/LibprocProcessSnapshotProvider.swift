import Darwin
import Foundation

/// Reads processes through libproc and `sysctl`, the same sources Activity Monitor uses.
public struct LibprocProcessSnapshotProvider: ProcessSnapshotProviding {
    private static let zombieStatus: UInt32 = 5 // SZOMB
    private static let pathBufferSize = 4 * Int(MAXPATHLEN) // PROC_PIDPATHINFO_MAXSIZE

    private let userID: uid_t
    private let timebase: mach_timebase_info_data_t

    public init(userID: uid_t = getuid()) {
        self.userID = userID
        var timebase = mach_timebase_info_data_t()
        mach_timebase_info(&timebase)
        self.timebase = timebase
    }

    public func listProcesses() throws -> [ProcessRecord] {
        try allPIDs().compactMap(record(for:))
    }

    private func allPIDs() throws -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { throw ProcessSnapshotError.listingFailed(errno: errno) }
        // Headroom for processes spawned between the two calls.
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 256)
        let count = pids.withUnsafeMutableBytes { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count))
        }
        guard count > 0 else { throw ProcessSnapshotError.listingFailed(errno: errno) }
        return Array(pids.prefix(Int(count)).filter { $0 > 0 })
    }

    private func record(for pid: pid_t) -> ProcessRecord? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_uid == userID, info.pbi_ruid == userID,
              info.pbi_status != Self.zombieStatus,
              let usage = resourceUsage(pid)
        else { return nil }

        let name = Self.string(fromTuple: info.pbi_name)
        return ProcessRecord(
            id: ProcessID(pid: pid, startMicros: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec),
            parentPID: Int32(bitPattern: info.pbi_ppid),
            kernelName: name.isEmpty ? Self.string(fromTuple: info.pbi_comm) : name,
            executablePath: executablePath(pid),
            footprintBytes: usage.ri_phys_footprint,
            cpuTimeNanos: nanos(fromMachTicks: usage.ri_user_time &+ usage.ri_system_time)
        )
    }

    private func resourceUsage(_ pid: pid_t) -> rusage_info_v2? {
        var usage = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V2, $0)
            }
        }
        return status == 0 ? usage : nil
    }

    // ri_user_time / ri_system_time are mach ticks, not nanoseconds, on Apple silicon.
    private func nanos(fromMachTicks ticks: UInt64) -> UInt64 {
        guard timebase.denom != 0, timebase.numer != timebase.denom else { return ticks }
        return UInt64(Double(ticks) * Double(timebase.numer) / Double(timebase.denom))
    }

    private func executablePath(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Self.pathBufferSize)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    public func arguments(of pid: Int32) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = Self.argumentMax
        // Uninitialised on purpose: the kernel fills only what argv needs, so untouched pages stay unmapped.
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: MemoryLayout<Int32>.alignment)
        defer { buffer.deallocate() }
        guard sysctl(&mib, 3, buffer, &size, nil, 0) == 0 else { return nil }
        return ProcessArgumentsParser.parse(UnsafeRawBufferPointer(start: buffer, count: size))
    }

    private static let argumentMax: Int = {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.argmax", &value, &size, nil, 0) == 0, value > 0 else { return 1 << 20 }
        return Int(value)
    }()

    private static func string<T>(fromTuple tuple: T) -> String {
        withUnsafeBytes(of: tuple) { bytes in
            String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
        }
    }
}
