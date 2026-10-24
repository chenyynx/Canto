import Foundation

 
 
 
 
 
 
 
 
 
 
 
struct ClashTVHomePresentation: Equatable {
    enum Tone: Equatable {
         
        case idle
         
        case transitional
         
        case connected
         
        case failed
    }

     
     
     
     
    let buttonTitle: String
    let statusLine: String
    let tone: Tone
     
     
     
     
    let cancels: Bool
     
     
     
    let reinstallsVPNProfile: Bool

    init(buttonTitle: String, statusLine: String, tone: Tone, cancels: Bool = false, reinstallsVPNProfile: Bool = false) {
        self.buttonTitle = buttonTitle
        self.statusLine = statusLine
        self.tone = tone
        self.cancels = cancels
        self.reinstallsVPNProfile = reinstallsVPNProfile
    }

     
    var showsActivity: Bool { tone == .transitional }
     
     
     
     
    var isPressable: Bool { !showsActivity || cancels }

    static func phase(for state: ClashTVProductState) -> ClashHomeConnectionPhase {
        ClashHomeConnectionPresenter.presentation(for: facts(for: state)).phase
    }

    static func facts(for state: ClashTVProductState) -> ClashHomeConnectionFacts {
        let status: String = switch state.stage {
        case .disconnected: "disconnected"
        case .connecting: "connecting"
        case .connected: "connected"
        case .disconnecting: "disconnecting"
        }
        return ClashHomeConnectionFacts(
             
             
             
            activeProfileName: state.profileName.isEmpty ? "Profile" : state.profileName,
            vpnStatus: status,
            errorMessage: state.issue ?? "",
            vpnAuthorization: state.vpnAuthorization,
             
             
            errorIsProviderNotLaunched: state.issue == ClashTVTunnelController.providerNotLaunchedMessage,
            mode: state.outboundMode.kernelToken
        )
    }

    static func make(state: ClashTVProductState, now: Date = Date()) -> ClashTVHomePresentation {
        if let phase = state.pipelinePhase {
            let line: String = switch phase {
            case .downloading: String(localized: "Downloading configuration…")
            case .preparing: String(localized: "Preparing configuration…")
            case .publishing: String(localized: "Saving configuration…")
            }
             
             
             
            return ClashTVHomePresentation(
                buttonTitle: "STARTING".localizedForTelevision,
                statusLine: line,
                tone: .transitional,
                cancels: true
            )
        }
        if let authorization = state.vpnAuthorization, state.issue == nil, !state.isConnected {
            let waiting = authorization == .waiting
            return .init(buttonTitle: waiting ? "STARTING".localizedForTelevision : "Retry".localizedForTelevision,
                         statusLine: waiting ? String(localized: "Allow VPN setup to connect.")
                            : String(localized: "Select Retry, then allow VPN setup."),
                         tone: waiting ? .transitional : .idle, cancels: waiting)
        }
        let presentation = ClashHomeConnectionPresenter.presentation(for: facts(for: state))
        switch presentation.phase {
        case .connected:
             
             
             
            if let issue = state.issue {
                return ClashTVHomePresentation(
                    buttonTitle: word(presentation),
                    statusLine: issue,
                    tone: .failed
                )
            }
            return ClashTVHomePresentation(
                buttonTitle: word(presentation),
                statusLine: connectedLine(state, now: now),
                tone: .connected
            )
        case .connecting:
             
             
             
            return ClashTVHomePresentation(
                buttonTitle: presentation.title.localizedForTelevision,
                statusLine: presentation.subtitle.rawValue.localizedForTelevision,
                tone: .transitional,
                cancels: presentation.primaryAction == .cancel
            )
        case .recoverableError:
             
             
             
            let reinstalls = presentation.issue?.kind == .providerNotLaunched
            return ClashTVHomePresentation(
                buttonTitle: reinstalls ? String(localized: "Reinstall VPN Profile") : word(presentation),
                statusLine: presentation.issue?.message ?? presentation.subtitle.rawValue.localizedForTelevision,
                tone: .failed,
                reinstallsVPNProfile: reinstalls
            )
        default:
            return ClashTVHomePresentation(
                buttonTitle: word(presentation),
                statusLine: String(localized: "Not Connected · \(state.nodeCount) nodes · \(state.groupCount) policy groups · \(state.ruleCount) rules"),
                tone: .idle
            )
        }
    }

     
     
     
     
     
     
     
     
     
    static func nodeObservation(_ state: ClashTVProductState) -> ClashTVObservation {
        state.outboundMode == .direct ? state.observations.mode : state.observations.proxies
    }

    static func nodeRow(_ state: ClashTVProductState) -> (title: String, value: String) {
        guard nodeObservation(state).hasValue else {
            return (String(localized: "Node"), "—")
        }
        if state.outboundMode == .direct { return (String(localized: "Node"), "DIRECT") }
        if state.nodeName.isEmpty { return (String(localized: "Node"), "—") }
        return (state.nodeName, state.nodeGroup)
    }

     
     
     
    static func nodeExplanation(mode: ClashTVOutboundMode) -> String {
        if mode == .direct {
            return String(localized: "This mode sends all traffic without a proxy, so proxy groups and nodes are not listed.")
        }
        return String(localized: "The node currently carrying proxied traffic. A url-test group may pick a different one for you. Press to see every group and node.")
    }

     
     
     
    private static func word(_ presentation: ClashHomeConnectionPresentation) -> String {
        (presentation.primaryActionTitle ?? presentation.title).localizedForTelevision
    }

     
     
     
     
    static func connectedLine(_ state: ClashTVProductState, now: Date = Date()) -> String {
        let seconds = state.connectedSince.map { Int(now.timeIntervalSince($0)) } ?? 0
        let total = state.observations.totals.value(ClashTVBytes.text(state.sessionBytes), unknown: "—")
        let count = state.observations.connections.value(String(state.connectionCount), unknown: "—")
        return String(localized: "Connected · \(duration(secondsElapsed: seconds)) · \(total) since you connected · \(count) connections")
    }

     
    static func readFailures(_ state: ClashTVProductState) -> [String] {
        guard state.isConnected else { return [] }
        return ClashTVObservation.failureMessages([
            state.observations.traffic, state.observations.totals,
            state.observations.connections, state.observations.mode, state.observations.proxies
        ]).filter { $0 != state.issue }
    }

     
     
    static func throughput(_ bytesPerSecond: Int64, unit: ClashThroughputUnit) -> String {
        ClashThroughputFormatter.rate(bytesPerSecond, unit: unit)
    }

    static func duration(secondsElapsed: Int) -> String {
        ClashConnectionDuration.text(secondsElapsed: secondsElapsed)
    }
}

 
 
 
enum ClashTVBytes {
    static func text(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.includesUnit = true
        return formatter.string(fromByteCount: max(0, count))
    }
}
