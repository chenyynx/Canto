import Foundation

public struct ConfigurationLocalRuleSet: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public var name: String
    public var input: String
    public var rules: [String]
    public init(id: String = UUID().uuidString.lowercased(), name: String, input: String, rules: [String]) {
        self.id = id; self.name = name; self.input = input; self.rules = rules
    }
}

public extension ConfigurationLibrarySnapshot {
     
     
     
     
    func keepsRulesInOriginal(_ scheme: ConfigurationRuleScheme) -> Bool {
        let base = scheme.rulesFromSchemeID.flatMap { id in rules.first { $0.id == id } } ?? scheme
        guard base.collectionKey == nil else { return false }
        return sources.first { $0.id == base.sourceID }?.rulesWrittenInOriginal == true
    }

    var visibleRuleSchemes: [ConfigurationRuleScheme] {
         
         
         
         
         
         
        let keepsAny = sources.contains { $0.rulesWrittenInOriginal == true }
        let available = keepsAny ? availableRules.filter { !keepsRulesInOriginal($0) } : availableRules
        let baseIDs = Set(available.filter { $0.baseSchemeID == nil }.map(\.id))
         
         
         
         
        let bases = ConfigurationBuiltins.schemes + available.filter {
            guard let base = $0.baseSchemeID else { return true }
            return ConfigurationBuiltins.isNative(base) || !baseIDs.contains(base)
        }
        var seen = Set<String>()
        return bases.filter { seen.insert($0.id).inserted }.map { base in
            ConfigurationBuiltins.isNative(base.id) ? base : (familyRepresentative(of: base.id, in: available) ?? base)
        }
    }

     
     
     
     
     
     
    func familyRepresentative(of baseID: String) -> ConfigurationRuleScheme? {
        familyRepresentative(of: baseID, in: availableRules)
    }

    private func familyRepresentative(of baseID: String, in available: [ConfigurationRuleScheme]) -> ConfigurationRuleScheme? {
        let derivatives = available.filter { $0.baseSchemeID == baseID }
        return derivatives.first { derivative in recipes.contains { $0.ruleSchemeID == derivative.id } } ?? derivatives.last
    }
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func effectiveRuleScheme(_ id: String) -> ConfigurationRuleScheme? {
        let available = availableRules
        if ConfigurationBuiltins.isNative(id) {
            let representative = familyRepresentative(of: id, in: available)
            if let representative, recipes.contains(where: { $0.ruleSchemeID == representative.id }) { return representative }
            return ConfigurationBuiltins.schemes.first { $0.id == id }
        }
        if let own = rules.first(where: { $0.id == id }), own.isRetainedSnapshot != true,
           own.collectionKey == nil, own.kind == .custom || own.kind == .imported {
            return own
        }
        return familyRepresentative(of: id, in: available) ?? rules.first { $0.id == id } ?? ConfigurationBuiltins.schemes.first { $0.id == id }
    }

     
     
     
    func ruleSchemeAfterSavingCustomization(_ id: String) -> ConfigurationRuleScheme? {
        if let own = rules.first(where: { $0.id == id }), own.isRetainedSnapshot != true,
           own.collectionKey == nil, own.kind == .custom || own.kind == .imported {
            return own
        }
        return familyRepresentative(of: id) ?? effectiveRuleScheme(id)
    }
}
