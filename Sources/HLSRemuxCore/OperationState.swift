import Foundation

public struct OperationID: Sendable, Hashable {
    fileprivate let rawValue: UUID

    fileprivate init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

public enum OperationStateError: Error, Sendable, Equatable {
    case operationInProgress
}

public final class OperationState: @unchecked Sendable {
    private struct ActiveOperation {
        let id: OperationID
        var cancellationRequested = false
        var cancellationInvoked = false
        var cancel: (@Sendable () -> Void)?
    }

    private let lock = NSLock()
    private var active: ActiveOperation?

    public init() {}

    public func reserve() throws -> OperationID {
        lock.lock()
        defer { lock.unlock() }

        guard active == nil else {
            throw OperationStateError.operationInProgress
        }

        let id = OperationID()
        active = ActiveOperation(id: id)
        return id
    }

    public func registerCancellation(
        _ cancel: @escaping @Sendable () -> Void,
        for id: OperationID
    ) {
        let callback: (@Sendable () -> Void)?
        lock.lock()
        if var operation = active, operation.id == id {
            operation.cancel = cancel
            if operation.cancellationRequested && !operation.cancellationInvoked {
                operation.cancellationInvoked = true
                callback = cancel
            } else {
                callback = nil
            }
            active = operation
        } else {
            callback = nil
        }
        lock.unlock()
        callback?()
    }

    public func requestCancellation(_ id: OperationID) {
        let callback: (@Sendable () -> Void)?
        lock.lock()
        if var operation = active, operation.id == id {
            operation.cancellationRequested = true
            if let cancel = operation.cancel, !operation.cancellationInvoked {
                operation.cancellationInvoked = true
                callback = cancel
            } else {
                callback = nil
            }
            active = operation
        } else {
            callback = nil
        }
        lock.unlock()
        callback?()
    }

    public func requestCancellation() {
        lock.lock()
        let id = active?.id
        lock.unlock()
        if let id {
            requestCancellation(id)
        }
    }

    public func isCancellationRequested(for id: OperationID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return active?.id == id && active?.cancellationRequested == true
    }

    public func finish(_ id: OperationID) {
        lock.lock()
        if active?.id == id {
            active = nil
        }
        lock.unlock()
    }
}
