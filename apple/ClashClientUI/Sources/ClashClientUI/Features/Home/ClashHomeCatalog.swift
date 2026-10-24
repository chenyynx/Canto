public enum ClashHomeSection:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case common

    public var id: Self { self }

    public var title: String {
        switch self {
        case .common: "General"
        }
    }
}

public enum ClashHomeCard:
    String,
    CaseIterable,
    Codable,
    Hashable,
    Identifiable,
    Sendable
{
    case routing
    case proxies
    case rules
    case traffic
    case externalIP
    case lanIP

    public var id: Self { self }

    public var title: String {
        switch self {
        case .routing: "Outbound Mode"
        case .proxies: "Proxies"
        case .rules: "Rules"
        case .traffic: "Traffic"
        case .externalIP: "External IP"
        case .lanIP: "LAN IP"
        }
    }

    public var symbol: ClashSymbol {
        switch self {
        case .routing: .arrowTriangleBranch
        case .proxies: .serverRack
        case .rules: .ruleDomain
        case .traffic: .waveformPathEcg
        case .externalIP: .globe
        case .lanIP: .point3ConnectedTrianglepathDotted
        }
    }
}

public enum ClashHomeCatalog {
    public static let defaultCards: [ClashHomeCard] = [
        .routing, .proxies, .rules, .traffic,
    ]
    public static let requiredCards: [ClashHomeCard] = [
        .routing, .proxies, .rules,
    ]
    public static let optionalCards: [ClashHomeCard] = [
        .traffic, .externalIP, .lanIP,
    ]

     
     
     
     
     
     
     
    public enum ClashHomeCardMode: String { case rule, global, direct }

    public static func visibleCards(_ cards: [ClashHomeCard], mode: ClashHomeCardMode) -> [ClashHomeCard] {
        switch mode {
        case .rule: return cards
        case .global: return cards.filter { $0 != .rules }
        case .direct: return cards.filter { $0 != .rules && $0 != .proxies }
        }
    }

    public static func normalized(_ cards: [ClashHomeCard]) -> [ClashHomeCard] {
        var seen = Set<ClashHomeCard>()
        var result = cards.filter { seen.insert($0).inserted }
        for card in requiredCards where seen.insert(card).inserted {
            result.append(card)
        }
        return result
    }
}

