import Foundation

 
 
 
 
 
 
 
 
 
public enum ClashActivityTableKind: String, Sendable {
    case connections
    case requests
}

public struct ClashActivityTableRow: Identifiable, Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        case live
        case closed
    }

    public let id: String
    public let connection: ClashActivityConnectionSnapshot
    public let status: Status
     
    public let time: Date?

    public init(
        id: String,
        connection: ClashActivityConnectionSnapshot,
        status: Status,
        time: Date?
    ) {
        self.id = id
        self.connection = connection
        self.status = status
        self.time = time
    }

    public init(connection: ClashActivityConnectionSnapshot) {
        self.init(
            id: connection.id,
            connection: connection,
             
             
            status: .live,
            time: connection.start
        )
    }

    public init(request: ClashActivityRequestSnapshot) {
        self.init(
            id: request.id,
            connection: request.connection,
            status: request.isActive ? .live : .closed,
             
             
             
             
             
            time: request.firstSeen
        )
    }

     
     
     
     
     
    static func newestIndex(in rows: [ClashActivityTableRow]) -> Int? {
        rows.indices.max { (rows[$0].time ?? .distantPast) < (rows[$1].time ?? .distantPast) }
    }

     
     
     
    public var proxy: String {
        connection.chains.first ?? connection.route
    }

     
     
    public var proxyPath: String {
        connection.chains.isEmpty
            ? connection.route
            : connection.chains.joined(separator: " → ")
    }

     
     
    public var isRejected: Bool {
        proxy.uppercased().hasPrefix("REJECT")
    }

     
     
     
     
     
    public var trafficProtocol: ClashActivityTrafficProtocol {
        let port = Int(connection.destinationPort)
            ?? connection.destination.split(separator: ":").last.flatMap { Int($0) }
            ?? 0
        switch connection.network.lowercased() {
        case "tcp": return port == 443 ? .https : port == 80 ? .http : .tcp
        case "udp": return port == 443 ? .quic : .udp
        default: return .other(connection.network.uppercased())
        }
    }
}

extension ClashActivityTableRow {
     
     
     
    public var ruleKind: String { Self.configSpelling(connection.rule) }

    static func configSpelling(_ kernel: String) -> String {
        if let spelled = knownSpellings[kernel] { return spelled }
         
         
        if kernel.contains("-") || kernel.contains(",") || kernel == kernel.uppercased() {
            return String(kernel.split(separator: ",", maxSplits: 1).first ?? "").uppercased()
        }
        var out = ""
        for (index, character) in kernel.enumerated() {
            if index > 0, character.isUppercase, !(out.last?.isUppercase ?? true) { out.append("-") }
            out.append(character)
        }
        return out.uppercased()
    }

     
    private static let knownSpellings: [String: String] = [
        "GeoIP": "GEOIP", "GeoSite": "GEOSITE", "SrcGeoIP": "SRC-GEOIP",
        "IPCIDR": "IP-CIDR", "IPCIDR6": "IP-CIDR6", "SrcIPCIDR": "SRC-IP-CIDR",
        "IPASN": "IP-ASN", "SrcIPASN": "SRC-IP-ASN",
        "IPSuffix": "IP-SUFFIX", "SrcIPSuffix": "SRC-IP-SUFFIX",
        "Process": "PROCESS-NAME", "ProcessPath": "PROCESS-PATH",
        "RuleSet": "RULE-SET", "Match": "MATCH", "DSCP": "DSCP",
    ]
}

public enum ClashActivityTrafficProtocol: Equatable, Sendable {
    case https, http, tcp, quic, udp
    case other(String)

    public var label: String {
        switch self {
        case .https: "HTTPS"
        case .http: "HTTP"
        case .tcp: "TCP"
        case .quic: "QUIC"
        case .udp: "UDP"
        case .other(let name): name
        }
    }
}

public enum ClashActivityTableColumn: String, CaseIterable, Sendable {
    case status
    case time
    case host
    case process
    case rule
    case proxy
    case network
    case download
    case upload
    case source
    case destinationIP

     
     
     
     
     
     
    public enum Badge: Equatable, Sendable {
        case https, http, tcp, quic, udp, otherTransport
        case refused
         
         
        case ruleKind
    }

     
     
     
    public var isSecondaryText: Bool { false }

    public enum Alignment: Equatable, Sendable {
        case leading
        case trailing
        case center
    }

     
    public static func columns(for kind: ClashActivityTableKind) -> [Self] {
        switch kind {
        case .connections:
            [.status, .host, .process, .rule, .proxy, .network, .download, .upload, .time, .source, .destinationIP]
        case .requests:
            [.status, .time, .host, .process, .rule, .proxy, .network, .download, .upload, .source, .destinationIP]
        }
    }

     
     
     
    public var hiddenByDefault: Bool {
        self == .source || self == .destinationIP
    }

     
     
    public var title: String {
        switch self {
        case .status: ""
        case .time: "Time"
        case .host: "Host"
        case .process: "Process"
        case .rule: "Rule"
        case .proxy: "Proxy"
        case .network: "Protocol"
        case .download: "Download"
        case .upload: "Upload"
        case .source: "Source"
        case .destinationIP: "Destination IP"
        }
    }

    public var width: (ideal: Double, min: Double) {
        switch self {
        case .status: (12, 12)
        case .time: (70, 62)
        case .host: (220, 120)
        case .process: (120, 70)
        case .rule: (170, 70)
        case .proxy: (100, 60)
        case .network: (76, 70)
        case .download: (72, 56)
        case .upload: (72, 56)
        case .source: (140, 80)
        case .destinationIP: (120, 80)
        }
    }

     
     
     
     
    public var flexes: Bool {
        switch self {
        case .host, .process, .rule, .proxy, .source, .destinationIP: true
        default: false
        }
    }

    public var alignment: Alignment {
        switch self {
        case .download, .upload: .trailing
        case .status: .center
        default: .leading
        }
    }

     
     
    public var truncatesInMiddle: Bool {
        self == .host || self == .destinationIP || self == .source
    }

     
     
    public var sortsDescendingFirst: Bool {
        switch self {
        case .time, .download, .upload, .status: true
        default: false
        }
    }

    public func text(
        of row: ClashActivityTableRow,
        bytes: ByteCountFormatter,
        time: (Date) -> String
    ) -> String {
        let connection = row.connection
        switch self {
        case .status: return ""
        case .time: return row.time.map(time) ?? ""
        case .host: return connection.destination
        case .process: return connection.process
        case .rule: return connection.ruleDescription
        case .proxy: return row.proxy
        case .network: return row.trafficProtocol.label
         
        case .download: return connection.download == 0 ? "–" : bytes.string(fromByteCount: connection.download)
        case .upload: return connection.upload == 0 ? "–" : bytes.string(fromByteCount: connection.upload)
        case .source: return connection.source
        case .destinationIP: return connection.destinationIP
        }
    }

     
    public func badge(of row: ClashActivityTableRow) -> Badge? {
        switch self {
        case .network:
            switch row.trafficProtocol {
            case .https: return .https
            case .http: return .http
            case .tcp: return .tcp
            case .quic: return .quic
            case .udp: return .udp
            case .other(let name): return name.isEmpty ? nil : .otherTransport
            }
        case .proxy:
            return row.isRejected ? .refused : nil
        case .rule:
            return row.connection.rule.isEmpty ? nil : .ruleKind
        default:
            return nil
        }
    }

     
     
     
    public func differs(_ old: ClashActivityTableRow, _ new: ClashActivityTableRow) -> Bool {
        let a = old.connection
        let b = new.connection
        switch self {
        case .status: return old.status != new.status
        case .time: return old.time != new.time
        case .host: return a.destination != b.destination
        case .process: return a.process != b.process || a.processPath != b.processPath
        case .rule: return a.rule != b.rule || a.rulePayload != b.rulePayload
        case .proxy: return a.chains != b.chains || a.route != b.route
        case .network: return old.trafficProtocol != new.trafficProtocol
        case .download: return a.download != b.download
        case .upload: return a.upload != b.upload
        case .source: return a.source != b.source
        case .destinationIP: return a.destinationIP != b.destinationIP
        }
    }

     
     
     
    public func ascending(_ lhs: ClashActivityTableRow, _ rhs: ClashActivityTableRow) -> Bool? {
        func compare<T: Comparable>(_ a: T, _ b: T) -> Bool? {
            a == b ? nil : a < b
        }
        func text(_ a: String, _ b: String) -> Bool? {
            switch a.compare(b, options: [.caseInsensitive, .numeric]) {
            case .orderedSame: nil
            case .orderedAscending: true
            case .orderedDescending: false
            }
        }
        let a = lhs.connection
        let b = rhs.connection
        switch self {
        case .status:
            return compare(lhs.status == .live ? 1 : 0, rhs.status == .live ? 1 : 0)
        case .time:
            return compare(lhs.time ?? .distantPast, rhs.time ?? .distantPast)
        case .host: return text(a.destination, b.destination)
        case .process: return text(a.process, b.process)
        case .rule: return text(a.ruleDescription, b.ruleDescription)
        case .proxy: return text(lhs.proxy, rhs.proxy)
        case .network: return text(lhs.trafficProtocol.label, rhs.trafficProtocol.label)
        case .download: return compare(a.download, b.download)
        case .upload: return compare(a.upload, b.upload)
        case .source: return text(a.source, b.source)
        case .destinationIP: return text(a.destinationIP, b.destinationIP)
        }
    }
}

public enum ClashActivityTableSorting {
     
    public static func sorted(
        _ rows: [ClashActivityTableRow],
        by column: ClashActivityTableColumn,
        ascending: Bool
    ) -> [ClashActivityTableRow] {
        rows.sorted { lhs, rhs in
            if let order = column.ascending(lhs, rhs) {
                return order == ascending
            }
            return lhs.id < rhs.id
        }
    }
}

 
 
 
public enum ClashActivityTableChange: Equatable, Sendable {
    case none
    case cells([Int: Set<ClashActivityTableColumn>])
    case reload

    public static func between(
        _ old: [ClashActivityTableRow],
        _ new: [ClashActivityTableRow],
        columns: [ClashActivityTableColumn]
    ) -> Self {
        guard old.count == new.count else { return .reload }
        var changed: [Int: Set<ClashActivityTableColumn>] = [:]
        for index in new.indices {
            let a = old[index]
            let b = new[index]
            guard a.id == b.id else { return .reload }
            if a == b { continue }
            let columns = Set(columns.filter { $0.differs(a, b) })
            if !columns.isEmpty { changed[index] = columns }
        }
        return changed.isEmpty ? .none : .cells(changed)
    }
}

public extension ClashActivityProjection {
     
     
     
     
    static let tableRenderCap = 5_000
}
