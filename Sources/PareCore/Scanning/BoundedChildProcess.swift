import Darwin
import Foundation

/// One child in its own process group with null stdin/stderr and piped stdout. Finishes on exit + EOF,
/// or at the deadline / task cancellation, which resume at once and then SIGTERM, later SIGKILL, the group.
final class BoundedChildProcess: @unchecked Sendable {
    typealias Outcome = (exitCode: Int32, stdout: Data)

    /// Time a timed-out group gets between SIGTERM and SIGKILL.
    static let killGraceSeconds: TimeInterval = 1
    private static let readChunkBytes = 64 * 1024

    // All mutable state below is touched only on `queue`.
    private let queue = DispatchQueue(label: "com.yudgnahk.pare.tool-command")
    private let pid: pid_t
    private let readFD: Int32
    private var readSource: DispatchSourceRead?
    private var chunk = [UInt8](repeating: 0, count: BoundedChildProcess.readChunkBytes)
    private var output = Data()
    private var exitCode: Int32?
    private var reachedEOF = false
    private var finished = false
    private var continuation: CheckedContinuation<Outcome?, Never>?

    private init(pid: pid_t, readFD: Int32) {
        self.pid = pid
        self.readFD = readFD
    }

    /// Nil on launch failure, timeout or cancellation; never waits past `timeout` for the result.
    static func run(
        executable: URL,
        arguments: [String],
        environment: [String: String]?,
        timeout: TimeInterval
    ) async -> Outcome? {
        guard let (pid, readFD) = spawn(executable: executable, arguments: arguments, environment: environment) else {
            return nil
        }
        let child = BoundedChildProcess(pid: pid, readFD: readFD)
        child.startReaper()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                child.queue.async { child.start(continuation, timeout: timeout) }
            }
        } onCancel: {
            child.queue.async { child.abandon() }
        }
    }

    // MARK: - Lifecycle (on queue)

    private func start(_ continuation: CheckedContinuation<Outcome?, Never>, timeout: TimeInterval) {
        guard !finished else {
            close(readFD)
            continuation.resume(returning: nil)
            return
        }
        self.continuation = continuation

        let source = DispatchSource.makeReadSource(fileDescriptor: readFD, queue: queue)
        source.setEventHandler { [weak self] in self?.drain() }
        source.setCancelHandler { [readFD] in close(readFD) }
        readSource = source
        source.resume()
        queue.asyncAfter(deadline: .now() + timeout) { [weak self] in self?.abandon() }
    }

    /// A blocking wait on a plain GCD thread, never the cooperative pool; it always reaps the child.
    private func startReaper() {
        DispatchQueue.global(qos: .utility).async { [self] in
            let code = Self.waitForExit(pid)
            queue.async {
                self.exitCode = code
                self.completeIfDone()
            }
        }
    }

    private func drain() {
        while true {
            let count = chunk.withUnsafeMutableBytes { read(readFD, $0.baseAddress, $0.count) }
            if count > 0 {
                output.append(contentsOf: chunk[0..<count])
                continue
            }
            if count < 0, errno == EINTR { continue }
            if count < 0, errno == EAGAIN { return }
            // EOF, or a read error that will never deliver more output.
            reachedEOF = true
            readSource?.cancel()
            completeIfDone()
            return
        }
    }

    private func completeIfDone() {
        guard !finished, continuation != nil, reachedEOF, let exitCode else { return }
        finished = true
        continuation?.resume(returning: (exitCode, output))
        continuation = nil
    }

    /// Timeout or cancellation: answer nil now, close our read end, then terminate the whole group.
    private func abandon() {
        guard !finished else { return }
        finished = true
        continuation?.resume(returning: nil)
        continuation = nil
        readSource?.cancel()
        // The child leads its own group, so this also reaches grandchildren that still hold the pipe.
        killpg(pid, SIGTERM)
        queue.asyncAfter(deadline: .now() + Self.killGraceSeconds) { [pid] in
            killpg(pid, SIGKILL)
        }
    }

    // MARK: - Spawning

    /// Mirrors `Process.terminationStatus`: the exit status, or the signal number for a signalled child.
    private static func waitForExit(_ pid: pid_t) -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1 {
            guard errno == EINTR else { return -1 }
        }
        let signal = status & 0x7f
        return signal == 0 ? (status >> 8) & 0xff : signal
    }

    private static func spawn(
        executable: URL,
        arguments: [String],
        environment: [String: String]?
    ) -> (pid: pid_t, readFD: Int32)? {
        var fds: [Int32] = [-1, -1]
        guard pipe(&fds) == 0 else { return nil }
        let (readFD, writeFD) = (fds[0], fds[1])
        // Close-on-exec keeps both ends out of any other child spawned concurrently.
        _ = fcntl(readFD, F_SETFD, FD_CLOEXEC)
        _ = fcntl(writeFD, F_SETFD, FD_CLOEXEC)
        _ = fcntl(readFD, F_SETFL, fcntl(readFD, F_GETFL) | O_NONBLOCK)

        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_adddup2(&actions, writeFD, STDOUT_FILENO)
        posix_spawn_file_actions_addopen(&actions, STDERR_FILENO, "/dev/null", O_WRONLY, 0)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // Own process group (pgid = pid) for killpg; default signal dispositions and an empty mask,
        // so the child does not inherit an ignored SIGPIPE; every other descriptor closed.
        let flags = POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_CLOEXEC_DEFAULT
        posix_spawnattr_setflags(&attributes, Int16(flags))
        posix_spawnattr_setpgroup(&attributes, 0)
        var allSignals = ~sigset_t(0)
        var noSignals = sigset_t(0)
        posix_spawnattr_setsigdefault(&attributes, &allSignals)
        posix_spawnattr_setsigmask(&attributes, &noSignals)

        let argv = [executable.path] + arguments
        let envp = (environment ?? ProcessInfo.processInfo.environment).map { "\($0.key)=\($0.value)" }
        var pid: pid_t = 0
        let status = withCStringArray(argv) { argvPointer in
            withCStringArray(envp) { envPointer in
                posix_spawn(&pid, executable.path, &actions, &attributes, argvPointer, envPointer)
            }
        }
        close(writeFD)
        guard status == 0 else {
            close(readFD)
            return nil
        }
        return (pid, readFD)
    }

    private static func withCStringArray<R>(
        _ strings: [String],
        _ body: (UnsafePointer<UnsafeMutablePointer<CChar>?>) -> R
    ) -> R {
        let pointers = strings.map { strdup($0) } + [nil]
        defer { pointers.forEach { free($0) } }
        return pointers.withUnsafeBufferPointer { body($0.baseAddress!) }
    }
}
