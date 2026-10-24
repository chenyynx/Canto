public enum ClashMoreSectionID: String, CaseIterable, Hashable, Sendable {
    case dataAndResources
    case connectionBehavior
    case clientPreferences
    case about

    public var title: String {
        switch self {
        case .dataAndResources: "Data & Resources"
        case .connectionBehavior: "Connection Behavior"
        case .clientPreferences: "App Settings"
        case .about: "About"
        }
    }
}

public enum ClashMoreDestination:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case root
    case geoResources
    case storage
    case onDemand
    case tunnel
    case tunnelAndRoutes
    case clientSettings
    case appearance
    case about
    case developer

    public var id: Self { self }

    public var title: String {
        switch self {
        case .root: "More"
        case .geoResources: "Geo Resources"
        case .storage: "Storage"
        case .onDemand: "On Demand"
         
         
        case .tunnel: "VPN"
        case .tunnelAndRoutes: "Tunnel & Routes"
        case .clientSettings: "Client Settings"
        case .appearance: "Appearance"
        case .about: "About Clash"
        case .developer: "Developer"
        }
    }

    public var symbol: ClashSymbol {
        switch self {
        case .root: .ellipsisCircle
        case .geoResources: .globeAsiaAustralia
        case .storage: .externaldrive
        case .onDemand: .appBadgeCheckmarkFill
        case .tunnel: .arrowLeftAndRightSquareFill
        case .tunnelAndRoutes: .globeBadgeChevronBackward
        case .clientSettings: .gearshape
        case .appearance: .circleLefthalfFilled
        case .about: .infoCircle
        case .developer: .wrenchAndScrewdriver
        }
    }

    public var accent: ClashAccentRole {
        switch self {
        case .root: .blue
        case .geoResources: .green
        case .storage: .indigo
        case .onDemand: .cyan
        case .tunnel: .blue
        case .tunnelAndRoutes: .teal
        case .clientSettings: .purple
        case .appearance: .indigo
        case .about: .blue
        case .developer: .orange
        }
    }
}

public struct ClashMoreSectionDescriptor: Equatable, Sendable {
    public let id: ClashMoreSectionID
    public let destinations: [ClashMoreDestination]

    public init(
        id: ClashMoreSectionID,
        destinations: [ClashMoreDestination]
    ) {
        self.id = id
        self.destinations = destinations
    }
}

public enum ClashMoreCatalog {
     
     
     
     
    private static var connectionBehaviorDestinations: [ClashMoreDestination] {
         
         
         
        [.onDemand, .tunnel]
    }

     
     
     
     
     
     
     
     
     
     
    public static let regularHubExcludes: Set<ClashMoreDestination> = [
        .about,
    ]

     
     
     
     
     
     
     
     
     
     
     
     
    public static let sections = [
        ClashMoreSectionDescriptor(
            id: .connectionBehavior,
            destinations: connectionBehaviorDestinations
        ),
         
         
         
         
        ClashMoreSectionDescriptor(
            id: .clientPreferences,
            destinations: [.clientSettings, .appearance]
        ),
         
         
         
         
         
         
        ClashMoreSectionDescriptor(
            id: .dataAndResources,
             
             
            destinations: [.geoResources, .storage]
        ),
         
        ClashMoreSectionDescriptor(
            id: .about,
            destinations: [.about]
        ),
    ]
}
