import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVHomeView: View {
    @Binding var state: ClashTVProductState
     
     
     
    @Binding var showsOutboundMode: Bool
     
     
    @Binding var showsSubscriptions: Bool
     
     
     
    @Binding var showsNodes: Bool
     
     
     
    var onPrimaryAction: (() -> Void)?

    @State private var explained: Explanation = .connect
    @State private var clockNow = Date()
    @Environment(\.clashTVPollingPresentation) private var pollingPresentation
    @Environment(\.clashThroughputUnit) private var throughputUnit
    private var clockActive: Bool {
        pollingPresentation.active && pollingPresentation.page == .home && isConnected
    }

    enum Explanation: Hashable {
        case connect, disconnect, reinstall, outbound, profile, node

        var label: String {
            switch self {
            case .connect: String(localized: "START")
            case .disconnect: String(localized: "STOP")
            case .reinstall: String(localized: "Reinstall VPN Profile")
            case .outbound: String(localized: "Outbound mode")
            case .profile: String(localized: "Configuration")
            case .node: String(localized: "Node")
            }
        }

        var detail: String {
            switch self {
            case .connect:
                String(localized: "Connects Clash and routes traffic by the current profile's rules. Until then nothing goes through a proxy.")
            case .disconnect:
                String(localized: "Disconnects Clash. The profile and the selected node stay as they are.")
            case .reinstall:
                 
                 
                String(localized: "Removes the Clash VPN configuration from this Apple TV and adds it again. Apple TV asks you to allow it, as on first start. Then press START.")
            case .outbound:
                String(localized: "Rule matches every connection against the configuration. Global sends everything to the selected node. Direct proxies nothing.")
            case .profile:
                String(localized: "The profile this Apple TV is using. Press to see the others, switch to one, or remove one. The address is what gets remembered; what it points at is downloaded again when needed.")
            case .node:
                 
                 
                ClashTVHomePresentation.nodeExplanation(mode: .rule)
            }
        }
    }

    private var isConnected: Bool { state.isConnected }
    private var presentation: ClashTVHomePresentation { ClashTVHomePresentation.make(state: state, now: clockNow) }
     
     
     
    private var primaryExplanation: Explanation {
        isConnected ? .disconnect : presentation.reinstallsVPNProfile ? .reinstall : .connect
    }

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            actions
            explanation
        }
        .task(id: clockActive) {
            guard clockActive else { return }
            await ClashTVDisplayClock.run { clockNow = $0 }
        }
        .task {
             
             
             
             
             
             
            explained = primaryExplanation
        }
        .onChange(of: primaryExplanation) { _, next in
             
             
             
             
             
            if [.connect, .disconnect, .reinstall].contains(explained) { explained = next }
        }
    }

    private var actions: some View {
        list
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    private var primaryAction: some View {
        Button {
            guard presentation.isPressable else { return }
            if let onPrimaryAction {
                onPrimaryAction()
            } else {
                state.stage = isConnected ? .disconnected : .connected
            }
        } label: {
            primaryWord
        }
        .onClashTVFocus { explained = primaryExplanation }
         
         
         
         
         
         
         
         
         
         
         
         
         
    }

     
     
     
     
     
     
     
    private var primaryWord: some View {
        HStack(spacing: 24) {
            if presentation.showsActivity {
                ProgressView()
            }
            Text(presentation.buttonTitle)
                 
                 
                 
                .font(.largeTitle)
                .fontWeight(.black)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var list: some View {
        List {
             
             
             
             
            Section {
                primaryAction
            } footer: {
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                Text(presentation.statusLine)
                    .accessibilityIdentifier("tvos.home.status")
                    .foregroundStyle(Self.tone(presentation.tone))
                     
                     
                     
                     
                     
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                ForEach(ClashTVHomePresentation.readFailures(state), id: \.self) { message in
                    Text(verbatim: message).font(.caption).foregroundStyle(.secondary)
                }
            }

            if isConnected {
                Section("Throughput") {
                     
                     
                    LabeledContent("Download", value: state.observations.traffic.value(ClashTVHomePresentation.throughput(state.downloadBytesPerSecond, unit: throughputUnit)))
                    LabeledContent("Upload", value: state.observations.traffic.value(ClashTVHomePresentation.throughput(state.uploadBytesPerSecond, unit: throughputUnit)))
                }
            }

            Section("Using") {
                 
                 
                Button { showsOutboundMode = true } label: {
                    LabeledContent("Outbound mode", value: state.observations.mode.value(state.outboundMode.title))
                }
                    .onClashTVFocus { explained = .outbound }
                 
                 
                Button { showsSubscriptions = true } label: {
                     
                     
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        LabeledContent(state.profileName, value: Self.profileAge(state, now: context.date))
                    }
                }
                    .onClashTVFocus { explained = .profile }
                 
                 
                 
                 
                 
                 
                 
                 
                Button { showsNodes = true } label: {
                    let row = ClashTVHomePresentation.nodeRow(state)
                    LabeledContent(row.title, value: row.value)
                }
                    .onClashTVFocus { explained = .node }
            }
        }
         
         
         
        .listStyle(.grouped)
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        .safeAreaPadding(.horizontal, 44)
        .frame(maxWidth: .infinity)
    }

     

     
     
    static func statusLine(_ state: ClashTVProductState) -> String {
        ClashTVHomePresentation.make(state: state).statusLine
    }

     
    static func tone(_ tone: ClashTVHomePresentation.Tone) -> Color {
        switch tone {
        case .idle: .blue
        case .transitional: .secondary
        case .connected: .green
        case .failed: .red
        }
    }

     
     
    private var explanation: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(explained.label)
                .font(.caption)
                .textCase(.uppercase)
                .foregroundStyle(.tertiary)
            Text(explained == .node ? ClashTVHomePresentation.nodeExplanation(mode: state.outboundMode) : explained.detail)
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(.easeOut(duration: 0.18), value: explained)
    }
}


private struct ClashTVPollingPresentationKey: EnvironmentKey {
    static let defaultValue = ClashTVPollingPresentation(page: .configuration, active: false)
}

extension EnvironmentValues {
    var clashTVPollingPresentation: ClashTVPollingPresentation {
        get { self[ClashTVPollingPresentationKey.self] }
        set { self[ClashTVPollingPresentationKey.self] = newValue }
    }
}

@MainActor
enum ClashTVDisplayClock {
    static func run(now: () -> Date = Date.init,
                    sleep: () async throws -> Void = { try await Task.sleep(for: .seconds(1)) },
                    publish: (Date) -> Void) async {
        while !Task.isCancelled {
            publish(now())
            do { try await sleep() } catch { return }
        }
    }
}

extension ClashTVHomeView {
     
    static func profileAge(_ state: ClashTVProductState, now: Date) -> String {
        state.profileUpdatedAt.map { ClashTVSubscriptionUpdatedWords.text(updatedAt: $0, now: now) } ?? state.profileAge
    }
}
