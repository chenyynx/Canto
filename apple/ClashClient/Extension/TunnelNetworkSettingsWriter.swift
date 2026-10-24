import Foundation

 
 
 
final class TunnelNetworkSettingsWriter: @unchecked Sendable {
    struct Generation: Equatable, Sendable {
        fileprivate let value: UInt64
    }

    enum Outcome: Equatable {
        case applied
        case unchanged
        case superseded
    }

    private struct Ticket {
        let generation: Generation
        let revision: UInt64
    }

    private let lock = NSLock()
    private let gate = SettingsGate()
    private var generation: UInt64 = 0
    private var revision: UInt64 = 0
    private var needsReconciliation = false
    private var hasSubmitted = false

     
     
    func advanceGeneration() -> Generation {
        lock.lock(); defer { lock.unlock() }
        generation &+= 1
        revision = 0
        return Generation(value: generation)
    }

    func isCurrent(_ token: Generation) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == token.value
    }

    var hasSubmittedSettings: Bool {
        lock.lock(); defer { lock.unlock() }
        return hasSubmitted
    }

     
     
    @discardableResult
    func updateDesired(
        in token: Generation, when condition: () -> Bool = { true }, _ update: () -> Void
    ) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == token.value, condition() else { return false }
        revision &+= 1
        update()
        return true
    }

    @discardableResult
    func commitIfCurrent(
        _ token: Generation, requiringReconciled: Bool = false, _ commit: () -> Void
    ) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard generation == token.value,
              !requiringReconciled || !needsReconciliation else { return false }
        commit()
        return true
    }

     
     
     
     
     
    func perform<Plan>(
        in token: Generation,
        prepare: (Bool) throws -> Plan?,
        apply: (Plan) async throws -> Void,
        accept: (Plan) -> Bool = { _ in true },
        publish: (Plan) -> Void
    ) async throws -> Outcome {
        try await gate.enter()
        do {
            try Task.checkCancellation()
            guard isCurrent(token) else {
                await gate.leave()
                return .superseded
            }
            guard let (ticket, plan) = try preparePlan(in: token, prepare) else {
                let outcome: Outcome = isCurrent(token) ? .unchanged : .superseded
                await gate.leave()
                return outcome
            }
            try await apply(plan)
            let accepted = finish(ticket, plan, accept, publish, cancelled: Task.isCancelled)
            await gate.leave()
            return accepted ? .applied : .superseded
        } catch {
             
             
            await gate.leave()
            throw error
        }
    }

    private func preparePlan<Plan>(
        in token: Generation, _ prepare: (Bool) throws -> Plan?
    ) throws -> (Ticket, Plan)? {
        lock.lock(); defer { lock.unlock() }
        guard generation == token.value,
              let plan = try prepare(needsReconciliation) else { return nil }
        let ticket = Ticket(generation: token, revision: revision)
        needsReconciliation = true
        hasSubmitted = true
        return (ticket, plan)
    }

    private func finish<Plan>(
        _ ticket: Ticket, _ plan: Plan, _ accept: (Plan) -> Bool,
        _ publish: (Plan) -> Void, cancelled: Bool
    ) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !cancelled, generation == ticket.generation.value,
              revision == ticket.revision, accept(plan) else { return false }
        publish(plan)
        needsReconciliation = false
        return true
    }
}

private actor SettingsGate {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Error>
    }
    private var entered = false
    private var waiters: [Waiter] = []

    func enter() async throws {
        try Task.checkCancellation()
        guard entered else { entered = true; return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    waiters.append(Waiter(id: id, continuation: continuation))
                }
            }
        } onCancel: {
            Task { await self.cancel(id) }
        }
    }

    private func cancel(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(throwing: CancellationError())
    }

    func leave() {
        guard !waiters.isEmpty else { entered = false; return }
        waiters.removeFirst().continuation.resume()
    }
}
