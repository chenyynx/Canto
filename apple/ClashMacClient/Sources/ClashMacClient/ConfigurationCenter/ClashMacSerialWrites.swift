import Foundation
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
 
@MainActor
public final class ClashMacSerialWrites {
    private var last: Task<Void, Never>?
    private let attempts: Int
    private let pauseNanoseconds: UInt64

     
     
     
    public init(attempts: Int = 10, pause: TimeInterval = 0.2) {
        self.attempts = max(1, attempts)
        pauseNanoseconds = UInt64(max(0, pause) * 1_000_000_000)
    }

     
     
    public func enqueue(
        _ work: @escaping @MainActor () async throws -> Void,
        failure: @escaping @MainActor (Error) -> Void
    ) {
        let previous = last
        let attempts = attempts
        let pause = pauseNanoseconds
        last = Task { @MainActor in
            await previous?.value
            var tried = 0
            while true {
                tried += 1
                do {
                    try await work()
                    return
                } catch ConfigurationLibraryError.busy where tried < attempts {
                    try? await Task.sleep(nanoseconds: pause)
                } catch {
                    failure(error)
                    return
                }
            }
        }
    }

     
    public func drain() async {
        await last?.value
    }
}
