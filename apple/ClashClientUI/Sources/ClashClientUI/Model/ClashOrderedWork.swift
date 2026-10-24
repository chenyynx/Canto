import Foundation

 
 
 
 
 
 
 
 
 
@MainActor
public final class ClashOrderedWork {
    private var last: Task<Void, Never>?

    public nonisolated init() {}

     
     
     
    @discardableResult
    public func enqueue<T: Sendable>(_ body: @escaping @MainActor () async throws -> T) -> Task<T, Error> {
        let previous = last
        let job = Task { @MainActor () throws -> T in
            await previous?.value
            return try await body()
        }
        last = Task { @MainActor in _ = await job.result }
        return job
    }

     
    public func run<T: Sendable>(_ body: @escaping @MainActor () async throws -> T) async throws -> T {
        try await enqueue(body).value
    }
}
