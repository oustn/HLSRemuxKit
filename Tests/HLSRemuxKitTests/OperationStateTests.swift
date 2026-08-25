import Foundation
import Testing
@testable import HLSRemuxCore

struct OperationStateTests {
    @Test func rejectsASecondOperationUntilTheOwnerCompletes() throws {
        let state = OperationState()
        let first = try state.reserve()

        #expect(throws: OperationStateError.operationInProgress) {
            try state.reserve()
        }

        state.finish(first)
        _ = try state.reserve()
    }

    @Test func registrationImmediatelyCancelsAfterAnEarlyRequest() throws {
        let state = OperationState()
        let id = try state.reserve()
        let counter = LockedCounter()

        state.requestCancellation(id)
        state.registerCancellation({ counter.increment() }, for: id)

        #expect(counter.value == 1)
    }

    @Test func cancellationInvokesARegisteredSessionOnce() throws {
        let state = OperationState()
        let id = try state.reserve()
        let counter = LockedCounter()
        state.registerCancellation({ counter.increment() }, for: id)

        state.requestCancellation(id)
        state.requestCancellation(id)

        #expect(counter.value == 1)
    }

    @Test func staleCancellationCannotAffectTheCurrentOwner() throws {
        let state = OperationState()
        let staleID = try state.reserve()
        state.finish(staleID)
        let currentID = try state.reserve()
        let counter = LockedCounter()
        state.registerCancellation({ counter.increment() }, for: currentID)

        state.requestCancellation(staleID)

        #expect(counter.value == 0)
        #expect(state.isCancellationRequested(for: currentID) == false)
    }

    @Test func staleFinishCannotReleaseTheCurrentOwner() throws {
        let state = OperationState()
        let staleID = try state.reserve()
        state.finish(staleID)
        _ = try state.reserve()

        state.finish(staleID)

        #expect(throws: OperationStateError.operationInProgress) {
            try state.reserve()
        }
    }

    @Test func cancellationRequestIsObservableByTheOwner() throws {
        let state = OperationState()
        let id = try state.reserve()

        #expect(state.isCancellationRequested(for: id) == false)
        state.requestCancellation(id)
        #expect(state.isCancellationRequested(for: id))
    }

    @Test func cancellationWithoutAnIDTargetsTheCurrentOwner() throws {
        let state = OperationState()
        let id = try state.reserve()
        let counter = LockedCounter()
        state.registerCancellation({ counter.increment() }, for: id)

        state.requestCancellation()

        #expect(counter.value == 1)
        #expect(state.isCancellationRequested(for: id))
    }
}

private final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = 0

    var value: Int {
        lock.withLock { storage }
    }

    func increment() {
        lock.withLock { storage += 1 }
    }
}
