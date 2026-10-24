import Foundation
 
 

 
 
 
 
 
 
 
 
 
 
 
 
struct ClashStartRecoveryState: Codable, Equatable {
    struct Quarantined: Codable, Equatable {
        let profileID: String
        let revision: String
        let message: String
        let at: Date
         
        var core: String?
    }

    var quarantined: Quarantined?
    var consecutiveFailures = 0
    var backoffUntil: Date?
    var failurePathSignature: String?
    var failedProfileID: String?
    var failedRevision: String?

    static let firstBackoff: TimeInterval = 5
    static let maximumBackoff: TimeInterval = 60

    func isQuarantined(profileID: String, revision: String, core: String) -> Bool {
        guard let quarantined else { return false }
        return quarantined.profileID == profileID && quarantined.revision == revision && quarantined.core == core
    }

     
    func backoff(now: Date, pathSignature: String, userInitiated: Bool, profileID: String?, revision: String?) -> Date? {
        guard !userInitiated, let until = backoffUntil, now < until else { return nil }
        guard failurePathSignature == pathSignature,
              failedProfileID == profileID, failedRevision == revision
        else { return nil }
        return until
    }

    mutating func noteFailure(endedAt: Date, pathSignature: String, profileID: String?, revision: String?) {
        if failurePathSignature != pathSignature || failedProfileID != profileID || failedRevision != revision {
            consecutiveFailures = 0
        }
        consecutiveFailures += 1
        let delay = min(Self.maximumBackoff, Self.firstBackoff * pow(2, Double(consecutiveFailures - 1)))
        backoffUntil = endedAt.addingTimeInterval(delay)
        failurePathSignature = pathSignature
        failedProfileID = profileID
        failedRevision = revision
    }

     
    mutating func noteSuccess(profileID: String?, revision: String?) {
        consecutiveFailures = 0
        backoffUntil = nil
        failurePathSignature = nil
        failedProfileID = nil
        failedRevision = nil
        if let quarantined, quarantined.profileID == profileID, quarantined.revision == revision {
            self.quarantined = nil
        }
    }

    mutating func quarantine(profileID: String, revision: String, message: String, at: Date, core: String) {
        quarantined = Quarantined(profileID: profileID, revision: revision, message: message, at: at, core: core)
    }

    func write(in container: URL) throws {
        let data = try ClashStartupOutcomeRecord.encoder().encode(self)
        try data.write(to: container.appendingPathComponent(ClashTunnelStart.stateFileName), options: .atomic)
    }

    static func read(in container: URL) -> ClashStartRecoveryState {
        guard let data = try? Data(contentsOf: container.appendingPathComponent(ClashTunnelStart.stateFileName)),
              let state = try? ClashStartupOutcomeRecord.decoder().decode(Self.self, from: data)
        else {
            return ClashStartRecoveryState()
        }
        return state
    }
}

 
 
 
enum ClashStartRecovery {
    struct Candidate: Equatable {
        let profileID: String
        let revision: String
        let yaml: String
         
        var recovered = false
    }

    enum Result: Equatable {
         
         
         
         
        case started(running: Candidate?, recovered: Bool, newlyQuarantined: ClashStartRecoveryState.Quarantined?,
                     warning: String? = nil)
        case refused(errorClass: String, message: String, newlyQuarantined: ClashStartRecoveryState.Quarantined?)
        case backedOff(until: Date)
    }

     
     
     
     
     
    static func run(
        state: inout ClashStartRecoveryState,
        now: Date,
        clock: () -> Date = Date.init,
        core: String,
        pathSignature: String,
        userInitiated: Bool,
        published: Candidate?,
        fallbackYAML: String? = nil,
        lastKnownGood: (Candidate?) -> Candidate?,
        start: (String) -> ProviderReloadEnvelope.Verdict
    ) -> Result {
        if let until = state.backoff(now: now, pathSignature: pathSignature, userInitiated: userInitiated,
                                     profileID: published?.profileID, revision: published?.revision) {
            return .backedOff(until: until)
        }
        guard let yaml = published?.yaml ?? fallbackYAML else {
            return .refused(errorClass: "config", message: "No client-staged config.yaml is available in the App Group", newlyQuarantined: nil)
        }
        var candidate = published
        var candidateYAML = yaml
        var recovered = published?.recovered ?? false
        var newlyQuarantined: ClashStartRecoveryState.Quarantined?

        if let current = published, state.isQuarantined(profileID: current.profileID, revision: current.revision, core: core) {
            guard let fallback = lastKnownGood(current) else {
                let message = state.quarantined?.message ?? "refused earlier"
                return .refused(errorClass: "config", message: message, newlyQuarantined: nil)
            }
            (candidate, candidateYAML, recovered) = (fallback, fallback.yaml, true)
        }
        var verdict = start(candidateYAML)
        if verdict.errorClass == "config", let current = candidate, !current.recovered,
           current.profileID == published?.profileID, current.revision == published?.revision {
            state.quarantine(profileID: current.profileID, revision: current.revision, message: verdict.message,
                             at: now, core: core)
            newlyQuarantined = state.quarantined
            if let fallback = lastKnownGood(current) {
                (candidate, candidateYAML, recovered) = (fallback, fallback.yaml, true)
                verdict = start(candidateYAML)
            }
        }
         
        if verdict.errorClass.isEmpty || verdict.errorClass == "committed" {
            state.noteSuccess(profileID: candidate?.profileID, revision: candidate?.revision)
            return .started(running: candidate, recovered: recovered, newlyQuarantined: newlyQuarantined,
                            warning: verdict.errorClass == "committed" ? verdict.message : nil)
        }
        if verdict.errorClass != "config" || recovered {
             
             
            state.noteFailure(endedAt: clock(), pathSignature: pathSignature,
                              profileID: published?.profileID, revision: published?.revision)
        }
        return .refused(errorClass: verdict.errorClass, message: verdict.message, newlyQuarantined: newlyQuarantined)
    }
}
