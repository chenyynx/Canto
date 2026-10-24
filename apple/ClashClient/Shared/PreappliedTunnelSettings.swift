import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct PreappliedTunnelDescriptor: Equatable, Codable {
    var mtu: Int
    var dnsServerAddress: String
    var inet4Addresses: [String]
    var inet6Addresses: [String]
    var inet4IncludedRoutes: [String]
    var inet4ExcludedRoutes: [String]
    var inet6IncludedRoutes: [String]
    var inet6ExcludedRoutes: [String]
    var strictRoute: Bool
     
    var queryMode: String = ""
    var ipv6Mode: String = ""

    static func == (lhs: Self, rhs: Self) -> Bool {
         
         
         
        lhs.mtu == rhs.mtu
            && lhs.dnsServerAddress == rhs.dnsServerAddress
            && lhs.strictRoute == rhs.strictRoute
            && lhs.queryMode == rhs.queryMode
            && lhs.ipv6Mode == rhs.ipv6Mode
            && lhs.inet4Addresses.sorted() == rhs.inet4Addresses.sorted()
            && lhs.inet6Addresses.sorted() == rhs.inet6Addresses.sorted()
            && lhs.inet4IncludedRoutes.sorted() == rhs.inet4IncludedRoutes.sorted()
            && lhs.inet4ExcludedRoutes.sorted() == rhs.inet4ExcludedRoutes.sorted()
            && lhs.inet6IncludedRoutes.sorted() == rhs.inet6IncludedRoutes.sorted()
            && lhs.inet6ExcludedRoutes.sorted() == rhs.inet6ExcludedRoutes.sorted()
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct PreappliedTunnelStore {
    private let defaults: UserDefaults?
    private static let key = "clash.preapplied.tunnel"

    init(defaults: UserDefaults?) {
        self.defaults = defaults
    }

    private struct Record: Codable {
        var build: String
        var order: [String]
        var descriptors: [String: PreappliedTunnelDescriptor]
    }

     
     
    private static let remembered = 4

     
     
     
     
     
     
     
    private static func currentBuild() -> String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? ""
    }

    private func load() -> Record? {
        guard let payload = defaults?.data(forKey: Self.key),
              let record = try? JSONDecoder().decode(Record.self, from: payload),
              record.build == Self.currentBuild()
        else { return nil }
        return record
    }

    private func cacheKey(_ fingerprint: String, queryMode: String, ipv6Mode: String) -> String? {
        guard !fingerprint.isEmpty else { return nil }
        if queryMode.isEmpty && ipv6Mode.isEmpty { return fingerprint }
         
        guard ["config", "ipv4-only", "dual-stack", "prefer-ipv4", "prefer-ipv6", "ipv6-only"].contains(queryMode),
              ["config", "disabled", "automatic", "enabled"].contains(ipv6Mode)
        else { return nil }
        return "\(fingerprint)|\(queryMode)|\(ipv6Mode)"
    }

    func descriptor(forTunIntent fingerprint: String, queryMode: String = "", ipv6Mode: String = "") -> PreappliedTunnelDescriptor? {
        guard let key = cacheKey(fingerprint, queryMode: queryMode, ipv6Mode: ipv6Mode),
              let descriptor = load()?.descriptors[key],
              descriptor.queryMode == queryMode, descriptor.ipv6Mode == ipv6Mode
        else { return nil }
        return descriptor
    }

    func remember(_ descriptor: PreappliedTunnelDescriptor, forTunIntent fingerprint: String,
                  queryMode: String = "", ipv6Mode: String = "") {
        guard let key = cacheKey(fingerprint, queryMode: queryMode, ipv6Mode: ipv6Mode),
              descriptor.queryMode == queryMode, descriptor.ipv6Mode == ipv6Mode
        else { return }
        var record = load() ?? Record(build: Self.currentBuild(), order: [], descriptors: [:])
        record.descriptors[key] = descriptor
        record.order.removeAll { $0 == key }
        record.order.append(key)
        while record.order.count > Self.remembered {
            record.descriptors.removeValue(forKey: record.order.removeFirst())
        }
        if let payload = try? JSONEncoder().encode(record) {
            defaults?.set(payload, forKey: Self.key)
        }
    }

}

 
 
 
 
 
 
 
enum PublishedTunIntent {
    private static let key = "clash.preapplied.tunIntent"

    static func publish(intentJSON: String, defaults: UserDefaults?) {
        guard let data = intentJSON.data(using: .utf8),
              let fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fingerprint = fields["tunRestartFingerprint"] as? String,
              !fingerprint.isEmpty
        else { return }
        defaults?.set(fingerprint, forKey: key)
    }

    static func current(defaults: UserDefaults?) -> String {
        defaults?.string(forKey: key) ?? ""
    }
}
