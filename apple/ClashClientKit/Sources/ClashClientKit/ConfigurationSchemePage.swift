import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
public enum ConfigurationSchemePage {
     
    public static var builtin: OrderedJSON {
        .object([("dns", ConfigurationDNSSettings.automatic)])
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static func imported(from document: OrderedJSON, rules: OrderedJSON? = nil) throws -> OrderedJSON? {
        var page = ConfigurationSettingsDocument.project(document)
        guard case .object(let entries) = page, !entries.isEmpty else { return nil }
        if let dns = page.topLevelValue("dns") {
            guard case .object = dns else { throw ConfigurationCompositionError.invalidDocument("DNS") }
        }
        page = try parse(page.serialized())
        let defined = (rules ?? document).topLevelValue("rule-providers")
        for name in ConfigurationSettingsDependencies.names(settings: page, dns: nil).sorted()
            where defined?.topLevelValue(name) == nil {
            throw ConfigurationCompositionError.unresolvedDependency(source: "Scheme page", name: name)
        }
        return page
    }

     
    public static func parse(_ json: String) throws -> OrderedJSON {
        try ConfigurationSettingsDocument.parse(json)
    }

     
    public static func of(_ scheme: ConfigurationRuleScheme?) throws -> OrderedJSON? {
        if let json = scheme?.pageJSON { return try parse(json) }
        if let scheme, ConfigurationBuiltins.isNative(scheme.id) { return builtin }
        return nil
    }

     
     
    public struct Effective: Equatable, Sendable {
        public let settings: OrderedJSON
        public let dns: OrderedJSON
    }

     
     
     
     
     
    public static func effective(schemePage: OrderedJSON?, settingsJSON: String?, dnsMode: ConfigurationDNSMode?,
                                 customDNSJSON: String?, nodeNameservers: [String]?) throws -> Effective {
        var settings = (schemePage ?? .object([])).removingTopLevel("dns")
        if case .object(let entries) = try ConfigurationSettingsDocument.parse(settingsJSON ?? "{}") {
            for entry in entries { settings = settings.settingTopLevel(entry.key, to: entry.value) }
        }
        if dnsMode == .custom {
            return Effective(settings: settings, dns: try ConfigurationDNSSettings.custom(customDNSJSON))
        }
        var dns = schemePage?.topLevelValue("dns") ?? ConfigurationDNSSettings.automatic
        if let servers = nodeNameservers {
            guard !servers.isEmpty, servers.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw ConfigurationLibraryError.emptyNodeNameservers
            }
            guard case .object = dns else { throw ConfigurationCompositionError.invalidDocument("DNS") }
            dns = dns.settingTopLevel("proxy-server-nameserver", to: .array(servers.map(OrderedJSON.string)))
        }
        return Effective(settings: settings, dns: dns)
    }

    public static func effective(of recipe: ConfigurationRecipe, scheme: ConfigurationRuleScheme?) throws -> Effective {
        try effective(schemePage: of(scheme), settingsJSON: recipe.settingsJSON, dnsMode: recipe.dnsMode,
                      customDNSJSON: recipe.customDNSJSON, nodeNameservers: recipe.nodeNameservers)
    }

     
     
    public static func legacy(of recipe: ConfigurationRecipe) throws -> OrderedJSON {
        let own = try effective(schemePage: nil, settingsJSON: recipe.settingsJSON, dnsMode: recipe.dnsMode,
                                customDNSJSON: recipe.customDNSJSON, nodeNameservers: recipe.nodeNameservers)
        return own.settings.removingTopLevel("dns").settingTopLevel("dns", to: own.dns)
    }
}

 
 
 
public enum ConfigurationSchemePageOwnership: Equatable, Sendable {
     
    case own(schemeID: String, label: String, configurations: Int)
     
     
     
    case shared(schemeID: String, label: String)
     
    case original
}

extension ConfigurationRuleScheme {
     
     
     
    var ownsItsPage: Bool { kind == .custom && isRetainedSnapshot != true && collectionKey == nil }
}

public extension ConfigurationLibrarySnapshot {
    func schemePageOwnership(profileID: String) -> ConfigurationSchemePageOwnership {
        guard let recipe = recipes.first(where: { $0.id == profileID }), recipe.preservesOriginal != true else { return .original }
        guard let scheme = rules.first(where: { $0.id == recipe.ruleSchemeID })
                ?? ConfigurationBuiltins.schemes.first(where: { $0.id == recipe.ruleSchemeID }) else {
            return .shared(schemeID: recipe.ruleSchemeID, label: recipe.ruleSchemeID)
        }
        guard scheme.ownsItsPage else { return .shared(schemeID: scheme.id, label: scheme.displayLabel) }
        return .own(schemeID: scheme.id, label: scheme.displayLabel,
                    configurations: recipes.filter { $0.ruleSchemeID == scheme.id && $0.preservesOriginal != true }.count)
    }

     
     
     
     
     
    func hasSchemeTakingPage(fromSource id: String) -> Bool {
        rules.contains { $0.takesPage(fromSource: id) }
    }

     
     
     
     
     
     
    func followedLinkLabel(ofScheme id: String) -> String? {
        guard let scheme = rules.first(where: { $0.id == id }) else { return nil }
        let base = scheme.rulesFromSchemeID.flatMap { baseID in rules.first { $0.id == baseID } } ?? scheme
        guard base.kind == .imported, base.isRetainedSnapshot != true,
              let source = sources.first(where: { $0.id == base.sourceID }), source.isRetainedSnapshot != true,
              case .subscription = source.origin else { return nil }
        return base.displayLabel
    }
}

extension ConfigurationRuleScheme {
     
    func takesPage(fromSource id: String) -> Bool {
        sourceID == id && kind == .imported && isRetainedSnapshot != true
            && rulesFromSchemeID == nil && collectionKey == nil
            && (pageFollowsSource == true || pageJSON == nil)
    }
}
