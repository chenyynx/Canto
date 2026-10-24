import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVDiagnosticsScreen: View {
    enum Row: Hashable, CaseIterable {
        case tunnel, lastProblem, memory, geodata, providers, resolvers

        var title: String {
            switch self {
            case .tunnel: String(localized: "Connection")
            case .lastProblem: String(localized: "Last problem")
            case .memory: String(localized: "Memory")
            case .geodata: String(localized: "Geo data")
            case .providers: String(localized: "Providers")
            case .resolvers: String(localized: "DNS servers")
            }
        }

         
         
         
         
         
         
        var identifier: String {
            switch self {
            case .tunnel: "tunnel"
            case .lastProblem: "lastProblem"
            case .memory: "memory"
            case .geodata: "geodata"
            case .providers: "providers"
            case .resolvers: "resolvers"
            }
        }

        var explanation: String {
            switch self {
             
             
            case .tunnel:
                String(localized: "Whether Clash is connected.")
            case .memory:
                String(localized: "How much memory Clash is using.")
            case .geodata:
                String(localized: "Which copy of the GeoIP and GeoSite data Clash is using.")
            case .lastProblem:
                String(localized: "The last thing that went wrong since you opened Clash.")
            case .providers:
                String(localized: "How many of the profile's node lists and rule sets are ready.")
            case .resolvers:
                String(localized: "The DNS servers Clash uses.")
            }
        }
    }

    @Binding var state: ClashTVProductState
    var openDNS: () -> Void = {}
    var openProviders: () -> Void = {}

    @State private var explained: Row = .tunnel


    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            List {
                Section(Self.statusSectionTitle) {
                    row(.tunnel, value: Self.tunnelValue(state)) {}
                    row(.lastProblem, value: Self.lastProblemValue(state.lastProblem)) {}
                        .lineLimit(2)
                    row(.memory, value: Self.memoryText(state)) {}
                    row(.geodata, value: state.geodataSource.localizedForTelevision) {}
                    row(.providers, value: Self.providersValue(
                        ready: ClashTVProvidersScreen.readyCount(state.providers, tunnel: state.providerRefresh, running: state.isConnected),
                        total: state.providers.count), action: openProviders)
                }
                Section("DNS") {
                    row(.resolvers, value: "\(state.dnsNameservers.count)", action: openDNS)
                }
            }
            .listStyle(.grouped)
            .safeAreaPadding(.horizontal, 44)
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 16) {
                Text(explained.title)
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                if explained == .memory {
                     
                     
                    Text(Self.memoryText(state))
                        .font(.largeTitle)
                        .monospacedDigit()
                }
                if explained == .lastProblem, let problem = state.lastProblem {
                     
                     
                     
                     
                     
                    Text(problem.sentence)
                        .font(.title3)
                    Text(Self.lastProblemWhen(problem) ?? "")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                Text(explained.explanation)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                if explained == .lastProblem, let advice = Self.lastProblemAdvice(for: state.lastProblem) {
                     
                     
                     
                     
                     
                     
                    Text(advice)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
                if explained == .memory, state.isConnected {
                     
                     
                     
                    ClashTVObservationNote(observation: state.observations.memory)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .animation(.easeOut(duration: 0.18), value: explained)
        }
         
    }

    private func row(_ row: Row, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            LabeledContent(row.title, value: value)
        }
        .onClashTVFocus { explained = row }
        .accessibilityIdentifier("tvos.diagnostics.\(row.identifier)")
    }

     

     
    static var statusSectionTitle: String { String(localized: "Status") }

     
     
    static func memoryText(_ state: ClashTVProductState) -> String {
        state.isConnected ? state.observations.memory.value(memoryValue(state.memoryBytes)) : "—"
    }

    static func tunnelValue(_ state: ClashTVProductState) -> String {
        state.isConnected ? String(localized: "Connected") : String(localized: "Not connected")
    }

     
     
     
     
     
     
    static func providersValue(ready: Int, total: Int) -> String {
        guard total > 0 else { return String(localized: "None") }
        return String(localized: "\(ready) of \(total)")
    }

    static func lastProblemValue(_ problem: ClashTVProductState.Problem?) -> String {
        problem?.sentence ?? String(localized: "None since you opened Clash")
    }

     
     
     
    static func lastProblemWhen(_ problem: ClashTVProductState.Problem?, now: Date = Date()) -> String? {
        guard let problem else { return nil }
         
         
        if now.timeIntervalSince(problem.at) < 60 { return String(localized: "Just now") }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: problem.at, relativeTo: now)
    }

     
     
     
    static func lastProblemAdvice(for problem: ClashTVProductState.Problem?) -> String? {
        problem?.aboutProfile == true ? lastProblemAdvice : nil
    }

    static var lastProblemAdvice: String {
        String(localized: "Check that the profile URL is still reachable, then update it once from its own screen.")
    }

     
    static func memoryValue(_ bytes: Int64) -> String {
        ClashTVBytes.text(bytes)
    }
}
