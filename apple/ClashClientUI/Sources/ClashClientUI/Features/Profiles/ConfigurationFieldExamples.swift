import Foundation
import ClashClientKit

 
 
 
 
 
public enum ConfigurationFieldExamples {
     
     
    public static func example(for format: ConfigurationFieldFormat?) -> String? {
        switch format {
        case .cidr?: return "192.168.0.0/16"
        case .ip?: return "192.168.1.1"
        case .domain?: return "+.example.com"
        case .host?: return "example.com"
        case .url?: return "https://example.com/"
        case .dnsServer?: return "https://dns.alidns.com/dns-query"
        case .portRange?: return "1000-2000"
        case .ipPort?: return "192.168.1.1:53"
        case .duration?: return "30s"
        case .regex?: return "^.*\\.example\\.com$"
        case .uuid?: return "5f0a9c3e-8d5b-4c2e-9c1a-2b3c4d5e6f70"
        default: return nil
        }
    }

     
     
    public static func prompt(for format: ConfigurationFieldFormat?) -> ClashDisplayText {
        guard let example = example(for: format) else { return .copy("Add an Item") }
        return .format("For example %@", [example])
    }

     
     
    public static func prompt(for field: ConfigurationField?, format: ConfigurationFieldFormat? = nil,
                              copy: ConfigurationFieldCopy, locale: Locale) -> ClashDisplayText {
        if let example = copy.entry(for: field, locale: locale)?.example { return .format("For example %@", [example]) }
        return prompt(for: format ?? field?.format)
    }

     
     
     
    public static func listFooter(for field: ConfigurationField?, format: ConfigurationFieldFormat? = nil,
                                  copy: ConfigurationFieldCopy, locale: Locale) -> ClashDisplayText {
        if let summary = copy.entry(for: field, locale: locale)?.summary, !summary.isEmpty { return .verbatim(summary) }
        return listFooter(for: field, format: format)
    }

     
     
    public static func listFooter(for field: ConfigurationField?, format: ConfigurationFieldFormat? = nil) -> ClashDisplayText {
        switch knownSet(for: field) {
        case .geosite?: return .copy("Each item is a GEOSITE category.")
        case .geoip?: return .copy("Each item is a GEOIP code.")
        case nil: break
        }
        switch field?.format ?? format {
        case .cidr?: return .copy("Each item is an IP range.")
        case .ip?: return .copy("Each item is an IP address.")
        case .domain?: return .copy("Each item is a domain. Starting with +. also covers its subdomains.")
        case .host?: return .copy("Each item is a domain or an IP address.")
        case .url?: return .copy("Each item is a web address.")
        case .dnsServer?: return .copy("Each item is a DNS server.")
        case .portRange?: return .copy("Each item is a port or a range of ports.")
        case .regex?: return .copy("Each item is a regular expression.")
        default: return .copy("Add one item at a time.")
        }
    }

     
    public static func listOrderNote(for field: ConfigurationField?) -> ClashDisplayText? {
        field?.ordered == true ? .copy("Earlier items come first.") : nil
    }

     
     
    public static func knownSet(for field: ConfigurationField?) -> ConfigurationKnownValueSet? {
        switch field?.path {
        case "dns.fallback-filter.geosite"?: return .geosite
        case "dns.fallback-filter.geoip-code"?: return .geoip
        default: return nil
        }
    }
}

 
 
public enum ConfigurationKnownValueSet: String, Sendable, Equatable {
    case geosite, geoip
}

 
 
 
public struct ConfigurationPolicyKey: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Identifiable, Sendable {
        case domain, geosite, ruleSet
        public var id: String { rawValue }
        public var title: ClashDisplayText {
            switch self {
            case .domain: return .copy("Domain Name")
            case .geosite: return .copy("GEOSITE Category")
            case .ruleSet: return .copy("Rule Set")
            }
        }
    }

    public let kind: Kind
    public let value: String

    public init(kind: Kind, value: String) {
        self.kind = kind
        self.value = value
    }

    public static func compose(_ kind: Kind, _ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        switch kind {
        case .domain: return trimmed
        case .geosite: return "geosite:" + trimmed
        case .ruleSet: return "rule-set:" + trimmed
        }
    }

    public static func parse(_ key: String) -> ConfigurationPolicyKey {
        if key.hasPrefix("geosite:") { return .init(kind: .geosite, value: String(key.dropFirst("geosite:".count))) }
        if key.hasPrefix("rule-set:") { return .init(kind: .ruleSet, value: String(key.dropFirst("rule-set:".count))) }
        return .init(kind: .domain, value: key)
    }

     
    public static func isPolicyMap(_ basePath: [String]) -> Bool {
        basePath == ["dns", "nameserver-policy"] || basePath == ["dns", "proxy-server-nameserver-policy"]
    }
}
