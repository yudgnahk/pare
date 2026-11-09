import Foundation

/// A value produced in the background that any number of waiters read with a time limit, never waiting on the producer.
final class TimeBoxedValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?
    private var cancelled = false
    private var waiters: [UUID: CheckedContinuation<Value?, Never>] = [:]

    /// True once the consumer gave up; producers poll it to stop early.
    var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func fulfill(_ newValue: Value) {
        lock.lock()
        value = newValue
        let pending = waiters
        waiters = [:]
        lock.unlock()
        for continuation in pending.values { continuation.resume(returning: newValue) }
    }

    /// The value if it arrives within `seconds`, else nil.
    func value(waitingAtMost seconds: Double) async -> Value? {
        let id = UUID()
        return await withCheckedContinuation { continuation in
            lock.lock()
            if let value {
                lock.unlock()
                continuation.resume(returning: value)
                return
            }
            waiters[id] = continuation
            lock.unlock()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                self.expire(id)
            }
        }
    }

    private func expire(_ id: UUID) {
        lock.lock()
        let pending = waiters.removeValue(forKey: id)
        lock.unlock()
        pending?.resume(returning: nil)
    }
}
