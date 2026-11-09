import Foundation

/// A value produced in the background that one waiter reads with a time limit, never waiting on the producer.
final class TimeBoxedValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?
    private var waiter: CheckedContinuation<Value?, Never>?

    func fulfill(_ newValue: Value) {
        lock.lock()
        value = newValue
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.resume(returning: newValue)
    }

    /// The value if it arrives within `seconds`, else nil.
    func value(waitingAtMost seconds: Double) async -> Value? {
        await withCheckedContinuation { continuation in
            lock.lock()
            if let value {
                lock.unlock()
                continuation.resume(returning: value)
                return
            }
            waiter = continuation
            lock.unlock()
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(seconds, 0) * 1_000_000_000))
                self.expire()
            }
        }
    }

    private func expire() {
        lock.lock()
        let pending = waiter
        waiter = nil
        lock.unlock()
        pending?.resume(returning: nil)
    }
}
