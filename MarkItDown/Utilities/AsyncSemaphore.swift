import Foundation

final class AsyncSemaphore {
    private let value: Int
    private let lock = NSLock()
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
        self.count = value
    }

    func wait() async {
        lock.lock()
        if count > 0 {
            count -= 1
            lock.unlock()
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func signal() {
        lock.lock()
        if waiters.isEmpty {
            count += 1
        } else {
            let continuation = waiters.removeFirst()
            continuation.resume()
        }
        lock.unlock()
    }
}
