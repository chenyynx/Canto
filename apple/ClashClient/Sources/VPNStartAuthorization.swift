import Foundation

 
 
protocol VPNStartAbandonment: Error {}

 
 
@MainActor
enum VPNStartAuthorization {
     
     
    static func isPermissionDenial(_ error: NSError) -> Bool {
        var current: NSError? = error
        for _ in 0..<8 {
            guard let value = current else { return false }
            if value.domain == NSCocoaErrorDomain && value.code == NSUserCancelledError { return true }
            if value.domain == "NEConfigurationErrorDomain" && value.code == 10 { return true }
             
             
             
            if value.domain == "NEVPNErrorDomain", value.code == 5,
               value.localizedDescription == "permission denied" { return true }
            current = value.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    static func perform(
        save: () async throws -> Void,
        reload: () async throws -> Void,
        start: () throws -> Void,
        abort: () async -> Void,
        isCurrent: () -> Bool,
        delay: @escaping () async throws -> Void = {
            try await Task.sleep(nanoseconds: 15_000_000_000)
        },
        onWaiting: @escaping () -> Void
    ) async throws {
        func checkIntent() throws {
            try Task.checkCancellation()
            guard isCurrent() else { throw CancellationError() }
        }
        try checkIntent()
        var saved = false
        do {
            try await IPStackProfileWriter.awaitConfirmation(
                operation: save, delay: delay, onWaiting: onWaiting)
            saved = true
            try checkIntent()
            try await reload()
            try checkIntent()
            try start()
        } catch {
            if error is CancellationError || Task.isCancelled || !isCurrent() {
                if saved { await abort() }
                throw CancellationError()
            }
             
             
             
             
            if error is VPNStartAbandonment {
                if saved { await abort() }
                throw error
            }
            throw error
        }
    }

     
    static func resolveFailure(
        fetch: () async -> NSError?,
        isCurrent: () -> Bool,
        publish: (NSError?) -> Void
    ) async {
        guard isCurrent() else { return }
        let error = await fetch()
        guard !Task.isCancelled, isCurrent() else { return }
        publish(error)
    }
}

 
 
final class VPNStartCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}
