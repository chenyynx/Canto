import Combine
import Foundation
import Hako
import HakoClientUI
import NetworkExtension

 
 
 
 
 
 
enum NETimeoutError: LocalizedError, Equatable {
     
    case nePreferencesTimeout
     
    case extensionMessageTimeout

    var errorDescription: String? {
        switch self {
        case .nePreferencesTimeout, .extensionMessageTimeout:
            return "The system VPN service isn’t responding. Please try again in a moment, or restart your device."
        }
    }
}

enum VPNDisconnectErrorPresentation {
    static let noNetworkMessage =
        "No network is available. Restore Wi-Fi or cellular data and try again."
    static let genericStartFailureMessage =
        "The VPN could not start. Check the configuration and try again."
    static let genericDisconnectMessage =
        "The VPN disconnected because the system reported an error."
    static let providerDisconnectMessage =
        "The VPN disconnected because the tunnel provider reported an error."
    static let genericReportMessage =
        "The VPN operation failed. Review the app and system status for details."
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let providerNotLaunchedMessage =
        "Connection failed. Tap to reinstall VPN profile."

     
    static func isProviderNotLaunched(_ reportMessage: String) -> Bool {
        reportMessage == providerNotLaunchedMessage
    }

    private static let connectionMessages: [Int: String] = [
        1: "The VPN disconnected after the device slept for an extended period.",
        2: noNetworkMessage,
        3: "The VPN disconnected after an unrecoverable network change.",
        4: "The VPN could not connect because its configuration is invalid.",
        5: "The VPN server address could not be resolved.",
        6: "The VPN server did not respond.",
        7: "The VPN server is unavailable.",
        8: "VPN authentication failed.",
        9: "The VPN client certificate is invalid.",
        10: "The VPN client certificate is not valid yet.",
        11: "The VPN client certificate has expired.",
        12: "The VPN tunnel provider stopped unexpectedly.",
        13: "The VPN configuration could not be found.",
        14: "The VPN tunnel provider is unavailable or needs an update.",
        15: "VPN protocol negotiation failed.",
        16: "The VPN server disconnected.",
        17: "The VPN server certificate is invalid.",
        18: "The VPN server certificate is not valid yet.",
        19: "The VPN server certificate has expired.",
    ]

    private static let configurationMessages: [Int: String] = [
        1: "The VPN configuration is invalid.",
        2: "The VPN configuration is disabled.",
        3: "The VPN connection failed.",
        4: "The VPN configuration is stale. Reload it and try again.",
        5: "The VPN configuration could not be read or saved.",
        6: "The VPN configuration failed for an unknown reason.",
    ]

    private static let safeReportMessages: Set<String> = Set(
        Array(connectionMessages.values)
            + Array(configurationMessages.values)
            + [
                genericStartFailureMessage,
                genericDisconnectMessage,
                providerDisconnectMessage,
                genericReportMessage,
                providerNotLaunchedMessage,
            ]
    )

    static func message(for error: NSError) -> String {
        message(for: error, providerLooksUnlaunched: false)
    }

     
     
     
    static func message(for error: NSError, providerLooksUnlaunched: Bool) -> String {
        if #available(iOS 16.0, *), error.domain == NEVPNConnectionErrorDomain {
            if error.code == 12, providerLooksUnlaunched { return providerNotLaunchedMessage }
            return connectionMessages[error.code] ?? genericDisconnectMessage
        }
        if error.domain == NEVPNErrorDomain {
            return configurationMessages[error.code] ?? genericDisconnectMessage
        }
        return providerDisconnectMessage
    }

    static func startMessage(for error: NSError) -> String {
        if error.domain == NEVPNErrorDomain {
            return configurationMessages[error.code] ?? genericStartFailureMessage
        }
        return genericStartFailureMessage
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func reportMessage(_ message: String) -> String {
        guard !message.isEmpty else { return "" }
        if safeReportMessages.contains(message) { return message }
        return String(message.prefix(512))
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func isProviderStoppedUnexpectedly(_ reportMessage: String) -> Bool {
        reportMessage == connectionMessages[12]
    }

    static func allowsSystemVPNProfileReset(for error: NSError) -> Bool {
        if #available(iOS 16.0, *), error.domain == NEVPNConnectionErrorDomain {
            return error.code == 4 || error.code == 13
        }
        if error.domain == NEVPNErrorDomain {
            return [1, 2, 4, 5, 6].contains(error.code)
        }
        return false
    }

    static func allowsSystemVPNProfileReset(forReportMessage message: String) -> Bool {
        let resettableMessages = Set(
            [connectionMessages[4], connectionMessages[13], providerNotLaunchedMessage]
                .compactMap { $0 }
                + [1, 2, 4, 5, 6].compactMap { configurationMessages[$0] }
        )
        return resettableMessages.contains(message)
    }
}

private final class VPNDisconnectErrorFetchGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NSError?, Never>?

    init(_ continuation: CheckedContinuation<NSError?, Never>) {
        self.continuation = continuation
    }

    func resolve(_ error: NSError?) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: error)
    }
}

 
 
 
 
private final class NETimeoutGate<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(returning value: T) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: value)
    }

    func resume(throwing error: Error) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(throwing: error)
    }
}

 
 
 
 
 
 
 
struct VPNTunnelSettings: Equatable {
    var enforceRoutes = false
    var includeAllNetworks = false
    var includeLocalNetworks = false
    var includeAPNs = false
    var includeCellularServices = false
     
     
     
     
     
     
     
    var hideVPNIcon = false
    var homeKitCompatibility = false
     
     
     
     
    var excludeAPNsRoute = false

    enum Key {
        static let enforceRoutes = "vpn.tunnel.enforceRoutes"
        static let includeAllNetworks = "vpn.tunnel.includeAllNetworks"
        static let includeLocalNetworks = "vpn.tunnel.includeLocalNetworks"
        static let includeAPNs = "vpn.tunnel.includeAPNs"
        static let includeCellularServices = "vpn.tunnel.includeCellularServices"
        static let hideVPNIcon = "vpn.tunnel.hideVPNIcon"
        static let homeKitCompatibility = "vpn.tunnel.homeKitCompatibility"
        static let excludeAPNsRoute = "vpn.tunnel.excludeAPNsRoute"
    }

    static func load(from defaults: UserDefaults) -> Self {
        VPNTunnelSettings(
            enforceRoutes: defaults.bool(forKey: Key.enforceRoutes),
            includeAllNetworks: defaults.bool(forKey: Key.includeAllNetworks),
            includeLocalNetworks: defaults.bool(forKey: Key.includeLocalNetworks),
            includeAPNs: defaults.bool(forKey: Key.includeAPNs),
            includeCellularServices: defaults.bool(forKey: Key.includeCellularServices),
            hideVPNIcon: defaults.bool(forKey: Key.hideVPNIcon),
            homeKitCompatibility: defaults.bool(forKey: Key.homeKitCompatibility),
            excludeAPNsRoute: defaults.bool(forKey: Key.excludeAPNsRoute)
        )
    }

    func save(to defaults: UserDefaults) {
        defaults.set(enforceRoutes, forKey: Key.enforceRoutes)
        defaults.set(includeAllNetworks, forKey: Key.includeAllNetworks)
        defaults.set(includeLocalNetworks, forKey: Key.includeLocalNetworks)
        defaults.set(includeAPNs, forKey: Key.includeAPNs)
        defaults.set(includeCellularServices, forKey: Key.includeCellularServices)
        defaults.set(hideVPNIcon, forKey: Key.hideVPNIcon)
        defaults.set(homeKitCompatibility, forKey: Key.homeKitCompatibility)
        defaults.set(excludeAPNsRoute, forKey: Key.excludeAPNsRoute)
    }
}

 
 
 
 
struct VPNRoutingPolicy: Equatable {
    let includeAllNetworks: Bool
    let excludeLocalNetworks: Bool
    let enforceRoutes: Bool
    let excludeCellularServices: Bool
    let excludeAPNs: Bool
    let excludeDeviceCommunication: Bool

    init(
        tunnel: VPNTunnelSettings = VPNTunnelSettings(),
        preserveDevelopmentDeviceCommunication: Bool = Self.defaultDevelopmentDeviceCommunication
    ) {
        includeAllNetworks = tunnel.includeAllNetworks
        excludeLocalNetworks = !tunnel.includeLocalNetworks
         
         
         
         
         
        enforceRoutes = tunnel.enforceRoutes
        excludeCellularServices = !tunnel.includeCellularServices
        excludeAPNs = !tunnel.includeAPNs
         
         
         
         
         
        excludeDeviceCommunication = includeAllNetworks
            || (enforceRoutes && preserveDevelopmentDeviceCommunication)
    }

    private init(
        includeAllNetworks: Bool,
        excludeLocalNetworks: Bool,
        enforceRoutes: Bool,
        excludeCellularServices: Bool,
        excludeAPNs: Bool,
        excludeDeviceCommunication: Bool
    ) {
        self.includeAllNetworks = includeAllNetworks
        self.excludeLocalNetworks = excludeLocalNetworks
        self.enforceRoutes = enforceRoutes
        self.excludeCellularServices = excludeCellularServices
        self.excludeAPNs = excludeAPNs
        self.excludeDeviceCommunication = excludeDeviceCommunication
    }

    private static let defaultDevelopmentDeviceCommunication = false


    func apply(to tunnelProtocol: NETunnelProviderProtocol) {
        tunnelProtocol.includeAllNetworks = includeAllNetworks
         
         
         
        tunnelProtocol.excludeLocalNetworks = excludeLocalNetworks
        tunnelProtocol.enforceRoutes = enforceRoutes
        if #available(iOS 16.4, *) {
            tunnelProtocol.excludeCellularServices = excludeCellularServices
            tunnelProtocol.excludeAPNs = excludeAPNs
        }
        if #available(iOS 17.4, *) {
            tunnelProtocol.excludeDeviceCommunication = excludeDeviceCommunication
        }
    }

    static func installed(from tunnelProtocol: NETunnelProviderProtocol) -> Self {
        var excludeCellularServices = false
        var excludeAPNs = false
        var excludeDeviceCommunication = false
        if #available(iOS 16.4, *) {
            excludeCellularServices = tunnelProtocol.excludeCellularServices
            excludeAPNs = tunnelProtocol.excludeAPNs
        }
        if #available(iOS 17.4, *) {
            excludeDeviceCommunication = tunnelProtocol.excludeDeviceCommunication
        }
        return Self(
            includeAllNetworks: tunnelProtocol.includeAllNetworks,
            excludeLocalNetworks: tunnelProtocol.excludeLocalNetworks,
            enforceRoutes: tunnelProtocol.enforceRoutes,
            excludeCellularServices: excludeCellularServices,
            excludeAPNs: excludeAPNs,
            excludeDeviceCommunication: excludeDeviceCommunication
        )
    }
}

 
 

enum AppConfigurationPreflight {
    static func validate(
        _ configContent: String,
        container: URL,
        fallbackCode: Int,
        settings: IPStackSettings? = nil
    ) throws -> PlatformConfigIntent {
        let outcome = PreflightService.check(finalYAML: configContent, container: container, settings: settings)
        guard outcome.ok, let intent = outcome.intentJSON else {
            throw NSError(domain: "HakoClient.Configuration", code: fallbackCode,
                          userInfo: [NSLocalizedDescriptionKey: outcome.errorMessage ?? "Configuration failed preflight"])
        }
        return try JSONDecoder().decode(PlatformConfigIntent.self, from: Data(intent.utf8))
    }

    static func inspectRoutingIntent(
        _ configContent: String, container: URL? = nil, settings: IPStackSettings? = nil
    ) throws -> PlatformConfigIntent {
        guard let container = container ?? AppCoreSetup.applicationContainer else {
            throw NSError(domain: "HakoClient.Configuration", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable"])
        }
        return try AppCoreSetup.withConfiguration(container: container, settings: settings) {
            var error: NSError?
            guard let box = HakoPlatformConfigIntentJSON(configContent, &error) else {
                throw error ?? NSError(domain: "HakoClient.Configuration", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "Unable to inspect configuration routing intent"])
            }
            return try JSONDecoder().decode(PlatformConfigIntent.self, from: Data(box.value.utf8))
        }
    }

}

 
 
 
@MainActor
 
 
 
enum VPNStopSite: String {
    case userButton = "user-stop-button"
    case intentRestart = "intent-restart"
    case forceRestart = "force-restart"
    case reloadFallback = "reload-fallback"
    case selfTest = "self-test"
}

final class VPNController: ObservableObject, DNSOnlyTunnelControlling {
     
     
     
     
     
     
     
     
    static let vpnProfileTitle = "Clash"

     
     
     
    static let vpnProfileDescription = "Clash by Hako"

    @Published var status: String = "idle"
     
     
     
     
     
     
    @Published private(set) var hasLoadedStatus = false
    @Published var lastError: String = "" {
        didSet { installationReadError = nil }
    }
     
    private var installationReadError: String?
    @Published private(set) var configurationNotice: String = ""
    @Published private(set) var vpnAuthorization: HakoVPNAuthorizationState?

    var systemVPNAuthorization: HakoVPNAuthorizationState? {
        vpnAuthorization ?? (hasLoadedStatus && systemVPNInstallationKnown && manager == nil ? .required : nil)
    }
     
     
     
     
    @Published var legacySettingsMigration: LegacyClientSettingsMigrationResult?
    @Published private(set) var configuredIncludedRouteCount = 0
    @Published private(set) var configuredExcludedRouteCount = 0
    @Published private(set) var routingPolicyNeedsApply = false
    @Published private(set) var installedRoutingPolicy = VPNRoutingPolicy()
     
     
    @Published private(set) var tunnelSettings = VPNTunnelSettings()

    private var manager: NETunnelProviderManager?
    private var systemVPNInstallationKnown = false
    private var installationReadGeneration: UInt64 = 0
    private var observer: NSObjectProtocol?
     
     
     
     
    private var disconnectNoticeTracker = VPNDisconnectNotice.Tracker()
    private var userStopInFlight = false
    private var startFailureTracker = VPNStartFailureTracker()
    private var systemVPNProfileResetInFlight = false
    private var startOutcomeWatchdog: Task<Void, Never>?
     
     
    private var statusLoad: Task<Void, Never>?
    private var connectionStatusGeneration: UInt64 = 0

    private let extensionBundleID = HakoAppIdentifiers.packetTunnelExtensionBundleID
    private let preferences: UserDefaults
    private let operatingModeStore: NetworkOperatingModeStore
    private let dnsOnlyConfigurationIsInstalled: @Sendable () async -> Bool
    private let usesUITestFixtures: Bool
    private let systemVPNManagers: @MainActor () async throws -> [NETunnelProviderManager]

     
     
     
     
     
     
     
     
     
     
     
    private lazy var connectionRequests: TunnelRequestCoalescer = {
        let fixtures = usesUITestFixtures
        return TunnelRequestCoalescer(
            gestureWindow: {
                fixtures ? 0 : TunnelRequestCoalescer.defaultGestureWindow
            },
            isSettling: { [weak self] in
                guard let self, !fixtures else { return false }
                return Self.transitionalStates.contains(self.status)
            },
            settlingWindow: fixtures ? 0 : TunnelRequestCoalescer.defaultSettlingWindow
        )
    }()

     
     
    private static let transitionalStates: Set<String> = [
        "connecting", "disconnecting", "reasserting",
    ]

     
     
     
    var clientPreferences: UserDefaults { preferences }

    @Published private(set) var applyingIPStackSettings = false
    @Published private(set) var ipStackSaveNotice = ""
    private let profileWriter: IPStackProfileWriter
    private var profileWriteIntentGeneration: UInt64 = 0


    @MainActor
    func updateIPStackSettings(_ settings: IPStackSettings) async throws {
        guard !applyingIPStackSettings, !connectionRequests.isBusy else {
            throw IPStackSettingsApplicationError.operationInProgress
        }
        let stopAtEntry = userStopEpoch
        applyingIPStackSettings = true
        defer { applyingIPStackSettings = false; ipStackSaveNotice = "" }
        var restoreInstalledProtocol: (() async throws -> Void)?
        try await IPStackSettingsApplication.apply(
            settings, defaults: preferences,
            saveProtocol: { [self] snapshot in
                let installed: NETunnelProviderManager?
                if let manager { installed = manager }
                else {
                    installed = try await Self.boundedLoadAll().first {
                        Self.isOwnedSystemVPNProfile($0, providerBundleIdentifier: extensionBundleID)
                    }
                }
                 
                guard let installed else { return }
                let previous = IPStackSystemProfileSnapshot(installed)
                installed.protocolConfiguration = try configuredProtocol(from: installed, ipStack: snapshot)
                do {
                    try await saveIPStackProfile(installed)
                    adoptManager(installed)
                    if userStopEpoch != stopAtEntry { installed.connection.stopVPNTunnel() }
                    restoreInstalledProtocol = { [self] in
                        previous.apply(to: installed, disarm: userStopEpoch != stopAtEntry)
                        try await saveIPStackProfile(installed)
                        if userStopEpoch != stopAtEntry { installed.connection.stopVPNTunnel() }
                    }
                } catch {
                    previous.apply(to: installed)
                    throw error
                }
            },
            restoreProtocol: { try await restoreInstalledProtocol?() },
            withProfileWrite: { [self] in try await profileWriter.settingsTransaction($0) },
            isRunning: { [self] in userStopEpoch == stopAtEntry && ["connected", "connecting", "reasserting"].contains(status) },
            restart: { [self] in
                guard await restartTunnel(site: .intentRestart) else {
                    throw NSError(domain: "HakoClient.IPStack", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: lastError.isEmpty
                            ? String(localized: "IP Stack settings were saved, but the VPN did not restart. Connect again to apply them.")
                            : lastError,
                    ])
                }
            }
        )
    }

    private func saveIPStackProfile(_ manager: NETunnelProviderManager) async throws {
        let frozen = IPStackSystemProfileSnapshot(manager)
        try await IPStackProfileWriter.awaitConfirmation(operation: { [self] in
            frozen.apply(to: manager)
            try await rawSaveToPreferences(manager)
        }, onWaiting: { [self] in
            ipStackSaveNotice = String(localized: "Waiting for the system to confirm the VPN settings. You can leave this page or stop the VPN.")
        })
        ipStackSaveNotice = ""
    }

     
     
     
     
     
     
    private enum LegacyKillSwitchPreferenceKey {
        static let killSwitch = "vpn.routing.killSwitch"
        static let allowLocalNetwork = "vpn.routing.allowLocalNetwork"
        static let deviceTestRoutingBackup = "vpn.routing.deviceTestBackup"
    }

    init(
        preferences: UserDefaults? = UserDefaults(suiteName: HakoAppIdentifiers.appGroup),
        operatingModeStore: NetworkOperatingModeStore? = nil,
         
         
         
         
        dnsOnlyConfigurationIsInstalled: (@Sendable () async -> Bool)? = nil,
        usesUITestFixtures: Bool = false,
        systemVPNManagers: (@MainActor () async throws -> [NETunnelProviderManager])? = nil,
        profileWriter: IPStackProfileWriter? = nil
    ) {
        let preferences = preferences ?? .standard
        self.preferences = preferences
        self.operatingModeStore = operatingModeStore
            ?? NetworkOperatingModeStore(defaults: preferences)
        self.dnsOnlyConfigurationIsInstalled = dnsOnlyConfigurationIsInstalled ?? {
            guard let snapshot = try? await NativeDNSOnlySettingsManager().load()
            else { return false }
            return snapshot != .notInstalled
        }
        self.usesUITestFixtures = usesUITestFixtures
        self.systemVPNManagers = systemVPNManagers ?? { try await Self.boundedLoadAll() }
        self.profileWriter = profileWriter ?? IPStackProfileWriter()
        clearLegacyKillSwitchPreferences()
        tunnelSettings = VPNTunnelSettings.load(from: preferences)
    }

     
    var session: NETunnelProviderSession? {
        manager?.connection as? NETunnelProviderSession
    }

    var reportableLastError: String {
        VPNDisconnectErrorPresentation.reportMessage(lastError)
    }

    var systemVPNProfileResetAvailable: Bool {
        VPNDisconnectErrorPresentation.allowsSystemVPNProfileReset(
            forReportMessage: reportableLastError
        )
    }

     
     
     
     
     
     
     
    func ensureStatusLoaded() async {
        if hasLoadedStatus { return }
        if let statusLoad { return await statusLoad.value }
        let load = Task { await self.loadInstalledManager() }
        statusLoad = load
        await load.value
        statusLoad = nil
    }

     
     
     
     
     
    private func loadInstalledManager() async {
        await refreshSystemVPNInstallation()
    }

     
     
     
    func refreshSystemVPNInstallation() async {
        _ = await refreshInstalledManagerIfIdle()
    }

    private func refreshInstalledManagerIfIdle() async -> Bool {
        guard !connectionRequests.isBusy, !profileWriter.isBusy else { return false }
        let intent = profileWriteIntentGeneration
        let writerRevision = profileWriter.revision
        installationReadGeneration &+= 1
        let readGeneration = installationReadGeneration
        func isCurrent() -> Bool {
            !Task.isCancelled && intent == profileWriteIntentGeneration
                && writerRevision == profileWriter.revision
                && readGeneration == installationReadGeneration
                && !connectionRequests.isBusy && !profileWriter.isBusy
        }
        do {
            let installed = try await systemVPNManagers().first {
                Self.isOwnedSystemVPNProfile($0, providerBundleIdentifier: extensionBundleID)
            }
            guard isCurrent() else { return false }
            let wasInstalled = manager != nil
            adoptManager(installed)
            if let installed {
                updateInstalledRoutingPolicy(from: installed)
                vpnAuthorization = nil
            } else if wasInstalled {
                vpnAuthorization = nil
            }
            if installationReadError != nil { lastError = "" }
            hasLoadedStatus = true
            updateStatus()
            return true
        } catch {
            guard isCurrent() else { return false }
             
            systemVPNInstallationKnown = false
            vpnAuthorization = nil
            lastError = VPNDisconnectErrorPresentation.startMessage(for: error as NSError)
            installationReadError = lastError
            return false
        }
    }

    func refresh() async {
        do {

            let recoveredInterruptedFixture = false
            let recoveredInterruptedPacketFlowProfile = false
            let recoveredInterruptedResourceProfile = false

            try await refreshConfigurationRoutingIntent()
            guard await refreshInstalledManagerIfIdle() else { return }
            let needsRecoveryApply = recoveredInterruptedFixture
                || recoveredInterruptedPacketFlowProfile
                || recoveredInterruptedResourceProfile
            if needsRecoveryApply {
                guard await applyRoutingPolicy(reconnectIfNeeded: true) else { return }


            }
            lastError = ""
        } catch {
            lastError = VPNDisconnectErrorPresentation.startMessage(
                for: error as NSError
            )
        }
    }

     
     
     
     
     
     
    @discardableResult
    func resetSystemVPNProfile() async -> Bool {
         
         
         
         
        guard !systemVPNProfileResetInFlight else { return false }
        systemVPNProfileResetInFlight = true
        defer { systemVPNProfileResetInFlight = false }
        startFailureTracker.cancelStart()

        do {
            if let observer {
                NotificationCenter.default.removeObserver(observer)
                self.observer = nil
            }

            let installedManagers = try await Self.boundedLoadAll()
            let hakoManagers = installedManagers.filter { installed in
                Self.isOwnedSystemVPNProfile(
                    installed,
                    providerBundleIdentifier: extensionBundleID
                )
            }

            for installed in hakoManagers {
                if Self.isActive(installed.connection.status) {
                    HakoLogStore.shared.append(
                        { let site = "replace-managers"; return "vpn stop requested  site=\(site)" }(),
                        stream: .app, level: .warning)
                    userStopInFlight = true
                    installed.connection.stopVPNTunnel()
                    try await waitUntilDisconnected(installed.connection)
                }
                try await boundedRemove(installed)
            }

            manager = nil
            let fresh = NETunnelProviderManager()
            let tunnel = try configuredProtocol(from: fresh)
            routingPolicy.apply(to: tunnel)
            fresh.protocolConfiguration = tunnel
            fresh.localizedDescription = Self.vpnProfileTitle
            fresh.isEnabled = true
            try applyOnDemand(to: fresh)
            try await boundedSave(fresh)
            try await boundedLoad(fresh)

            adoptManager(fresh)
            updateInstalledRoutingPolicy(from: fresh)
            routingPolicyNeedsApply = false
            updateStatus()
            lastError = ""
            configurationNotice = ""
             
             
            startFailureTracker.forgetInstantFailures()
            return true
        } catch {
            lastError = VPNDisconnectErrorPresentation.startMessage(
                for: error as NSError
            )
            updateStatus()
            return false
        }
    }

     
     
     
    static func isOwnedSystemVPNProfile(
        _ manager: NETunnelProviderManager,
        providerBundleIdentifier: String
    ) -> Bool {
        guard let tunnel = manager.protocolConfiguration
            as? NETunnelProviderProtocol else { return false }
        return tunnel.providerBundleIdentifier == providerBundleIdentifier
    }

    var routingPolicy: VPNRoutingPolicy {
        VPNRoutingPolicy(tunnel: tunnelSettings)
    }

     
     
     
     
     
    @discardableResult
    func updateTunnelSettings(_ settings: VPNTunnelSettings) async -> Bool {
        let previous = tunnelSettings
        guard settings != previous else { return true }
        settings.save(to: preferences)
        tunnelSettings = settings
        guard await applyRoutingPolicy(reconnectIfNeeded: true) else {
            previous.save(to: preferences)
            tunnelSettings = previous
            routingPolicyNeedsApply = installedRoutingPolicy != routingPolicy
            return false
        }
        return true
    }

    @discardableResult
    func applyRoutingPolicy(reconnectIfNeeded: Bool) async -> Bool {
        do {
            try await refreshConfigurationRoutingIntent()
            let mgr = try await currentOrNewManager()
            let wasActive = Self.isActive(mgr.connection.status)
            if wasActive && reconnectIfNeeded {
                HakoLogStore.shared.append(
                    { let site = "reconnect-for-config"; return "vpn stop requested  site=\(site)" }(),
                    stream: .app, level: .warning)
                userStopInFlight = true
                mgr.connection.stopVPNTunnel()
                try await waitUntilDisconnected(mgr.connection)
            }

            let tunnelProtocol = try configuredProtocol(from: mgr)
            routingPolicy.apply(to: tunnelProtocol)
            mgr.protocolConfiguration = tunnelProtocol
            mgr.localizedDescription = Self.vpnProfileTitle
            mgr.isEnabled = true
            try applyOnDemand(to: mgr)
            try await boundedSave(mgr)
            try await boundedLoad(mgr)
            adoptManager(mgr)
            updateInstalledRoutingPolicy(from: mgr)
            routingPolicyNeedsApply = false

            if wasActive && reconnectIfNeeded {
                try mgr.connection.startVPNTunnel()
                try await waitUntilConnected(mgr.connection)
            }
            updateStatus()
            lastError = ""
            return true
        } catch {
            lastError = "routing policy: \(error.localizedDescription)"
            return false
        }
    }

     
     
     
     
     
     
    private func stageConfig(settings: IPStackSettings) async throws -> String? {
        guard let container = HakoAppIdentifiers.appGroupContainer
        else {
            throw NSError(
                domain: "HakoClient.Configuration",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "App Group container unavailable"]
            )
        }
        let working = container.appendingPathComponent("working")
        try? FileManager.default.createDirectory(at: working, withIntermediateDirectories: true)
        try BundledGeodataProvisioner.seedAllMissing(into: working)
        try Self.ensureCoreSetup(container: container, settings: settings)

        let store = try ConfigResourceStore(containerURL: container)
        let profileStore = ProfileStore(
            fileURL: working.appendingPathComponent("store/profiles.json")
        )
        try LocalDefaultProfileProvisioner.provisionIfNeeded(
            store: profileStore,
            workingDirectory: working
        )
        try BundledProfileProvisioner.provisionExistingProfileIfNeeded(
            container: container
        )
        if try store.activePointer() == nil,
           try store.lastKnownGoodPointer() == nil {
             
             
             
            let profiles = profileStore.load()
            let profile = profiles.first {
                $0.id == LocalDefaultProfileProvisioner.profileID
            } ?? profiles.first {
                BundledProfileProvisioner.bundledSequence(for: $0.source) == 1
            }
            guard let profile else {
                throw NSError(
                    domain: "HakoClient.Configuration",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey:
                        "No local profile is available to start Clash"]
                )
            }
            let sidecar = working
                .appendingPathComponent("store/\(profile.id)", isDirectory: true)
                .appendingPathComponent("source.yaml")
            let sourceYAML: String
            if FileManager.default.fileExists(atPath: sidecar.path) {
                sourceYAML = try String(contentsOf: sidecar, encoding: .utf8)
            } else if BundledProfileProvisioner.bundledSequence(for: profile.source) == 1,
                      let configURL = Bundle.main.url(
                          forResource: "config",
                          withExtension: "yaml"
                      ) {
                sourceYAML = try String(contentsOf: configURL, encoding: .utf8)
            } else {
                throw NSError(
                    domain: "HakoClient.Configuration",
                    code: 3,
                    userInfo: [NSLocalizedDescriptionKey:
                        "The local profile source is unavailable"]
                )
            }
            try await activationCoordinator(store: store, container: container, settings: settings)
                .activate(profile: profile, sourceYAML: sourceYAML)
        }
        #if !os(tvOS)
        try await ProviderFirstLoadRetry.recoverCoreOwnedRoutesBeforeStart(container: container)
        #endif
        let preparation = try await ActiveRevisionMigrator(
            store: store,
            preflight: { PreflightService.check(finalYAML: $0, container: container, settings: settings) },
            rebuild: { [weak self] pointer in
                guard let self else {
                    throw PipelineError.sourceUnavailable(
                        "The client runtime compiler is unavailable."
                    )
                }
                return try await self.regenerateRuntime(
                    replacing: pointer,
                    store: store,
                    container: container,
                    settings: settings
                )
            }
        ).prepareForStart()
        guard let activeYAML = preparation.configuration.text else {
            throw ConfigResourceStoreError.configurationIsNotUTF8
        }
        applyConfigurationRoutingIntent(try AppConfigurationPreflight.inspectRoutingIntent(activeYAML, container: container, settings: settings))

        return preparation.userNotice
    }

     
     
     
    private func regenerateRuntime(
        replacing pointer: ActiveConfigurationPointer,
        store: ConfigResourceStore,
        container: URL,
        settings: IPStackSettings
    ) async throws -> ActiveConfigurationPointer {
        let working = container.appendingPathComponent("working", isDirectory: true)
        let profileStore = ProfileStore(
            fileURL: working.appendingPathComponent("store/profiles.json")
        )
        let profiles = profileStore.load()
        let profile = profiles.first { $0.id == pointer.profileID }
            ?? profiles.first { $0.activeRevision == pointer.revision }
            ?? {
                guard pointer.profileID == ConfigResourceStore.defaultProfileID else {
                    return nil
                }
                return profiles.first {
                    BundledProfileProvisioner.bundledSequence(for: $0.source) == 1
                }
            }()
        guard let profile else {
            throw PipelineError.sourceUnavailable(
                "The saved runtime has no matching source profile."
            )
        }

        let sidecar = working
            .appendingPathComponent("store/\(profile.id)", isDirectory: true)
            .appendingPathComponent("source.yaml")
        let coordinator = try activationCoordinator(store: store, container: container, settings: settings)
        if let source = try? String(contentsOf: sidecar, encoding: .utf8),
           !source.isEmpty {
            return try await coordinator.regenerateRuntime(
                profile: profile,
                storedSourceYAML: source,
                replacing: pointer
            )
        }

         
         
         
        if case .url = profile.source {
            let fetched = try await SubscriptionManager(
                downloader: ResourceDownloader(),
                credentials: CredentialStore()
            ).fetch(profile: profile, useConditionalValidators: false)
            guard let fetched else {
                throw PipelineError.sourceUnavailable(
                    "The profile URL did not provide a profile."
                )
            }
            return try await coordinator.regenerateRuntime(
                profile: profile,
                storedSourceYAML: fetched.yaml,
                sourceIsStoredSidecar: false,
                replacing: pointer
            )
        }

        if BundledProfileProvisioner.bundledSequence(for: profile.source) == 1,
           let configURL = Bundle.main.url(
               forResource: "config",
               withExtension: "yaml"
           ) {
            return try await coordinator.regenerateRuntime(
                profile: profile,
                storedSourceYAML: try String(contentsOf: configURL, encoding: .utf8),
                sourceIsStoredSidecar: false,
                replacing: pointer
            )
        }

        throw PipelineError.sourceUnavailable(
            "The local source file for this profile is unavailable."
        )
    }

     
     
     
    func activationCoordinator(store: ConfigResourceStore, container: URL, settings: IPStackSettings? = nil) throws -> ProfileActivationCoordinator {
        try Self.ensureCoreSetup(container: container, settings: settings)
        let working = container.appendingPathComponent("working")
        return ProfileActivationCoordinator(
            store: store,
            profileStore: ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json")),
            credentials: CredentialStore(),
            downloader: ResourceDownloader(),
            coreHomeDir: working,
             
             
             
             
             
             
            compileRuleSets: true,
            deferRuleSetCompilation: true,
            runtimeOverride: { [preferences = self.preferences] in
                FlClashRuntimeConfig.load(from: preferences)
            },
            activator: { _ in },
            preflight: { PreflightService.check(finalYAML: $0, container: container, settings: settings) })
    }

     
     
     
     
    func migrateLegacyGlobalSettingsIfNeeded() -> LegacyClientSettingsMigrationResult {
        guard let container = HakoAppIdentifiers.appGroupContainer else {
            return .init(
                globalConfig: .blocked(.storageUnavailable),
                globalScript: nil
            )
        }
        do { try Self.ensureCoreSetup(container: container) }
        catch {
            lastError = error.localizedDescription
            return .init(globalConfig: .blocked(.coreSetupFailed(error.localizedDescription)), globalScript: nil)
        }
        let working = container.appendingPathComponent("working")
        let globalConfig = LegacyGlobalConfigMigrationCoordinator.run(
            workingDirectory: working,
            defaults: preferences
        )
        guard globalConfig.userMessage.isEmpty else {
            return .init(globalConfig: globalConfig, globalScript: nil)
        }
        return .init(
            globalConfig: globalConfig,
            globalScript: LegacyGlobalScriptMigrationCoordinator.run(
                workingDirectory: working,
                defaults: preferences
            )
        )
    }

     
     
    private static func ensureCoreSetup(container: URL, settings: IPStackSettings? = nil) throws {
        try AppCoreSetup.ensure(container: container, settings: settings, memoryLimit: 50 * 1024 * 1024)
    }

     

    private var appliedConfigIntent: PlatformConfigIntent?

     
     
     
    func applyActiveConfiguration(nextIntent intent: PlatformConfigIntent) async {
        let tunnelUp: Bool
        switch manager?.connection.status {
        case .connected, .connecting, .reasserting: tunnelUp = true
        default: tunnelUp = false
        }
         
         
         
         
        if appliedConfigIntent == nil, tunnelUp,
           let stampJSON = TunnelIntentStamp.readJSON(from: preferences),
           let recovered = try? JSONDecoder().decode(
               PlatformConfigIntent.self, from: Data(stampJSON.utf8)
           ) {
            appliedConfigIntent = recovered
        }
        let succeeded: Bool
        switch ActivationDecision.decide(current: appliedConfigIntent, next: intent, tunnelUp: tunnelUp) {
        case .start:
            succeeded = await start(origin: .programmatic)
        case .reload:
             
             
             
             
             
             
            await awaitConnectedBeforeReload()
            guard !Task.isCancelled else { return }
            var reloaded = await sendReloadMessage()
             
             
             
             
             
             
            var attemptsLeft = 3
            while !reloaded,
                  ReloadRefusal.isRaceWithActivation(Self.lastReloadRefusal),
                   
                   
                   
                   
                   
                   
                   
                  session?.status == .connected,
                  attemptsLeft > 0 {
                attemptsLeft -= 1
                {
                    let why = Self.lastReloadRefusal ?? "unknown"
                    HakoLogStore.shared.append(
                        "reload raced activation, retrying  reason=\(why)",
                        stream: .app, level: .warning)
                }()
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                reloaded = await sendReloadMessage()
            }
            if reloaded {
                lastError = ""
                succeeded = true
            } else {
                 
                 
                 
                 
                 
                 
                {
                    let why = Self.lastReloadRefusal ?? "unknown"
                    HakoLogStore.shared.append(
                        "reload refused, restarting  reason=\(why)",
                        stream: .app, level: .warning)
                }()
                 
                 
                guard !Task.isCancelled else { return }
                succeeded = await restartTunnel(site: .reloadFallback)
            }
        case .restart:
            succeeded = await restartTunnel(site: .intentRestart)
        }
        if succeeded {
            appliedConfigIntent = intent
            configurationNotice = ""
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    nonisolated static func withNETimeout<T: Sendable>(
        seconds: Double,
        _ timeoutError: NETimeoutError,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let gate = NETimeoutGate(continuation)
            let timeout = Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                gate.resume(throwing: timeoutError)
            }
            Task {
                defer { timeout.cancel() }
                do {
                    gate.resume(returning: try await operation())
                } catch {
                    gate.resume(throwing: error)
                }
            }
        }
    }

     
    private func rawSaveToPreferences(_ manager: NETunnelProviderManager, disarmOnly: Bool = false) async throws {
        let frozen = IPStackSystemProfileSnapshot(manager)
        try await profileWriter.saveConfirmed(frozen, to: manager, disarmOnly: disarmOnly) {
            try await manager.saveToPreferences()
        }
    }

    private func boundedSave(_ manager: NETunnelProviderManager, whileIntent intent: UInt64? = nil, disarmOnly: Bool = false) async throws {
        let frozen = IPStackSystemProfileSnapshot(manager)
        try await Self.withNETimeout(seconds: 15, .nePreferencesTimeout) { [self] in
            try await profileWriter.run { [self] in
                if let intent, intent != profileWriteIntentGeneration { throw CancellationError() }
                frozen.apply(to: manager)
                try await rawSaveToPreferences(manager, disarmOnly: disarmOnly)
            }
        }
    }

     
    private func boundedLoad(_ manager: NETunnelProviderManager) async throws {
        try await Self.withNETimeout(seconds: 15, .nePreferencesTimeout) {
            try await manager.loadFromPreferences()
        }
    }

     
    private func boundedRemove(_ manager: NETunnelProviderManager) async throws {
        try await Self.withNETimeout(seconds: 15, .nePreferencesTimeout) {
            try await manager.removeFromPreferences()
        }
    }

     
    private static func boundedLoadAll() async throws -> [NETunnelProviderManager] {
        try await withNETimeout(seconds: 15, .nePreferencesTimeout) {
            try await NETunnelProviderManager.loadAllFromPreferences()
        }
    }

     
     
     
    private func sendReloadMessage() async -> Bool {
        guard let session, session.status == .connected else { return false }
        guard let payload = try? JSONSerialization.data(withJSONObject: ["cmd": "reload"]) else {
            return false
        }
        do {
            return try await Self.withNETimeout(seconds: 20, .extensionMessageTimeout) {
                try await withCheckedThrowingContinuation { continuation in
                    do {
                        try session.sendProviderMessage(payload) { reply in
                            guard let reply,
                                  let json = try? JSONSerialization.jsonObject(with: reply) as? [String: Any]
                            else {
                                { let why = "silent"; Self.lastReloadRefusal = "the extension replied \(why)" }()
                                continuation.resume(returning: false)
                                return
                            }
                            if let error = json["error"] as? String {
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                 
                                Self.lastReloadRefusal = error
                                continuation.resume(returning: false)
                                return
                            }
                            Self.lastReloadRefusal = nil
                            continuation.resume(returning: true)
                        }
                    } catch {
                        Self.lastReloadRefusal = error.localizedDescription
                        continuation.resume(returning: false)
                    }
                }
            }
        } catch {
             
             
            { let why = "unanswered"; Self.lastReloadRefusal = "the extension went \(why) for 20s" }()
            return false
        }
    }

     
     
     
     
     
    nonisolated(unsafe) private static var lastReloadRefusal: String?

    private func applyOnDemand(to manager: NETunnelProviderManager) throws {
        try OnDemandSettings.apply(OnDemandSettings.configuration(), to: manager)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    enum OnDemandSaveOutcome: Equatable {
        case applied
        case refused(String)
        case indeterminate(String)
    }

    func applyOnDemandSettingsReportingOutcome() async -> OnDemandSaveOutcome {
        do {
            let mgr = try await currentOrNewManager()
            try applyOnDemand(to: mgr)
            try await boundedSave(mgr)
            adoptManager(mgr)
            lastError = ""
            return .applied
        } catch let error as NETimeoutError {
            lastError = "on-demand: \(error.localizedDescription)"
            return .indeterminate(lastError)
        } catch {
            lastError = "on-demand: \(error.localizedDescription)"
            return .refused(lastError)
        }
    }

    @discardableResult
    func applyOnDemandSettings() async -> Bool {
        do {
            let mgr = try await currentOrNewManager()
            try applyOnDemand(to: mgr)
            try await boundedSave(mgr)
            adoptManager(mgr)
            lastError = ""
            return true
        } catch {
            lastError = "on-demand: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
     
     
     
     
     
     
     
    private func awaitConnectedBeforeReload() async {
        for _ in 0..<100 {
             
             
             
             
             
            if Task.isCancelled { return }
            switch manager?.connection.status {
            case .connecting, .reasserting:
                try? await Task.sleep(nanoseconds: 100_000_000)
            default:
                return
            }
        }
    }

    private func restartTunnel(site: VPNStopSite) async -> Bool {
         
         
         
         
         
         
         
        guard !Task.isCancelled else { return false }
        let epochAtEntry = userStopEpoch
        await stop(site: site)
        for _ in 0..<50 {  
            if Task.isCancelled { return false }
            let status = manager?.connection.status
            if status == .disconnected || status == .invalid || status == nil { break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        guard !Task.isCancelled else { return false }
         
         
         
        guard epochAtEntry == userStopEpoch else { return false }
        let started = await start(origin: .programmatic)
         
         
         
         
         
         
         
        if started, Task.isCancelled || epochAtEntry != userStopEpoch {
            await stop(site: site)
            return false
        }
        return started
    }

     
     
     
    func forceRestart() async {
        lastError = ""
        _ = await restartTunnel(site: .forceRestart)
    }

    private func stage(_ src: URL, to dst: URL) throws {
        try? FileManager.default.removeItem(at: dst)
        try FileManager.default.copyItem(at: src, to: dst)
    }

     
     
     
    func suspendPacketTunnelForDNSOnly() async -> Bool {
        do {
            let managers = try await Self.boundedLoadAll()
            guard let mgr = manager ?? managers.first else {
                status = "disconnected"
                lastError = ""
                return true
            }
            try await boundedLoad(mgr)
            if Self.isActive(mgr.connection.status) {
                HakoLogStore.shared.append(
                    { let site = "teardown"; return "vpn stop requested  site=\(site)" }(),
                    stream: .app, level: .warning)
                userStopInFlight = true
                mgr.connection.stopVPNTunnel()
                try await waitUntilDisconnected(mgr.connection)
            }
            mgr.isOnDemandEnabled = false
            mgr.isEnabled = false
            try await boundedSave(mgr)
            try await boundedLoad(mgr)
            adoptManager(mgr)
            updateStatus()
            lastError = ""
            return true
        } catch {
            lastError = "DNS-only: \(error.localizedDescription)"
            return false
        }
    }

     
     
     
    func restorePacketTunnelAfterDNSOnly() async -> Bool {
        do {
            let managers = try await Self.boundedLoadAll()
            guard let mgr = manager ?? managers.first else {
                lastError = ""
                return true
            }
            try await boundedLoad(mgr)
            mgr.isEnabled = true
            try applyOnDemand(to: mgr)
            try await boundedSave(mgr)
            try await boundedLoad(mgr)
            adoptManager(mgr)
            updateStatus()
            lastError = ""
            return true
        } catch {
            lastError = "restore VPN mode: \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
     
     
     
    func start(
        origin: TunnelRequestCoalescer.Origin = .gesture
    ) async -> Bool {
        do { try profileWriter.requireStartReady() }
        catch { lastError = error.localizedDescription; return false }
        let cancellation = VPNStartCancellation()
        return await withTaskCancellationHandler {
            await connectionRequests.run(origin: origin) { [weak self] in
                guard let self, !cancellation.isCancelled else { return false }
                self.profileWriteIntentGeneration &+= 1
                return await self.performStart(
                    writeIntent: self.profileWriteIntentGeneration, cancellation: cancellation)
            }
        } onCancel: {
            cancellation.cancel()
        }
    }

    private func performStart(writeIntent: UInt64, cancellation: VPNStartCancellation) async -> Bool {
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        if operatingModeStore.current == .dnsOnly {
            operatingModeStore.set(.packetTunnel)
        }
        let waitingMessage = String(localized: "Waiting for VPN authorization. Complete the system confirmation in Settings to continue.")
        let began = Date()
        var phase = "prepare"
        var needsAuthorization = false
        lastError = ""
        vpnAuthorization = nil
        func checkStartIntent() throws {
            try Task.checkCancellation()
            guard writeIntent == profileWriteIntentGeneration, !cancellation.isCancelled
            else { throw CancellationError() }
        }
        defer {
            if self.configurationNotice == waitingMessage { self.configurationNotice = "" }
            if vpnAuthorization == .waiting { vpnAuthorization = nil }
        }
        do {
            try checkStartIntent()
            let ipStack = try IPStackSettings.load(from: preferences)
            let configurationNotice = try await stageConfig(settings: ipStack)
            try checkStartIntent()
            let installed = try await loadSystemVPNStartProfile(isCurrent: {
                writeIntent == self.profileWriteIntentGeneration && !cancellation.isCancelled
            })
            try checkStartIntent()
            let mgr = installed.manager
            needsAuthorization = installed.needsAuthorization
            if needsAuthorization { vpnAuthorization = .waiting }
            let proto = try configuredProtocol(from: mgr, ipStack: ipStack)
            routingPolicy.apply(to: proto)
            mgr.protocolConfiguration = proto
            mgr.localizedDescription = Self.vpnProfileTitle
            mgr.isEnabled = true
            try applyOnDemand(to: mgr)
            let frozen = IPStackSystemProfileSnapshot(mgr)
            try await VPNStartAuthorization.perform(
                save: { [self] in
                    phase = "save"
                    try await profileWriter.run { [self] in
                        guard writeIntent == profileWriteIntentGeneration, !cancellation.isCancelled
                        else { throw CancellationError() }
                        frozen.apply(to: mgr)
                        HakoLogStore.shared.append("vpn authorization save began", stream: .app, level: .warning)
                        try await rawSaveToPreferences(mgr)
                        HakoLogStore.shared.append("vpn authorization save confirmed", stream: .app, level: .warning)
                    }
                },
                reload: { [self] in
                    phase = "reload"
                    vpnAuthorization = nil
                    try await boundedLoad(mgr)
                },
                start: { [self] in
                    phase = "start"
                    adoptManager(mgr)
                    updateInstalledRoutingPolicy(from: mgr)
                    routingPolicyNeedsApply = false
                    startFailureTracker.beginStart()
                    let before = connectionStatusLabel(mgr.connection.status)
                    try mgr.connection.startVPNTunnel()
                    updateStatus()
                    let after = connectionStatusLabel(mgr.connection.status)
                    HakoLogStore.shared.append(
                        "vpn start requested  before=\(before) after=\(after)",
                        stream: .app, level: .warning)
                    lastError = ""
                    self.configurationNotice = configurationNotice ?? ""
                    scheduleStartOutcomeWatchdog()
                },
                abort: { [self] in
                     
                     
                    await Task { @MainActor in
                        do {
                            try await profileWriter.run { [self] in
                                if mgr.isOnDemandEnabled {
                                    try await rawSaveToPreferences(mgr, disarmOnly: true)
                                }
                            }
                        } catch {
                            HakoLogStore.shared.append(
                                "vpn cancelled-start disarm failed: \(error)", stream: .app, level: .warning)
                        }
                        mgr.connection.stopVPNTunnel()
                    }.value
                },
                isCurrent: { [self] in
                    writeIntent == profileWriteIntentGeneration && !cancellation.isCancelled
                },
                onWaiting: { [weak self] in
                    guard let self, writeIntent == self.profileWriteIntentGeneration,
                          !cancellation.isCancelled else { return }
                    self.configurationNotice = waitingMessage
                    if needsAuthorization { self.vpnAuthorization = .waiting }
                    HakoLogStore.shared.append("vpn authorization still waiting", stream: .app, level: .warning)
                })
            return true
        } catch is CancellationError {
            startFailureTracker.cancelStart()
            HakoLogStore.shared.append("vpn start cancelled before request", stream: .app, level: .warning)
            return false
        } catch {
            startFailureTracker.cancelStart()
            guard writeIntent == profileWriteIntentGeneration,
                  !cancellation.isCancelled, !Task.isCancelled else {
                HakoLogStore.shared.append("vpn start cancelled during preparation", stream: .app, level: .warning)
                return false
            }
            let failure = error as NSError
            let elapsed = Int(Date().timeIntervalSince(began) * 1_000)
            HakoLogStore.shared.append(
                "vpn start refused  phase=\(phase) domain=\(failure.domain) code=\(failure.code) elapsedMs=\(elapsed) error=\(failure.localizedDescription) details=\(failure)",
                stream: .app, level: .warning)
            presentSystemVPNStartFailure(error, phase: phase, needsAuthorization: needsAuthorization)
            return false
        }
    }

    func presentSystemVPNStartFailure(_ error: Error, phase: String, needsAuthorization: Bool) {
        if needsAuthorization, phase == "save",
           VPNStartAuthorization.isPermissionDenial(error as NSError) {
            vpnAuthorization = .notCompleted
            lastError = ""
            return
        }
        vpnAuthorization = nil
        lastError = error is NETimeoutError ? error.localizedDescription
            : VPNDisconnectErrorPresentation.startMessage(for: error as NSError)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private static let startOutcomeDeadlineMilliseconds: UInt64 = 250

    private func scheduleStartOutcomeWatchdog() {
         
         
         
         
         
         
        guard startOutcomeWatchdog == nil else { return }
        startOutcomeWatchdog = Task { [weak self] in
            try? await Task.sleep(
                nanoseconds: Self.startOutcomeDeadlineMilliseconds * 1_000_000
            )
            guard !Task.isCancelled else { return }
            await self?.reportStartThatNeverMoved()
        }
    }

    private func reportStartThatNeverMoved() async {
        startOutcomeWatchdog = nil
        guard startFailureTracker.isAwaitingResult else { return }
        HakoLogStore.shared.append(
            {
                let window = Self.startOutcomeDeadlineMilliseconds
                return "vpn start never moved  window=\(window)ms"
            }(),
            stream: .app, level: .warning)
         
         
         
        await refreshLastDisconnectErrorAfterFailedStart()
    }

     
     
    nonisolated private func connectionStatusLabel(_ status: NEVPNStatus) -> String {
        switch status {
        case .invalid: return "invalid"
        case .disconnected: return "disconnected"
        case .connecting: return "connecting"
        case .connected: return "connected"
        case .reasserting: return "reasserting"
        case .disconnecting: return "disconnecting"
        @unknown default: return "unknown"
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func stop(
        site: VPNStopSite = .userButton,
        origin: TunnelRequestCoalescer.Origin? = nil,
        alongside: (@MainActor () -> Void)? = nil
    ) async {
        profileWriteIntentGeneration &+= 1
        let writeIntent = profileWriteIntentGeneration
        if applyingIPStackSettings { manager?.connection.stopVPNTunnel() }
        let origin = origin ?? (site == .userButton ? .gesture : .programmatic)
         
         
         
         
         
        if site == .userButton {
            userStopEpoch &+= 1
        }
        await connectionRequests.run(origin: origin) { [weak self] in
            alongside?()
            await self?.performStop(site: site, writeIntent: writeIntent)
            return false
        }
    }

    private func performStop(site: VPNStopSite, writeIntent: UInt64) async {
        startFailureTracker.cancelStart()
        guard let manager else { return }
        if Self.disarmOnDemandForUserStop(manager) || applyingIPStackSettings {
            do {
                try await boundedSave(manager, whileIntent: writeIntent, disarmOnly: true)
            } catch {
                 
                 
                 
            }
        }
        HakoLogStore.shared.append(
            { let label = site.rawValue; return "vpn stop requested  site=\(label)" }(),
            stream: .app, level: .warning)
         
         
         
         
         
         
         
        lastStopUserInitiated = true
        userStopInFlight = true
        if profileWriteIntentGeneration == writeIntent { manager.connection.stopVPNTunnel() }
    }

     
     
    private var userStopEpoch: UInt64 = 0

    private var lastStopUserInitiated = false
     
    func consumeUserInitiatedStop() -> Bool {
        defer { lastStopUserInitiated = false }
        return lastStopUserInitiated
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private(set) var reachedConnectedSinceStart = false

     
     
     
     
     
     
     
     
     
     
     
    private(set) var sawStartAttempt = false

     
     
    var lastStartFailed: Bool { sawStartAttempt && !reachedConnectedSinceStart }

     
     
     
    @discardableResult
    nonisolated static func disarmOnDemandForUserStop(
        _ manager: NETunnelProviderManager
    ) -> Bool {
        guard manager.isOnDemandEnabled else { return false }
        manager.isOnDemandEnabled = false
        return true
    }

    private func configuredProtocol(from manager: NETunnelProviderManager, ipStack: IPStackSettings? = nil) throws -> NETunnelProviderProtocol {
        let tunnelProtocol = (manager.protocolConfiguration?.copy() as? NETunnelProviderProtocol)
            ?? NETunnelProviderProtocol()
        let snapshot = try ipStack ?? IPStackSettings.load(from: preferences)
        tunnelProtocol.providerConfiguration = try snapshot.applying(to: tunnelProtocol.providerConfiguration)
        tunnelProtocol.providerBundleIdentifier = extensionBundleID
        tunnelProtocol.serverAddress = Self.vpnProfileDescription
         
         
        tunnelProtocol.disconnectOnSleep = OnDemandSettings.configuration().disconnectOnSleep
        return tunnelProtocol
    }

    struct SystemVPNStartProfile {
        let manager: NETunnelProviderManager
        let needsAuthorization: Bool
    }

    func loadSystemVPNStartProfile(isCurrent: () -> Bool) async throws -> SystemVPNStartProfile {
        let intent = profileWriteIntentGeneration
        try Task.checkCancellation()
        guard isCurrent(), intent == profileWriteIntentGeneration else { throw CancellationError() }
        let installed: NETunnelProviderManager?
        do {
            let managers = try await systemVPNManagers()
            let owned = managers.filter {
                Self.isOwnedSystemVPNProfile($0, providerBundleIdentifier: extensionBundleID)
            }
            installed = owned.first
            // 2026-10-21：`.first` 可能选中陈旧配置（状态还写着 connected，
            // 背后扩展进程早已不在）——那样 sendProviderMessage 会永远无回音。
            // 把候选与选中的状态记下来，日志里一眼能看出是不是僵尸配置。
            noteSystemVPNProfileSelection(site: "start", candidates: owned, chosen: installed)
        } catch {
            try Task.checkCancellation()
            guard isCurrent(), intent == profileWriteIntentGeneration else { throw CancellationError() }
            systemVPNInstallationKnown = false
            throw error
        }
        try Task.checkCancellation()
        guard isCurrent(), intent == profileWriteIntentGeneration else { throw CancellationError() }
         
         
        adoptManager(installed)
        hasLoadedStatus = true
        updateStatus()
        return SystemVPNStartProfile(
            manager: installed ?? NETunnelProviderManager(),
            needsAuthorization: installed == nil)
    }

    private func currentOrNewManager() async throws -> NETunnelProviderManager {
        if let manager { return manager }
        let managers = try await systemVPNManagers()
        if let installed = managers.first {
            return installed
        }
        return NETunnelProviderManager()
    }

     
     
     
     
    private func clearLegacyKillSwitchPreferences() {
        preferences.removeObject(forKey: LegacyKillSwitchPreferenceKey.killSwitch)
        preferences.removeObject(forKey: LegacyKillSwitchPreferenceKey.allowLocalNetwork)
        preferences.removeObject(forKey: LegacyKillSwitchPreferenceKey.deviceTestRoutingBackup)
    }

    private func updateInstalledRoutingPolicy(from manager: NETunnelProviderManager) {
        guard let tunnelProtocol = manager.protocolConfiguration as? NETunnelProviderProtocol else { return }
        let installed = VPNRoutingPolicy.installed(from: tunnelProtocol)
        let changed = installed != installedRoutingPolicy
        installedRoutingPolicy = installed
        routingPolicyNeedsApply = installedRoutingPolicy != routingPolicy
         
         
         
         
        if changed {
            HakoLogStore.shared.append(
                "vpn profile installed  includeAllNetworks=\(installed.includeAllNetworks) "
                    + "excludeLocalNetworks=\(installed.excludeLocalNetworks) "
                    + "enforceRoutes=\(installed.enforceRoutes) "
                    + "excludeAPNs=\(installed.excludeAPNs) "
                    + "excludeCellularServices=\(installed.excludeCellularServices) "
                    + "excludeDeviceCommunication=\(installed.excludeDeviceCommunication) "
                    + "disconnectOnSleep=\(tunnelProtocol.disconnectOnSleep) "
                    + "onDemand=\(manager.isOnDemandEnabled)",
                stream: .app, level: .warning)
        }
    }

    private func refreshConfigurationRoutingIntent() async throws {
        let ipStack = try IPStackSettings.load(from: preferences)
        if let container = HakoAppIdentifiers.appGroupContainer {
            do {
                let intent = try await Task.detached {
                    let stored = try ConfigResourceStore(containerURL: container).loadCurrent()
                    guard let content = stored.text else {
                        throw ConfigResourceStoreError.configurationIsNotUTF8
                    }
                    return try AppConfigurationPreflight.inspectRoutingIntent(content, settings: ipStack)
                }.value
                applyConfigurationRoutingIntent(intent)
                return
            } catch ConfigResourceStoreError.noValidConfiguration {
                 
                 
            }
        }
        guard let bundled = Bundle.main.url(forResource: "config", withExtension: "yaml") else { return }
        let content = try String(contentsOf: bundled, encoding: .utf8)
        let intent = try await Task.detached {
            try AppConfigurationPreflight.inspectRoutingIntent(content, settings: ipStack)
        }.value
        applyConfigurationRoutingIntent(intent)
    }

    private func applyConfigurationRoutingIntent(_ configContent: String) throws {
        applyConfigurationRoutingIntent(
            try AppConfigurationPreflight.inspectRoutingIntent(configContent)
        )
    }

    private func applyConfigurationRoutingIntent(_ intent: PlatformConfigIntent) {
         
         
        configuredIncludedRouteCount = intent.includedRouteCount
        configuredExcludedRouteCount = intent.excludedRouteCount
    }



    private static func isActive(_ status: NEVPNStatus) -> Bool {
        switch status {
        case .connecting, .connected, .reasserting:
            return true
        default:
            return false
        }
    }

    private func waitUntilDisconnected(_ connection: NEVPNConnection) async throws {
        for _ in 0..<100 {
            if connection.status == .disconnected || connection.status == .invalid { return }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(
            domain: "HakoClient.VPNRoutingPolicy",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "timed out waiting for VPN disconnect"]
        )
    }

    private func waitUntilConnected(_ connection: NEVPNConnection) async throws {
        for _ in 0..<450 {
            if connection.status == .connected || connection.status == .reasserting { return }
             
             
            if connection.status == .invalid {
                throw NSError(
                    domain: "HakoClient.VPNRoutingPolicy",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "VPN profile became invalid while applying routing policy"]
                )
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        throw NSError(
            domain: "HakoClient.VPNRoutingPolicy",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "timed out waiting for VPN reconnect"]
        )
    }

     
     
     
     
     
     
     
     
     
     
     
    private func adoptManager(_ mgr: NETunnelProviderManager?) {
        manager = mgr
        systemVPNInstallationKnown = true
        // 控制通道的诊断锚点：App 之后所有 provider message 都发给这条
        // connection。名字/状态/session 类型对不上，就是「发给了错的对象」。
        let status = mgr.map { connectionStatusLabel($0.connection.status) } ?? "nil"
        let kind = (mgr?.connection as? NETunnelProviderSession) != nil ? "provider" : "other"
        HakoLogStore.shared.append(
            "vpn manager adopt name=\(mgr?.localizedDescription ?? "nil") status=\(status) session=\(kind)",
            stream: .app, level: .info, force: true
        )
        observeStatus()
    }

    private func noteSystemVPNProfileSelection(
        site: String,
        candidates: [NETunnelProviderManager],
        chosen: NETunnelProviderManager?
    ) {
        let detail = candidates.map {
            "\($0.localizedDescription ?? "?")=\(connectionStatusLabel($0.connection.status))"
        }.joined(separator: ",")
        HakoLogStore.shared.append(
            "vpn profile select site=\(site) candidates=\(candidates.count) [\(detail)] chosen=\(chosen?.localizedDescription ?? "nil")",
            stream: .app, level: .info, force: true
        )
    }

    private func observeStatus() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        guard let connection = manager?.connection else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .NEVPNStatusDidChange, object: connection, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.handleStatusChange() }
        }
    }

    private func handleStatusChange() async {
        connectionStatusGeneration &+= 1
        guard let connection = manager?.connection else {
            updateStatus()
            return
        }
        updateStatus()
        if disconnectNoticeTracker.observe(
            connection.status,
            userInitiated: userStopInFlight,
            enabled: OnDemandSettings.configuration().showDisconnectMessage
        ) {
            VPNDisconnectNotice.post()
        }
        if connection.status == .connecting || connection.status == .connected {
            userStopInFlight = false
        }
         
         
         
         
         
         
         
        HakoLogStore.shared.append(
            {
                let label = connectionStatusLabel(connection.status)
                return "vpn status changed  to=\(label)"
            }(),
            stream: .app, level: .warning)
         
         
         
        startOutcomeWatchdog?.cancel()
        startOutcomeWatchdog = nil
        if connection.status == .connected || connection.status == .reasserting
            || connection.status == .connecting
        {
             
             
             
             
            lastError = ""
        }
        if connection.status == .connected || connection.status == .reasserting {
             
             
             
             
            #if !os(tvOS)
            if !reachedConnectedSinceStart, connection.status == .connected {
                 
                 
                 
                 
                 
                ProviderFirstLoadRetry.kick(trigger: .connected)
            }
            #endif
            reachedConnectedSinceStart = true
        }
        if connection.status == .connecting {
            reachedConnectedSinceStart = false
             
             
             
             
            sawStartAttempt = true
        }
        if startFailureTracker.statusDidChange(to: connection.status) {
            await resolveLastDisconnectError(on: connection)
        }
    }

    func refreshLastDisconnectErrorAfterFailedStart() async {
         
         
        guard startFailureTracker.isAwaitingResult,
              lastError.isEmpty,
              let connection = manager?.connection,
              connection.status == .disconnected || connection.status == .invalid
        else { return }
        startFailureTracker.cancelStart()
        await resolveLastDisconnectError(on: connection)
    }

    private func resolveLastDisconnectError(on connection: NEVPNConnection) async {
        let intent = profileWriteIntentGeneration
        let statusGeneration = connectionStatusGeneration
        await VPNStartAuthorization.resolveFailure(
            fetch: { [self] in await fetchLastDisconnectError(on: connection) },
            isCurrent: { [self] in
                manager?.connection === connection
                    && profileWriteIntentGeneration == intent
                    && connectionStatusGeneration == statusGeneration
                    && (connection.status == .disconnected || connection.status == .invalid)
            },
            publish: { [self] error in
                if let error {
                     
                     
                     
                     
                     
                     
                     
                     
                    HakoLogStore.shared.append(
                        {
                            let domain = error.domain
                            let code = error.code
                            return "vpn disconnect error  domain=\(domain) code=\(code)"
                        }(),
                        stream: .app, level: .warning)
                    lastError = VPNDisconnectErrorPresentation.message(
                        for: error,
                        providerLooksUnlaunched: startFailureTracker.providerLooksUnlaunched
                    )
                } else {
                    lastError = VPNDisconnectErrorPresentation.genericStartFailureMessage
                }
            })
    }

    private func fetchLastDisconnectError(on connection: NEVPNConnection) async -> NSError? {
        guard #available(iOS 16.0, *) else { return nil }
        return await withCheckedContinuation { continuation in
            let gate = VPNDisconnectErrorFetchGate(continuation)
            connection.fetchLastDisconnectError { error in
                gate.resolve(error as NSError?)
            }
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                gate.resolve(nil)
            }
        }
    }

    private func updateStatus() {
        guard let connection = manager?.connection else { status = "not installed"; return }
        switch connection.status {
        case .invalid: status = "invalid"
        case .disconnected: status = "disconnected"
        case .connecting: status = "connecting"
        case .connected: status = "connected"
        case .reasserting: status = "reasserting"
        case .disconnecting: status = "disconnecting"
        @unknown default: status = "unknown"
        }
    }
}
