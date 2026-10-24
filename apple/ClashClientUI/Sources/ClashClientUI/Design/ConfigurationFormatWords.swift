import Foundation
import ClashClientKit

 
 
 
 
 
extension ConfigurationFieldProblem {
     
    public var words: ClashDisplayText {
        switch self {
        case .notANumber: return .copy("Enter a number.")
        case .wholeNumber: return .copy("Enter a whole number.")
        case .belowMinimum(let bound): return .format("Enter at least %@.", [bound])
        case .aboveMaximum(let bound): return .format("Enter at most %@.", [bound])
        case .missingPort: return .copy("Add the port, like 127.0.0.1:9090.")
        case .portOutOfRange: return .copy("The port is a number from 1 to 65535.")
        case .unbracketedIPv6: return .copy("Put an IPv6 address in brackets, like [::1]:9090.")
        case .bracketedIPv6Host: return .copy("Put an IPv6 address in brackets, like [::1].")
        case .hostNotAnIP: return .copy("Use an IP address or any, like 0.0.0.0:53.")
        case .hostWithPort: return .copy("Enter the port in its own row.")
        case .address: return .copy("Enter only the address, without https:// or a path.")
        case .ipAddress: return .copy("Enter an IP address, like 192.168.1.1.")
        case .addressRange: return .copy("Enter an IP range, like 192.168.0.0/16.")
        case .domain: return .copy("Enter a domain, like example.com.")
        case .webAddress: return .copy("Enter a full address that starts with https://.")
        case .portList: return .copy("Enter ports like 443 or 1000-2000, separated by commas.")
        case .dnsServer: return .copy("Enter a DNS server, like 223.5.5.5 or https://dns.alidns.com/dns-query.")
        case .pattern: return .copy("This pattern’s brackets don’t close.")
        case .base64: return .copy("Use only letters, digits, + / - _ and = at the end.")
        case .standardBase64: return .copy("Use only letters, digits, + and /, padded with = at the end.")
        case .hexadecimal: return .copy("Use an even number of the digits 0–9 and a–f.")
        case .fingerprint: return .copy("A certificate fingerprint is 64 hexadecimal digits.")
        case .shortID: return .copy("A short ID is up to 16 hexadecimal digits, in pairs.")
        case .uuid: return .copy("Enter a UUID, or tap Generate.")
        case .duration: return .copy("Enter a duration, like 30s or 5m.")
        case .spaces: return .copy("Remove the spaces.")
        case .hostsValue: return .copy("Enter IP addresses, or one domain name on its own.")
        }
    }
}

 
 
 
public struct ConfigurationFormatPreset: Equatable, Hashable, Sendable, Identifiable {
    public let value: String?
    public let label: ClashDisplayText

    public init(value: String?, label: ClashDisplayText) {
        self.value = value
        self.label = label
    }

    public var id: String { value ?? "\u{1F}off" }
}

 
 
 
 
 
 
public enum ConfigurationFormatPresets {
     

     
     
     
     
    public static func common(path: String, unit: String?, copy: ConfigurationFieldCopy = .shared,
                              language: ConfigurationFieldCopy.Language = .app) -> [ConfigurationFormatPreset] {
        if let own = copied(path: path, copy: copy, language: language), !own.isEmpty {
             
             
            guard ["s", "ms", "min", "h"].contains(unit ?? "") else { return [] }
            return own
        }
        let values: [String]
        switch unit {
        case "s": values = ["30", "60", "300", "600", "1800", "3600"]
        case "ms": values = ["100", "300", "500", "1000", "3000", "5000"]
        case "min": values = ["1", "5", "10", "30", "60"]
        case "h": values = ["1", "6", "12", "24"]
        default: return []
        }
        return values.map { ConfigurationFormatPreset(value: $0, label: ConfigurationFormatWords.number($0, unit: unit)) }
    }

     

     
     
    static let listenPorts: [String: String] = [
        "external-controller": "9090",
        "external-controller-tls": "9443",
        "dns.listen": "1053",
        "tuic-server.listen": "10443",
    ]

     
     
    public static func isListenAddress(path: String) -> Bool {
        listenPorts[path] != nil || path.hasPrefix("tunnels") && path.hasSuffix(".address")
    }

     
     
     
    public static func addressChoices(path: String, copy: ConfigurationFieldCopy = .shared,
                                      language: ConfigurationFieldCopy.Language = .app) -> [ConfigurationFormatPreset]? {
        guard let port = listenPorts[path] else { return nil }
        if let own = copy.entry(forPath: path, language: language)?.presets, !own.isEmpty {
             
            return [ConfigurationFormatPreset(value: nil, label: .copy("Off"))] + own.map { preset in
                let port = ConfigurationFieldValidation.splitHostPort(preset.value)?.port
                return ConfigurationFormatPreset(value: preset.value,
                                                 label: .verbatim(port.map { preset.label + " · " + $0 } ?? preset.label))
            }
        }
        return [
            ConfigurationFormatPreset(value: nil, label: .copy("Off")),
            ConfigurationFormatPreset(value: ConfigurationHostPortEntry.thisDeviceHost + ":" + port,
                                      label: .format("This Device Only · %@", [port])),
            ConfigurationFormatPreset(value: ConfigurationHostPortEntry.allNetworksHost + ":" + port,
                                      label: .format("Devices on Your Network · %@", [port])),
        ]
    }

     

     
     
     
    public static func dnsServers(path: String, copy: ConfigurationFieldCopy = .shared,
                                  language: ConfigurationFieldCopy.Language = .app) -> [ConfigurationFormatPreset] {
        if let own = copied(path: path, copy: copy, language: language), !own.isEmpty { return own }
        let addresses: [ConfigurationFormatPreset] = [
            .init(value: "223.5.5.5", label: .copy("AliDNS")),
            .init(value: "119.29.29.29", label: .copy("DNSPod")),
            .init(value: "1.1.1.1", label: .copy("Cloudflare DNS")),
            .init(value: "8.8.8.8", label: .copy("Google DNS")),
        ]
        if path.hasSuffix("default-nameserver") { return addresses }
        return [
            .init(value: "https://dns.alidns.com/dns-query", label: .copy("AliDNS over HTTPS")),
            .init(value: "https://doh.pub/dns-query", label: .copy("DNSPod over HTTPS")),
            .init(value: "https://1.1.1.1/dns-query", label: .copy("Cloudflare over HTTPS")),
            .init(value: "https://dns.google/dns-query", label: .copy("Google over HTTPS")),
        ] + addresses + [.init(value: "system", label: .copy("System DNS"))]
    }

     

     
     
     
    static func copied(path: String, copy: ConfigurationFieldCopy,
                       language: ConfigurationFieldCopy.Language) -> [ConfigurationFormatPreset]? {
        guard let presets = copy.entry(forPath: path, language: language)?.presets else { return nil }
        return presets.map { ConfigurationFormatPreset(value: $0.value, label: .verbatim($0.label)) }
    }
}

 
public enum ConfigurationFormatWords {
     
     
     
    public static func summary(_ text: String, field: ConfigurationField?) -> ClashDisplayText? {
         
         
         
        if let field, ConfigurationFormatPresets.listenPorts[field.path] != nil,
           text.trimmingCharacters(in: .whitespaces).isEmpty {
            return .copy("Off")
        }
        guard let field, field.format == .ipPort, ConfigurationFormatPresets.isListenAddress(path: field.path),
              let (host, port) = ConfigurationFieldValidation.splitHostPort(text.trimmingCharacters(in: .whitespaces))
        else { return nil }
        switch host {
        case ConfigurationHostPortEntry.thisDeviceHost, "localhost", "::1":
            return .format("This Device · %@", [port])
        case ConfigurationHostPortEntry.allNetworksHost, "", "::":
            return .format("Local Network · %@", [port])
        default:
            return nil
        }
    }

     
     
    public static func number(_ token: String, unit: String?) -> ClashDisplayText {
        if ["s", "ms", "min", "h"].contains(unit ?? ""),
           let whole = ConfigurationDurationEntry.largestWhole(stored: token, fieldUnit: unit) {
            return time(whole.amount, whole.unit)
        }
        switch unit {
        case "s": return .format("%@ s", [token])
        case "ms": return .format("%@ ms", [token])
        case "min": return .format("%@ min", [token])
        case "h": return .format("%@ h", [token])
        default: return .verbatim(token)
        }
    }

    static func time(_ amount: String, _ unit: ConfigurationDurationEntry.Unit) -> ClashDisplayText {
        switch unit {
        case .milliseconds: return .format("%@ ms", [amount])
        case .seconds: return .format("%@ s", [amount])
        case .minutes: return .format("%@ min", [amount])
        case .hours: return .format("%@ h", [amount])
        }
    }

     
    public static func unitName(_ unit: ConfigurationDurationEntry.Unit) -> ClashDisplayText {
        switch unit {
        case .milliseconds: return .copy("Milliseconds")
        case .seconds: return .copy("Seconds")
        case .minutes: return .copy("Minutes")
        case .hours: return .copy("Hours")
        }
    }
}
