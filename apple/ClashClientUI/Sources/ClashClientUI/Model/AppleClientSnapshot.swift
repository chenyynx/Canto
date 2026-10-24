import Foundation
import ClashClientKit

public enum AppleClientCapability: String, CaseIterable, Codable, Hashable, Sendable {
    case home
    case profiles
    case proxies
    case activity
    case rules
    case dns
    case utilities
    case more
    case systemIntegration
    case configuration
    case connection
    case profileSelection
    case outboundMode
    case routingPolicy
    case egressLookup
    case memoryMaintenance
    case refresh
    case cancellation
}

public enum AppleClientUnavailableReason: String, Codable, Equatable, Sendable {
    case notProvidedByAdapter
    case unsupportedPlatform
    case requiresProfile
    case requiresConnection
    case permissionDenied
    case busy
}

public enum AppleClientCapabilityAvailability: Codable, Equatable, Sendable {
    case available
    case unavailable(AppleClientUnavailableReason)
}

public enum AppleClientCompositionError: Error, Equatable, Sendable {
    case duplicateCapability(AppleClientCapability)
}

 
 
public struct AppleClientCapabilities: Codable, Equatable, Sendable {
    private var states: [AppleClientCapability: AppleClientCapabilityAvailability]

    public init(
        _ states: [AppleClientCapability: AppleClientCapabilityAvailability] = [:]
    ) {
        self.states = states
    }

    public var declaredCapabilities: Set<AppleClientCapability> {
        Set(states.keys)
    }

    public func availability(
        for capability: AppleClientCapability
    ) -> AppleClientCapabilityAvailability {
        states[capability] ?? .unavailable(.notProvidedByAdapter)
    }

    public func combining(
        _ other: AppleClientCapabilities
    ) throws -> AppleClientCapabilities {
        var combined = states
        for (capability, availability) in other.states {
            guard combined[capability] == nil else {
                throw AppleClientCompositionError.duplicateCapability(capability)
            }
            combined[capability] = availability
        }
        return AppleClientCapabilities(combined)
    }

    public static func composing(
        _ components: [AppleClientCapabilities]
    ) throws -> AppleClientCapabilities {
        try components.reduce(AppleClientCapabilities()) { partial, component in
            try partial.combining(component)
        }
    }
}

public enum AppleClientConnectionPhase: String, Codable, Equatable, Sendable {
    case disconnected
    case preparing
    case connected
    case disconnecting
    case unavailable
}

public enum AppleClientConnectionIntent: String, Codable, Equatable, Sendable {
    case activateSystemExtension
    case updateSystemExtension
    case installConfiguration
    case connect
    case disconnect
}

public enum AppleClientOutboundMode: String, CaseIterable, Codable, Equatable, Sendable {
    case global
    case rule
    case direct
}

public enum AppleClientOperation: String, Codable, Hashable, Sendable {
    case profileImport
    case latencyTests
    case resourceUpdate
    case diagnostics
}

public enum AppleClientFailureCode: String, Codable, Equatable, Sendable {
    case configuration
    case connection
    case refresh
    case maintenance
    case unknown
}

 
 
 
public struct AppleClientFailure: Codable, Equatable, Sendable {
    public let code: AppleClientFailureCode
    public let title: String
    public let message: String

    public init(
        code: AppleClientFailureCode,
        title: String,
        message: String
    ) {
        self.code = code
        self.title = String(title.prefix(160))
        self.message = String(message.prefix(512))
    }
}

public struct AppleClientProfileSnapshot: Codable, Equatable, Sendable {
    public let id: Profile.ID
    public let label: String

    public init(id: Profile.ID, label: String) {
        self.id = id
        self.label = String(label.prefix(256))
    }
}

public struct AppleClientConnectionSnapshot: Codable, Equatable, Sendable {
    public let phase: AppleClientConnectionPhase
    public let primaryIntent: AppleClientConnectionIntent?
    public let selectedRouteName: String?
    public let selectedRouteDelayMilliseconds: Int?
    public let issue: AppleClientFailure?

    public init(
        phase: AppleClientConnectionPhase,
        primaryIntent: AppleClientConnectionIntent? = nil,
        selectedRouteName: String? = nil,
        selectedRouteDelayMilliseconds: Int? = nil,
        issue: AppleClientFailure? = nil
    ) {
        self.phase = phase
        self.primaryIntent = primaryIntent ?? Self.defaultIntent(for: phase)
        self.selectedRouteName = selectedRouteName.map { String($0.prefix(256)) }
        self.selectedRouteDelayMilliseconds = selectedRouteDelayMilliseconds.flatMap {
            (0...3_600_000).contains($0) ? $0 : nil
        }
        self.issue = issue
    }

    private static func defaultIntent(
        for phase: AppleClientConnectionPhase
    ) -> AppleClientConnectionIntent? {
        switch phase {
        case .disconnected:
            .connect
        case .connected:
            .disconnect
        case .preparing, .disconnecting, .unavailable:
            nil
        }
    }
}

public struct AppleClientTrafficSnapshot: Codable, Equatable, Sendable {
    public let uploadBytesPerSecond: Int64
    public let downloadBytesPerSecond: Int64
    public let uploadTotalBytes: Int64
    public let downloadTotalBytes: Int64
     
     
     
     
     
     
     
    public let uploadRatesBytesPerSecond: [Int64]
    public let downloadRatesBytesPerSecond: [Int64]
     
     
     
     
     
    public let coreStartedAtUnixSeconds: Int64

    public init(
        uploadBytesPerSecond: Int64 = 0,
        downloadBytesPerSecond: Int64 = 0,
        uploadTotalBytes: Int64 = 0,
        downloadTotalBytes: Int64 = 0,
        uploadRatesBytesPerSecond: [Int64] = [],
        downloadRatesBytesPerSecond: [Int64] = [],
        coreStartedAtUnixSeconds: Int64 = 0
    ) {
        self.uploadBytesPerSecond = max(0, uploadBytesPerSecond)
        self.downloadBytesPerSecond = max(0, downloadBytesPerSecond)
        self.uploadTotalBytes = max(0, uploadTotalBytes)
        self.downloadTotalBytes = max(0, downloadTotalBytes)
        self.uploadRatesBytesPerSecond =
            uploadRatesBytesPerSecond.suffix(30).map { max(0, $0) }
        self.downloadRatesBytesPerSecond =
            downloadRatesBytesPerSecond.suffix(30).map { max(0, $0) }
        self.coreStartedAtUnixSeconds = max(0, coreStartedAtUnixSeconds)
    }

    public static let zero = AppleClientTrafficSnapshot()
}

public enum ClashActivityPhase: String, Codable, Equatable, Sendable {
    case disconnected
    case loading
    case ready
    case failed
}

public enum ClashActivityDetailAvailability:
    String,
    Codable,
    Equatable,
    Sendable
{
    case summaryOnly
    case full
}

 
 
 
 
 
public struct ClashActivitySnapshot: Codable, Equatable, Sendable {
    public static let connectionLimit = 2_000
    public static let requestLimit = 500
    public static let logLineLimit = 1_000

    public let phase: ClashActivityPhase
    public let activeConnectionCount: Int
    public let recentLogCount: Int
    public let traffic: AppleClientTrafficSnapshot
    public let detailAvailability: ClashActivityDetailAvailability
    public let errorDescription: String?
    public let connections: [ClashActivityConnectionSnapshot]
    public let requests: [ClashActivityRequestSnapshot]
    public let logLines: [String]
    public let closingConnectionIDs: Set<String>
    public let isClosingAll: Bool
    public let canManageConnections: Bool
    public let canClearLogs: Bool
    public let canExportLogs: Bool
     
    public let isRecordingLogs: Bool?
     
     
    public let logRetentionOptions: [ClashLogRetentionOption]
    public let logRetention: String?
     
    public let logRetentionSummary: String?
     
     
     
    public let logSeverityFilter: [String]
     
    public let activeProfileLogLevel: String?
     
     
    public let logLevelDirective: String?

    public init(
        phase: ClashActivityPhase,
        activeConnectionCount: Int = 0,
        recentLogCount: Int = 0,
        traffic: AppleClientTrafficSnapshot = .zero,
        detailAvailability: ClashActivityDetailAvailability = .summaryOnly,
        errorDescription: String? = nil,
        connections: [ClashActivityConnectionSnapshot] = [],
        requests: [ClashActivityRequestSnapshot] = [],
        logLines: [String] = [],
        closingConnectionIDs: Set<String> = [],
        isClosingAll: Bool = false,
        canManageConnections: Bool = false,
        canClearLogs: Bool = false,
        canExportLogs: Bool = false,
        isRecordingLogs: Bool? = nil,
        logRetentionOptions: [ClashLogRetentionOption] = [],
        logRetention: String? = nil,
        logRetentionSummary: String? = nil,
        logSeverityFilter: [String] = [],
        activeProfileLogLevel: String? = nil,
        logLevelDirective: String? = nil
    ) {
        self.phase = phase
        self.activeConnectionCount = max(0, activeConnectionCount)
        self.recentLogCount = max(0, recentLogCount)
        self.traffic = traffic
        self.detailAvailability = detailAvailability
        self.errorDescription = errorDescription.map {
            String($0.prefix(512))
        }
        self.connections = Array(
            connections.prefix(Self.connectionLimit)
        )
        self.requests = Array(
            requests.prefix(Self.requestLimit)
        )
        self.logLines = Array(
            logLines.suffix(Self.logLineLimit)
        )
        self.closingConnectionIDs =
            closingConnectionIDs.intersection(
                Set(self.connections.map(\.id))
            )
        self.isClosingAll = isClosingAll
        self.canManageConnections = canManageConnections
        self.canClearLogs = canClearLogs
        self.canExportLogs = canExportLogs
        self.isRecordingLogs = isRecordingLogs
        self.logRetentionOptions = logRetentionOptions
        self.logRetention = logRetention
        self.logRetentionSummary = logRetentionSummary
        self.logSeverityFilter = logSeverityFilter
        self.activeProfileLogLevel = activeProfileLogLevel
        self.logLevelDirective = logLevelDirective
    }

    public static let disconnected = Self(phase: .disconnected)
    public static let loading = Self(phase: .loading)
    public static let readyEmpty = Self(phase: .ready)

    public static func failed(_ message: String) -> Self {
        Self(phase: .failed, errorDescription: message)
    }
}

public struct AppleClientRoutingSnapshot: Codable, Equatable, Sendable {
    public let mode: AppleClientOutboundMode
    public let strictRouteEnabled: Bool
    public let includedRouteCount: Int
    public let excludedRouteCount: Int
    public let deviceCommunicationBypassEnabled: Bool
    public let needsApply: Bool

    public init(
        mode: AppleClientOutboundMode,
        strictRouteEnabled: Bool = false,
        includedRouteCount: Int = 0,
        excludedRouteCount: Int = 0,
        deviceCommunicationBypassEnabled: Bool = false,
        needsApply: Bool = false
    ) {
        self.mode = mode
        self.strictRouteEnabled = strictRouteEnabled
        self.includedRouteCount = max(0, includedRouteCount)
        self.excludedRouteCount = max(0, excludedRouteCount)
        self.deviceCommunicationBypassEnabled = deviceCommunicationBypassEnabled
        self.needsApply = needsApply
    }
}

public struct AppleClientHomeSnapshot: Codable, Equatable, Sendable {
    public let routing: AppleClientRoutingSnapshot
    public let traffic: AppleClientTrafficSnapshot
    public let proxyGroupCount: Int
    public let proxyCount: Int
    public let ruleCount: Int
    public let connection: ClashHomeConnectionPresentation
    public let initialSection: ClashHomeSection
    public let favoriteCards: [ClashHomeCard]
    public let trafficScope: ClashHomeTrafficScope
    public let proxies: ClashHomeDomainSnapshot
    public let rules: ClashHomeDomainSnapshot
    public let egress: ClashHomeEgressSnapshot
    public let lanAddress: String?
    public let isProfileActionInFlight: Bool
     
     
     
     
     
    public let selectedProfileIsSystemFallback: Bool
     
     
     
     
     
    public let profilesLoaded: Bool
     
     
     
    public let profilesUnavailableReason: String?

    public init(
        routing: AppleClientRoutingSnapshot = AppleClientRoutingSnapshot(mode: .rule),
        traffic: AppleClientTrafficSnapshot = .zero,
        proxyGroupCount: Int = 0,
        proxyCount: Int = 0,
        ruleCount: Int = 0,
        connection: ClashHomeConnectionPresentation = .unavailable,
        initialSection: ClashHomeSection = .common,
        favoriteCards: [ClashHomeCard] = ClashHomeCatalog.defaultCards,
        trafficScope: ClashHomeTrafficScope = .allTraffic,
        proxies: ClashHomeDomainSnapshot = .empty,
        rules: ClashHomeDomainSnapshot = .empty,
        egress: ClashHomeEgressSnapshot = .unavailable,
        lanAddress: String? = nil,
        isProfileActionInFlight: Bool = false,
        selectedProfileIsSystemFallback: Bool = false,
        profilesLoaded: Bool = true,
        profilesUnavailableReason: String? = nil
    ) {
        self.routing = routing
        self.traffic = traffic
        self.proxyGroupCount = max(0, proxyGroupCount)
        self.proxyCount = max(0, proxyCount)
        self.ruleCount = max(0, ruleCount)
        self.connection = connection
        self.initialSection = initialSection
        self.favoriteCards = ClashHomeCatalog.normalized(favoriteCards)
        self.trafficScope = trafficScope
        self.proxies = proxies
        self.rules = rules
        self.egress = egress
        self.lanAddress = lanAddress.map { String($0.prefix(128)) }
        self.isProfileActionInFlight = isProfileActionInFlight
        self.selectedProfileIsSystemFallback = selectedProfileIsSystemFallback
        self.profilesLoaded = profilesLoaded
        self.profilesUnavailableReason = profilesUnavailableReason.map { String($0.prefix(600)) }
    }
}

 
 
 
public struct AppleClientSnapshot: Codable, Equatable, Sendable {
    public let revision: UInt64
    public let selectedProfile: AppleClientProfileSnapshot?
    public let connection: AppleClientConnectionSnapshot
    public let home: AppleClientHomeSnapshot
    public let profiles: ClashProfilesSnapshot
    public let proxies: ClashProxiesSnapshot
    public let activity: ClashActivitySnapshot
    public let rules: ClashRulesSnapshot
    public let dns: ClashDNSSnapshot
    public let utilities: ClashUtilitiesSnapshot
    public let more: ClashMoreSnapshot
    public let capabilities: AppleClientCapabilities
    public let activeOperations: Set<AppleClientOperation>
    public let failure: AppleClientFailure?

    public init(
        revision: UInt64,
        selectedProfile: AppleClientProfileSnapshot? = nil,
        connection: AppleClientConnectionSnapshot,
        home: AppleClientHomeSnapshot = AppleClientHomeSnapshot(),
        profiles: ClashProfilesSnapshot = .empty,
        proxies: ClashProxiesSnapshot = .empty,
        activity: ClashActivitySnapshot = .disconnected,
        rules: ClashRulesSnapshot = .empty,
        dns: ClashDNSSnapshot = .empty,
        utilities: ClashUtilitiesSnapshot = .empty,
        more: ClashMoreSnapshot = .empty,
        capabilities: AppleClientCapabilities = AppleClientCapabilities(),
        activeOperations: Set<AppleClientOperation> = [],
        failure: AppleClientFailure? = nil
    ) {
        self.revision = revision
        self.selectedProfile = selectedProfile
        self.connection = connection
        self.home = home
        self.profiles = profiles
        self.proxies = proxies
        self.activity = activity
        self.rules = rules
        self.dns = dns
        self.utilities = utilities
        self.more = more
        self.capabilities = capabilities
        self.activeOperations = activeOperations
        self.failure = failure
    }

    public static let empty = AppleClientSnapshot(
        revision: 0,
        connection: AppleClientConnectionSnapshot(phase: .unavailable)
    )
}
