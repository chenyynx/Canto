import Foundation
import NetworkExtension

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct VPNUnrequestedStopLog {
     
    struct Run: Equatable {
         
        let connectedSince: Date?
         
        let lastSeenUp: Date
         
         
         
         
        let readerWordGeneration: UInt64?
    }

    private enum Key {
        static let armed = "vpn.unrequestedStop.armed"
         
         
         
         
         
        static let stopAskedAt = "vpn.unrequestedStop.stopAskedAt"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    var armed: Run? {
        guard let object = defaults.dictionary(forKey: Key.armed),
              let seen = object["lastSeenUp"] as? Double else { return nil }
        return Run(
            connectedSince: (object["connectedSince"] as? Double).map(Date.init(timeIntervalSinceReferenceDate:)),
            lastSeenUp: Date(timeIntervalSinceReferenceDate: seen),
            readerWordGeneration: (object["readerWordGeneration"] as? NSNumber)?.uint64Value
        )
    }

     
    func tunnelIsUp(connectedSince: Date?, readerWordGeneration: UInt64?, at now: Date = Date()) {
        if let asked = defaults.object(forKey: Key.stopAskedAt) as? Double {
            guard let connectedSince, connectedSince.timeIntervalSinceReferenceDate > asked else { return }
            defaults.removeObject(forKey: Key.stopAskedAt)
        }
         
         
         
         
        let current = armed
        let sameRun = connectedSince.flatMap { since in
            current?.connectedSince.map { abs($0.timeIntervalSince(since)) < 0.001 }
        } ?? false
        let generation = sameRun ? current?.readerWordGeneration : readerWordGeneration
        var object: [String: Any] = ["lastSeenUp": now.timeIntervalSinceReferenceDate]
        if let connectedSince { object["connectedSince"] = connectedSince.timeIntervalSinceReferenceDate }
        if let generation { object["readerWordGeneration"] = NSNumber(value: generation) }
        defaults.set(object, forKey: Key.armed)
    }

     
     
     
     
    func appWillStop(connectedSince: Date?, at now: Date = Date()) {
        defaults.removeObject(forKey: Key.armed)
        defaults.set(now.timeIntervalSinceReferenceDate, forKey: Key.stopAskedAt)
    }

     
     
    func tunnelIsDown(lastReaderWord: ReaderTunnelIntent.Record?) -> Run? {
        defaults.removeObject(forKey: Key.stopAskedAt)
        guard let run = armed else { return nil }
        defaults.removeObject(forKey: Key.armed)
        if let word = lastReaderWord, word.intent == .stop, word.generation != run.readerWordGeneration {
            return nil
        }
        return run
    }

     
    static func line(for run: Run, status: String, error: NSError?) -> String {
        let since = run.connectedSince.map(stamp) ?? "unknown"
        let seen = stamp(run.lastSeenUp)
        let account: String
        if let error {
            let domain = error.domain
            let code = error.code
            let description = error.localizedDescription
            account = "domain=\(domain) code=\(code) description=\(description)"
        } else {
            account = "error=none"
        }
        return "vpn stopped without a request from Clash  status=\(status) connectedSince=\(since) lastSeenUp=\(seen) \(account)"
    }

    static func stamp(_ date: Date) -> String {
        ISO8601DateFormatter.string(from: date, timeZone: TimeZone(secondsFromGMT: 0)!,
                                    formatOptions: [.withInternetDateTime])
    }
}
