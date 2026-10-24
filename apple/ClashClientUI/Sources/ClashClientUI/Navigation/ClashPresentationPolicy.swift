 
 
 
 
 
 
public enum ClashRootSidebarGroup: String, CaseIterable, Hashable, Sendable {
     
     
    case primary
    case session
    case configuration
     
     
     
     
    case hub
     
    case footer

     
     
     
     
     
     
     
    public var title: String? {
        switch self {
        case .primary, .hub, .footer: nil
        case .session: "Session"
         
         
         
        case .configuration: "sidebar.band.configuration"
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
public enum ClashRootDestination: String, CaseIterable, Hashable, Identifiable, Sendable {
    case home

     
     
     
     
     
     
     
     
     
     
     
    case proxies
    case rules
    case activity

    case profiles

     
     
     
     
     
     
     
    case utilities
    case more

    case about

    public var id: Self { self }

    public var group: ClashRootSidebarGroup {
        switch self {
        case .home: .primary
        case .proxies, .rules, .activity: .session
        case .profiles: .configuration
        case .utilities, .more: .hub
        case .about: .footer
        }
    }

    public static func rows(
        in group: ClashRootSidebarGroup
    ) -> [ClashRootDestination] {
        allCases.filter { $0.group == group }
    }

     
     
     
     
     
     
     
    public static let pendingShellHoist: Set<ClashRootDestination> = []

     
     
     

    public static var sidebarRows: [ClashRootDestination] {
        allCases.filter { !pendingShellHoist.contains($0) }
    }

    public static func sidebarRows(
        in group: ClashRootSidebarGroup
    ) -> [ClashRootDestination] {
        rows(in: group).filter { !pendingShellHoist.contains($0) }
    }

    public var title: String {
        switch self {
        case .home: "Home"
        case .proxies: "Proxies"
        case .rules: "Rules"
        case .activity: "Activity"
        case .profiles: "Profiles"
         
         
         
         
        case .utilities: "Utilities"
        case .more: "More"
        case .about: "About"
        }
    }

     
     
     
     
    public var pageTitle: String {
        switch self {
        case .profiles: "Profile Center"
        default: title
        }
    }

    public var symbol: ClashSymbol {
        switch self {
        case .home: .catCircleFill
        case .proxies: .serverRack
        case .rules: .ruleDomain
         
         
         
        case .activity: .waveformPathEcg
         
         
        case .profiles: .trayFullFill
         
         
        case .utilities: .briefcaseCircleFill
        case .more: .ellipsisCircleFill
        case .about: .infoCircle
        }
    }
}

public enum ClashPresentationClass: String, CaseIterable, Sendable {
    case compactTouch
    case regularTouch
    case desktop
    case television
}

public enum ClashRootNavigationStyle: String, Sendable {
    case bottomTabs
    case fixedSidebar
    case televisionFocus
}

public enum ClashContentWidthClass: String, Sendable {
    case compact
    case regular
    case television
}

public enum ClashSurfaceTreatment: String, Sendable {
    case nativeGlassWhenAvailable
    case focusNative
    case stableGrouped
}

 
 
 
public struct ClashPresentationPolicy: Equatable, Sendable {
    public let presentationClass: ClashPresentationClass
    public let rootNavigation: ClashRootNavigationStyle
    public let contentWidth: ClashContentWidthClass
    public let primaryPageTreatment: ClashSurfaceTreatment
    public let secondaryPageTreatment: ClashSurfaceTreatment
    public let allowsUserSidebarCollapse: Bool

    public static func `for`(_ presentationClass: ClashPresentationClass) -> Self {
        switch presentationClass {
        case .compactTouch:
            Self(
                presentationClass: presentationClass,
                rootNavigation: .bottomTabs,
                contentWidth: .compact,
                primaryPageTreatment: .nativeGlassWhenAvailable,
                secondaryPageTreatment: .stableGrouped,
                allowsUserSidebarCollapse: false
            )
        case .regularTouch, .desktop:
            Self(
                presentationClass: presentationClass,
                rootNavigation: .fixedSidebar,
                contentWidth: .regular,
                primaryPageTreatment: .nativeGlassWhenAvailable,
                secondaryPageTreatment: .stableGrouped,
                allowsUserSidebarCollapse: false
            )
        case .television:
            Self(
                presentationClass: presentationClass,
                rootNavigation: .televisionFocus,
                contentWidth: .television,
                primaryPageTreatment: .focusNative,
                secondaryPageTreatment: .stableGrouped,
                allowsUserSidebarCollapse: false
            )
        }
    }
}
