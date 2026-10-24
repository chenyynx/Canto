import AppIntents
import UniformTypeIdentifiers

 
 
 
 
 
 
 
 
 
 
@available(iOS 16.0, *)
enum ClashTunnelShortcut {
     
     
     
     
     
     
     
     
     
    static func sentence(on: Bool) -> LocalizedStringResource {
        on ? "Clash VPN is on." : "Clash VPN is off."
    }

    static func drive(
        _ action: ClashSystemRoute.VPNAction,
        _ act: () async -> Bool
    ) async throws {
        if await act() { return }
        ClashSystemActionDispatch.enqueue(.vpn(action))
        throw ClashTunnelIntentError.configurationUnreachable
    }
}

@available(iOS 16.0, *)
enum ClashTunnelIntentError: LocalizedError {
    case configurationUnreachable

    var errorDescription: String? {
        String(localized: "Clash could not reach its VPN configuration. Open Clash once, then run the shortcut again.")
    }
}

@available(iOS 16.0, *)
struct ConnectClashIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Clash"
    static let description = IntentDescription("Start the installed Clash by Clash VPN profile.")
    static var openAppWhenRun: Bool { false }
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        try await ClashTunnelShortcut.drive(.connect) {
            await ClashVPNControlDriver.apply(connect: true)
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct DisconnectClashIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Clash"
    static let description = IntentDescription("Stop the active Clash by Clash VPN profile.")
    static var openAppWhenRun: Bool { false }
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult {
        try await ClashTunnelShortcut.drive(.disconnect) {
            await ClashVPNControlDriver.apply(connect: false)
        }
        return .result()
    }
}

@available(iOS 16.0, *)
struct ToggleClashIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Clash VPN"
    static let description = IntentDescription("Start or stop Clash based on its current state.")
    static var openAppWhenRun: Bool { false }
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .background }

     
    func perform() async throws -> some IntentResult & ReturnsValue<Bool> {
        var applied: Bool?
        try await ClashTunnelShortcut.drive(.toggle) {
            applied = await ClashVPNControlDriver.toggle()
            return applied != nil
        }
        return .result(value: applied ?? false)
    }
}

 
 
@available(iOS 16.0, *)
struct GetClashVPNStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Clash VPN Status"
    static let description = IntentDescription("Reports whether the installed Clash by Clash VPN profile is connected.")
    static var openAppWhenRun: Bool { false }
    static let authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .background }

    func perform() async throws -> some IntentResult & ReturnsValue<Bool> & ProvidesDialog {
        let live = await ClashVPNControlDriver.isActive()
        let on = live ?? ClashSystemActionDispatch.handoff.isVPNSnapshotActive
        return .result(
            value: on,
            dialog: IntentDialog(ClashTunnelShortcut.sentence(on: on))
        )
    }
}

@available(iOS 16.0, *)
enum ClashRoutingModeIntentValue: String, AppEnum {
    case rule
    case global
    case direct

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Routing Mode"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .rule: "Rule",
        .global: "Global",
        .direct: "Direct",
    ]

    var route: ClashSystemRoute {
        .mode(ClashSystemRoute.RoutingMode(rawValue: rawValue)!)
    }
}

 
 
 
@available(iOS 16.0, *)
struct SetClashRoutingModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Set Clash Routing Mode"
    static let description = IntentDescription("Switch Clash between Rule, Global, and Direct routing.")
    static var openAppWhenRun: Bool { true }
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(title: "Mode")
    var mode: ClashRoutingModeIntentValue

    static var parameterSummary: some ParameterSummary {
        Summary("Set Clash to \(\.$mode)")
    }

     
     
     
    func perform() async throws -> some IntentResult {
        ClashSystemActionDispatch.enqueue(mode.route)
        return .result()
    }
}

@available(iOS 16.0, *)
struct ImportClashConfigurationIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Clash Configuration"
    static let description = IntentDescription("Import one or more YAML configurations into Clash.")
    static var openAppWhenRun: Bool { true }
    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground(.immediate) }

    @Parameter(
        title: "Configuration Files",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var files: [IntentFile]

    static var parameterSummary: some ParameterSummary {
        Summary("Import \(\.$files) into Clash")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard !files.isEmpty else { return .result(dialog: "No configuration files were provided.") }
        guard let inbox = ProfileShareInbox() else { throw ProfileShareInboxError.unavailable }
        for file in files {
            guard ProfileShareInboxAdmission.accepts(file.data) else {
                throw ProfileInstallLinkError.unsupportedFile
            }
            try inbox.enqueue(file.data)
        }
        ClashSystemActionDispatch.enqueue(.open(.profiles))
        return .result(dialog: "Opening Clash to validate and import the configuration.")
    }
}

@available(iOS 16.0, *)
struct ClashAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
         
         
         
        AppShortcut(
            intent: ConnectClashIntent(),
            phrases: ["Start \(.applicationName)"],
            shortTitle: "Start Clash",
            systemImageName: "play.fill"
        )
        AppShortcut(
            intent: DisconnectClashIntent(),
            phrases: ["Stop \(.applicationName)"],
            shortTitle: "Stop Clash",
            systemImageName: "power"
        )
        AppShortcut(
            intent: ToggleClashIntent(),
            phrases: ["Toggle \(.applicationName) VPN"],
            shortTitle: "Toggle Clash",
            systemImageName: "arrow.triangle.swap"
        )
        AppShortcut(
            intent: GetClashVPNStatusIntent(),
            phrases: ["Is \(.applicationName) connected"],
            shortTitle: "Get VPN Status",
            systemImageName: "bolt.horizontal.circle"
        )
        AppShortcut(
            intent: SetClashRoutingModeIntent(),
            phrases: ["Set routing mode in \(.applicationName)"],
            shortTitle: "Set Routing Mode",
            systemImageName: "arrow.triangle.branch"
        )
        AppShortcut(
            intent: ImportClashConfigurationIntent(),
            phrases: ["Import configuration into \(.applicationName)"],
            shortTitle: "Import Configuration",
            systemImageName: "square.and.arrow.down"
        )
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
enum ProfileShareInboxAdmission {
    static func accepts(_ data: Data) -> Bool {
        guard !data.isEmpty, data.count <= ProfileShareInbox.defaultMaximumBytes,
              let text = String(data: data, encoding: .utf8) else { return false }
        do {
            try ConfigTransforms.validateSource(text)
            return true
        } catch {
            return false
        }
    }
}
