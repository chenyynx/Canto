import Foundation
import NetworkExtension

 
 
 
 
 
 
struct VPNStartFailureTracker {
    private var awaitingResult = false
    private var startedAt: Date?
     
     
     
     
     
    private(set) var consecutiveInstantFailures = 0
     
     
     
     
     
    static let instantWindow: TimeInterval = 0.5
     
     
     
     
     
     
     
    private(set) var providerLooksUnlaunched = false

    mutating func beginStart(at now: Date = Date()) {
        awaitingResult = true
        startedAt = now
        providerLooksUnlaunched = false
    }

    mutating func cancelStart() {
        awaitingResult = false
        startedAt = nil
        providerLooksUnlaunched = false
    }

     
     
    mutating func forgetInstantFailures() {
        consecutiveInstantFailures = 0
        providerLooksUnlaunched = false
    }

     
     
     
     
    var isAwaitingResult: Bool { awaitingResult }

    mutating func statusDidChange(to status: NEVPNStatus, at now: Date = Date()) -> Bool {
        switch status {
        case .connected, .reasserting:
            awaitingResult = false
            startedAt = nil
            consecutiveInstantFailures = 0
            providerLooksUnlaunched = false
            return false
        case .disconnected where awaitingResult, .invalid where awaitingResult:
            awaitingResult = false
            let lived = startedAt.map { now.timeIntervalSince($0) } ?? .infinity
            startedAt = nil
            consecutiveInstantFailures = lived < Self.instantWindow
                ? consecutiveInstantFailures + 1
                : 0
            providerLooksUnlaunched = consecutiveInstantFailures >= 2
            return true
        default:
            return false
        }
    }
}
