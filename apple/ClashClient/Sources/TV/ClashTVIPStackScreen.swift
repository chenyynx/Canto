import SwiftUI

 
 
struct ClashTVIPStackScreen: View {
    @ObservedObject var tunnel: ClashTVTunnelController
    @State private var saved: IPStackSettings?
    @State private var error = ""
    @State private var explainedTitle = String(localized: "IP Query Mode")
    @State private var explained = String(localized: "Choose how Clash looks up IPs and whether it uses IPv6. Changing it reconnects Clash.")

    var body: some View {
        HStack(alignment: .top, spacing: 56) {
            List {
                Section("IP Query Mode") {
                    ForEach(IPQueryMode.allCases) { mode in
                        choice(mode.title, selected: saved?.queryMode == mode,
                               id: "tvos.ipStack.query.\(mode.rawValue)") {
                            guard var next = saved else { return }
                            next.queryMode = mode
                            apply(next)
                        }
                        .onClashTVFocus {
                            explainedTitle = mode.title.localizedForTelevision
                            explained = Self.explanation(mode)
                        }
                    }
                }
                Section(Self.ipv6SectionTitle) {
                    ForEach(TUNIPv6Mode.allCases) { mode in
                        choice(Self.title(for: mode), selected: saved?.tunIPv6Mode == mode,
                               id: "tvos.ipStack.tun.\(mode.rawValue)") {
                            guard var next = saved else { return }
                            next.tunIPv6Mode = mode
                            apply(next)
                        }
                        .onClashTVFocus {
                            explainedTitle = Self.title(for: mode)
                            explained = Self.explanation(mode)
                        }
                    }
                }
            }
            .listStyle(.grouped)
            .safeAreaPadding(.horizontal, 44)
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 16) {
                Text(explainedTitle)
                    .font(.caption)
                    .textCase(.uppercase)
                    .foregroundStyle(.tertiary)
                Text(explained).font(.title3).foregroundStyle(.secondary)
                if tunnel.state.isConnected {
                    Text(Self.reconnectsLine)
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 8)
                }
                if tunnel.isApplyingIPStack {
                    ProgressView("Applying IP Stack settings…")
                        .accessibilityIdentifier("tvos.ipStack.applying")
                }
                if !error.isEmpty {
                    Text(error).foregroundStyle(.orange)
                        .accessibilityIdentifier("tvos.ipStack.error")
                }
                if let feedback = tunnel.state.feedback(for: [.ipStack]) {
                    ClashTVFeedbackLine(presentation: feedback)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 44)
            .animation(.easeOut(duration: 0.18), value: explained)
        }
        .task { reload() }
        .accessibilityIdentifier("tvos.ipStack.screen")
    }

    private func choice(_ title: String, selected: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title.localizedForTelevision)
                Spacer()
                if selected { Image(systemName: ClashSymbol.checkmark.rawValue) }
            }
        }
         
         
         
         
         
         
        .disabled(saved == nil)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(id)
    }

    private func reload() {
        do { saved = try IPStackSettings.load(from: tunnel.ipStackDefaults) }
        catch { self.error = error.localizedDescription }
    }

    private func apply(_ next: IPStackSettings) {
        guard next != saved else { return }
        tunnel.state.beginOperation()
         
        guard !tunnel.isApplyingIPStack else { return }
         
         
        if let busy = busy {
            tunnel.state.post(ClashTVFeedback.busy(busy), for: .ipStack)
            return
        }
        error = ""
        Task { @MainActor in
            do {
                 
                 
                 
                if try await tunnel.applyIPStack(next) {
                    tunnel.state.post(ClashTVFeedback.ipStackAppliedWithRestart, for: .ipStack)
                }
            } catch is CancellationError {
                 
            } catch IPStackSettingsApplicationError.operationInProgress {
                tunnel.state.post(ClashTVFeedback.busy(busy ?? .updating), for: .ipStack)
            } catch ClashTVTunnelController.ControllerError.ipStackRestartFailed(let reason) {
                 
                 
                tunnel.state.post(ClashTVFeedback.ipStackChangedNotRestarted(reason: reason), for: .ipStack, remembers: false)
            } catch ClashTVTunnelController.ControllerError.ipStackStopUnanswered(let reason) {
                 
                 
                tunnel.state.post(ClashTVFeedback.ipStackChangedNotRestarted(reason: reason), for: .ipStack)
            } catch {
                tunnel.state.post(ClashTVFeedback.couldNotApplyIPStack(reason: error.localizedDescription), for: .ipStack)
            }
            reload()
        }
    }

    private var busy: ClashTVFeedback.Busy? {
        if tunnel.isStarting { return .connecting }
        if tunnel.state.stage == .disconnecting { return .disconnecting }
        return nil
    }

    static func explanation(_ mode: IPQueryMode) -> String {
        switch mode {
        case .followConfiguration: String(localized: "Run the configuration's own IPv6 settings. Every other choice overrides the configuration.")
        case .ipv4Only: String(localized: "Query only IPv4 addresses and reject IPv6 connections.")
        case .dualStack: String(localized: "Query IPv4 and IPv6 together and use the first usable response.")
        case .preferIPv4: String(localized: "Wait for both query results. Prefer IPv4 when available; otherwise use IPv6. This can add latency.")
        case .preferIPv6: String(localized: "Wait for both query results. Prefer IPv6 when available; otherwise use IPv4. This can add latency.")
        case .ipv6Only: String(localized: "Query only IPv6 addresses and reject IPv4 connections. Use with caution: some destinations may be unreachable.")
        }
    }

     
     
    static var ipv6SectionTitle: String { String(localized: "IPv6") }

    static func title(for mode: TUNIPv6Mode) -> String {
        switch mode {
        case .followConfiguration: String(localized: "Follow Configuration")
        case .disabled: String(localized: "Off")
        case .automatic: String(localized: "Automatic")
        case .enabled: String(localized: "Always")
        }
    }

     
    static var reconnectsLine: String { String(localized: "Changing this reconnects Clash") }

    static func explanation(_ mode: TUNIPv6Mode) -> String {
        switch mode {
        case .followConfiguration: String(localized: "Use IPv6 only if the profile turns it on. The other choices override the profile.")
        case .disabled: String(localized: "Don't use IPv6.")
        case .automatic: String(localized: "Use IPv6 when the network supports it. Switching networks doesn't reconnect Clash.")
        case .enabled: String(localized: "Always use IPv6. May cause problems on networks without IPv6.")
        }
    }
}
