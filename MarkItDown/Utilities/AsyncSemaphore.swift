import Foundation

final class AsyncSemaphore {
    private let value: Int
    private var count: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var unfairLock = os_unfair_lock()

    init(value: Int) {
        self.value = value
        self.count = value
    }

    private func withLock<T>(_ body: () -> T) -> T {
        os_unfair_lock_lock(&unfairLock)
        defer { os_unfair_lock_unlock(&unfairLock) }
        return body()
    }

    func wait() async {
        if withLock({ count > 0 }) {
            withLock { count -= 1 }
            return
        }

        await withCheckedContinuation { continuation in
            withLock { waiters.append(continuation) }
        }
    }

    func signal() {
        if withLock { waiters.isEmpty } {
            withLock { count += 1 }
        } else {
            let continuation = withLock { waiters.removeFirst() }
            continuation.resume()
        }
    }
}
