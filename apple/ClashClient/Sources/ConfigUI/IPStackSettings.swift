import Foundation
import CoreFoundation

 
 
 
 
 
 
 
 
enum IPQueryMode: String, CaseIterable, Identifiable, Sendable {
    case followConfiguration = "config"
    case ipv4Only = "ipv4-only"
    case dualStack = "dual-stack"
    case preferIPv4 = "prefer-ipv4"
    case preferIPv6 = "prefer-ipv6"
    case ipv6Only = "ipv6-only"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .followConfiguration: return "Follow Configuration"
        case .ipv4Only: return "IPv4 Only"
        case .dualStack: return "IPv4 & IPv6"
        case .preferIPv4: return "Prefer IPv4"
        case .preferIPv6: return "Prefer IPv6"
        case .ipv6Only: return "IPv6 Only (Use with Caution)"
        }
    }
}

enum TUNIPv6Mode: String, CaseIterable, Identifiable, Sendable {
    case followConfiguration = "config"
    case disabled
    case automatic
    case enabled

    var id: String { rawValue }
    var title: String {
        switch self {
        case .followConfiguration: return "TUN IPv6: Follow Configuration"
        case .disabled: return "TUN IPv6: Off"
        case .automatic: return "TUN IPv6: Automatic"
        case .enabled: return "TUN IPv6: On"
        }
    }
}

struct IPStackSettings: Equatable, Sendable {
    static let defaultsKey = "vpn.ipStack.settings"
     
     
    var queryMode: IPQueryMode = .followConfiguration
    var tunIPv6Mode: TUNIPv6Mode = .followConfiguration

    var dictionary: [String: Any] {
        ["schemaVersion": 1, "queryMode": queryMode.rawValue,
         "tunIPv6Mode": tunIPv6Mode.rawValue]
    }

    init(queryMode: IPQueryMode = .followConfiguration, tunIPv6Mode: TUNIPv6Mode = .followConfiguration) {
        self.queryMode = queryMode
        self.tunIPv6Mode = tunIPv6Mode
    }

    init(dictionary: [String: Any]) throws {
        guard let version = dictionary["schemaVersion"] as? NSNumber,
              CFGetTypeID(version) != CFBooleanGetTypeID(),
              version == NSNumber(value: 1),
              let query = dictionary["queryMode"] as? String,
              let queryMode = IPQueryMode(rawValue: query),
              let tun = dictionary["tunIPv6Mode"] as? String,
              let tunIPv6Mode = TUNIPv6Mode(rawValue: tun)
        else { throw IPStackSettingsError.invalidSnapshot }
        self.init(queryMode: queryMode, tunIPv6Mode: tunIPv6Mode)
    }

    static func load(from defaults: UserDefaults) throws -> Self {
        guard let value = defaults.object(forKey: defaultsKey) else { return Self() }
        guard let dictionary = value as? [String: Any] else {
            throw IPStackSettingsError.invalidSnapshot
        }
        return try Self(dictionary: dictionary)
    }

    func applying(to providerConfiguration: [String: Any]?) throws -> [String: Any] {
        var result = providerConfiguration ?? [:]
#if !os(tvOS)
         
         
         
         
         
        result["ipStack"] = dictionary
        return result
#else
        var snapshot: [String: Any] = [:]
        if let installed = result["ipStack"] {
            guard let dictionary = installed as? [String: Any] else {
                throw IPStackSettingsError.invalidSnapshot
            }
            _ = try Self(dictionary: dictionary)
            snapshot = dictionary
        }
        snapshot.merge(dictionary) { _, new in new }
        result["ipStack"] = snapshot
        return result
#endif
    }

    func save(to defaults: UserDefaults) throws {
         
         
        _ = try Self.load(from: defaults)
        var payload = defaults.dictionary(forKey: Self.defaultsKey) ?? [:]
        payload.merge(dictionary) { _, new in new }
        defaults.set(payload, forKey: Self.defaultsKey)
    }
}

enum IPStackSettingsError: LocalizedError {
    case invalidSnapshot

    var errorDescription: String? {
        String(localized: "The saved IP Stack settings are invalid or require a newer app version. They have not been changed.")
    }
}
