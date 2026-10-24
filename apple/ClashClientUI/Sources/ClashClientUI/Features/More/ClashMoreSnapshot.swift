import Foundation

public struct ClashAboutSnapshot: Codable, Equatable, Sendable {
    public let appVersion: String
     
     
    public let buildNumber: String
     
     
    public let sourceRevision: String
    public let coreVersion: String

    public init(
        appVersion: String = "—",
        buildNumber: String = "",
        sourceRevision: String = "",
        coreVersion: String = "—"
    ) {
        self.appVersion = String(appVersion.prefix(128))
        self.buildNumber = String(buildNumber.prefix(64))
        self.sourceRevision = String(sourceRevision.prefix(64))
        self.coreVersion = String(coreVersion.prefix(128))
    }

     
     
    public var versionLine: String {
        buildNumber.isEmpty
            ? appVersion
            : "\(appVersion) (\(buildNumber))"
    }
}

public struct ClashMoreSnapshot: Codable, Equatable, Sendable {
    public let onDemandEnabled: Bool
    public let onDemandRuleCount: Int
     
     
     
    public let tunnelIncludeAllNetworks: Bool
    public let showsDeveloperDestination: Bool
    public let about: ClashAboutSnapshot
     
     
     
     
     
     
     
     
     
     
     
    public let overrideCounts: [ClashMoreDestination: Int]
     
     
     
     
    public let attention: ClashMoreAttention?

    public init(
        onDemandEnabled: Bool = false,
        onDemandRuleCount: Int = 0,
        tunnelIncludeAllNetworks: Bool = false,
        showsDeveloperDestination: Bool = false,
        about: ClashAboutSnapshot = ClashAboutSnapshot(),
        overrideCounts: [ClashMoreDestination: Int] = [:],
        attention: ClashMoreAttention? = nil
    ) {
        self.onDemandEnabled = onDemandEnabled
        self.onDemandRuleCount = max(0, onDemandRuleCount)
        self.tunnelIncludeAllNetworks = tunnelIncludeAllNetworks
        self.showsDeveloperDestination = showsDeveloperDestination
        self.about = about
        self.overrideCounts = overrideCounts.filter { $0.value > 0 }
        self.attention = attention
    }

     
     
    func overrideSubtitle(for destination: ClashMoreDestination) -> ClashDisplayText? {
        guard let count = overrideCounts[destination], count > 0 else { return nil }
        return .format("%@ overriding the profile", [String(count)])
    }

    public func presentation(
        for destination: ClashMoreDestination
    ) -> ClashProductDestinationPresentation {
        switch destination {
        case .root:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle:
                    "Core, data, connection, and app settings"
            )
        case .geoResources:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: "GeoIP, GeoSite, ASN, and MMDB data"
            )
        case .storage:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: "Configurations, data, and caches"
            )
        case .onDemand:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: onDemandEnabled
                    ? count(
                        onDemandRuleCount,
                        singular: "%@ ordered network rule",
                        plural: "%@ ordered network rules"
                    )
                    : "Wi-Fi and cellular rules",
                badge: onDemandEnabled ? "On" : nil
            )
        case .tunnel:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: "Enforce Routes and Include All Networks",
                badge: tunnelIncludeAllNetworks ? "On" : nil
            )
        case .tunnelAndRoutes:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: overrideSubtitle(for: .tunnelAndRoutes) ?? "App-wide TUN stack and route coverage"
            )
        case .clientSettings:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle:
                    "Traffic, updates, delay tests, and node switching"
            )
        case .appearance:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: "Language, theme, tint, and dark appearance"
            )
        case .about:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle: "Version, open source, and release information"
            )
        case .developer:
            return ClashProductDestinationPresentation(
                title: .copy(destination.title),
                subtitle:
                    "Diagnostics and local data"
            )
        }
    }

    public static let empty = ClashMoreSnapshot()

     
    private func count(
        _ value: Int,
        singular: String,
        plural: String
    ) -> ClashDisplayText {
        .format(value == 1 ? singular : plural, ["\(value)"])
    }
}


 
 
 
 
 
 
public struct ClashMoreAttention: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let message: ClashDisplayText
    public let actions: [ClashMoreAttentionAction]
     
     
    public let emphasised: Bool

    public init(id: String, message: ClashDisplayText, actions: [ClashMoreAttentionAction], emphasised: Bool = false) {
        self.id = id
        self.message = message
        self.actions = actions
        self.emphasised = emphasised
    }
}

public struct ClashMoreAttentionAction: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let title: ClashDisplayText
    public let destructive: Bool

    public init(id: String, title: ClashDisplayText, destructive: Bool = false) {
        self.id = id
        self.title = title
        self.destructive = destructive
    }
}
