import Foundation

final class AsyncSemaphore {
    private let value: Int
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private let lock = NSLock()

    init(value: Int) {
        self.value = value
        self.count = value
    }

    func wait() async {
        lock.lock()
        defer { lock.unlock() }
        if count > 0 {
            count -= 1
            return
        }

        await withCheckedContinuation { continuation in
            lock.lock()
            defer { lock.unlock() }
            waiters.append(continuation)
        }
    }

    func signal() {
        lock.lock()
        defer { lock.unlock() }
        if waiters.isEmpty {
            count += 1
        } else {
            let continuation = waiters.removeFirst()
            continuation.resume()
        }
    }
}
