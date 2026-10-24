import Foundation

 
 
 
 

 
 
 
 
enum LibraryGoneRepublish {
    static let markerKey = "node-library.republished-for"

     
    static func identity(of record: StartupOutcomeRecord) -> String {
        [record.at.map { String(Int64($0.timeIntervalSince1970)) } ?? "-",
         record.requested.map { $0.profileID + "/" + $0.revision } ?? "-",
         record.message ?? ""].joined(separator: "|")
    }

     
    static func owes(_ record: StartupOutcomeRecord?, answered: String?) -> Bool {
        guard let record, NodeLibraries.isUnavailable(record.message) else { return false }
        return identity(of: record) != answered
    }

     
     
     
     
    enum Action: Equatable {
        case reconnect, applyToRunningTunnel, republishOnly
    }

     
     
     
     
     
     
     
     
     
     
     
    static func action(for record: StartupOutcomeRecord, tunnelIsRunning: Bool,
                       readerStillWantsIt: Bool = true, now: Date = Date(),
                       intent: Intent = .notTracked) -> Action {
        if tunnelIsRunning { return .applyToRunningTunnel }
        guard record.operation == "start", readerStillWantsIt, record.userInitiated == true,
              record.outcome != .backedOff,
              let at = record.at,
               
              (0...reconnectWithin).contains(now.timeIntervalSince(at))
        else { return .republishOnly }
        switch intent {
        case .notTracked:
            return .reconnect
        case .tracked(let last):
             
             
             
             
             
             
            guard let last, last.intent == .connect,
                  at.timeIntervalSince(last.at) > -recordRounding
            else { return .republishOnly }
            return .reconnect
        }
    }

     
     
     
    enum Intent: Equatable {
        case notTracked
        case tracked(ReaderTunnelIntent.Record?)
    }

     
     
    static let reconnectWithin: TimeInterval = 120

     
    static let recordRounding: TimeInterval = 1

     
     
     
    static func markAnswered(_ record: StartupOutcomeRecord, in markers: UserDefaults) {
        markers.set(identity(of: record), forKey: markerKey)
    }

     
     
    static let readerSentence = "Clash can reconnect once you open it"
}
