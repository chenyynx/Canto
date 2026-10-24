import Foundation
import ClashClientKit

 
 
 
 
public enum ConfigurationTypeWords {
    public enum Family: String, Sendable {
        case proxies = "proxies[*].type"
        case proxyGroups = "proxy-groups[*].type"
        case proxyProviders = "proxy-providers.*.type"
        case ruleProviders = "rule-providers.*.type"
         
        case ruleProviderFormats = "rule-providers.*.format"
        case ruleProviderBehaviors = "rule-providers.*.behavior"
        case listeners = "listeners[*].type"
    }

     
    public static func names(_ family: Family, copy: ConfigurationFieldCopy, locale: Locale) -> [String: String] {
        let presets = copy.entry(forPath: family.rawValue, language: ConfigurationFieldCopy.Language(locale: locale))?.presets ?? []
        return Dictionary(presets.map { ($0.value.lowercased(), $0.label) }, uniquingKeysWith: { first, _ in first })
    }

    public static func word(_ type: String?, in names: [String: String]) -> String {
        guard let type, !type.isEmpty else { return "" }
        return names[type.lowercased()] ?? type
    }

     
     
     
     
    public struct Collections: Sendable {
        public let nodes: [String: String]
        let nodeSets: [String: String]
        let ruleSets: [String: String]
        let behaviors: [String: String]
        let formats: [String: String]

        public init(copy: ConfigurationFieldCopy, locale: Locale) {
            nodes = ConfigurationTypeWords.names(.proxies, copy: copy, locale: locale)
            nodeSets = ConfigurationTypeWords.names(.proxyProviders, copy: copy, locale: locale)
            ruleSets = ConfigurationTypeWords.names(.ruleProviders, copy: copy, locale: locale)
            behaviors = ConfigurationTypeWords.names(.ruleProviderBehaviors, copy: copy, locale: locale)
            formats = ConfigurationTypeWords.names(.ruleProviderFormats, copy: copy, locale: locale)
        }

        public func type(of collection: ConfigurationCollection) -> String {
            ConfigurationTypeWords.word(collection.type, in: collection.id.kind == .rules ? ruleSets : nodeSets)
        }

        public func behavior(of collection: ConfigurationCollection) -> String? {
            collection.behavior.map { ConfigurationTypeWords.word($0, in: behaviors) }
        }

        public func format(of collection: ConfigurationCollection) -> String {
            ConfigurationTypeWords.word(collection.format, in: formats)
        }

         
         
        public func line(_ collection: ConfigurationCollection) -> String {
            guard collection.id.kind == .rules else { return type(of: collection) }
            return [type(of: collection), behavior(of: collection), format(of: collection)]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        }
    }
}
