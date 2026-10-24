import Foundation

public extension ConfigurationSourcePayload {
     
     
     
     
     
     
    var suppliesOwnRouting: Bool {
         
         
        if record.rulesWrittenInOriginal == true { return true }
        guard let document = try? OrderedJSON.topLevel(documentJSON),
              case .array(let rules)? = try? document.value("rules") else { return false }
        return rules.contains { rule in
            guard case .string(let line) = rule else { return false }
            let type = line.split(separator: ",", maxSplits: 1).first
                .map { $0.trimmingCharacters(in: .whitespaces).uppercased() } ?? ""
            return !type.isEmpty && type != "MATCH"
        }
    }
}

public extension ConfigurationCreationDraft {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    mutating func acceptNewImport(_ payload: ConfigurationSourcePayload,
                                  suppliesOwnRouting: Bool? = nil) throws {
        guard payload.record.suppliesNodes,
              payload.record.nodeCount > 0 || payload.record.providerCount > 0 else {
            throw ConfigurationLibraryError.missingNodes
        }
        let isEmpty = selectedSourceIDs.isEmpty && newSources.isEmpty
        let isFile: Bool = { if case .file = payload.record.origin { return true }; return false }()
        if isEmpty, isFile, suppliesOwnRouting ?? payload.suppliesOwnRouting { useOriginal(payload) }
        else { try acceptInitialNodeImport(payload) }
    }

     
     
    mutating func useOriginal(_ payload: ConfigurationSourcePayload) {
        self = .init()
        var source = payload
        source.record.registersSuppliedRules = true
        newSources = [source]
        originalSourceID = source.record.id
        selectedSourceIDs = [source.record.id]
        label = source.record.label
        dnsMode = .source
        step = .finish
    }
}

extension ConfigurationLibraryStore {
    func prepareOriginal(_ draft: ConfigurationCreationDraft, profileID: String,
                         starting: ConfigurationLibrarySnapshot,
                         resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput) throws -> PreparedConfigurationCreation {
        guard let sourceID = draft.originalSourceID, draft.selectedSourceIDs == [sourceID],
              !starting.recipes.contains(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        var source: ConfigurationSourcePayload
        if let staged = draft.newSources.first(where: { $0.record.id == sourceID }) { source = staged }
        else if let stored = starting.sources.first(where: { $0.id == sourceID }) { source = try payload(.init(stored)) }
        else { throw ConfigurationLibraryError.missingDependency(sourceID) }
        let input = try resolveInput(source)
        guard input.id == sourceID, case .object = input.document else {
            throw ConfigurationCompositionError.invalidDocument(sourceID)
        }
        source.record.registersSuppliedRules = true
        var candidate = starting
        if let index = candidate.sources.firstIndex(where: { $0.id == sourceID }) {
             
             
             
             
             
             
             
            candidate.sources[index].registersSuppliedRules = true
            source.record = candidate.sources[index]
        } else {
            candidate.sources.append(source.record)
        }
        let reference = ConfigurationSourceVersion(source.record)
        let ruleID = "rules-" + sourceID
         
         
        if input.document.topLevelValue("rules") != nil || input.document.topLevelValue("rule-providers") != nil
            || input.rulesWrittenInOriginal {
            candidate.rules.removeAll { $0.id == ruleID }
            var scheme = ConfigurationRuleScheme(id: ruleID, label: source.record.label, kind: .supplied, sourceID: sourceID)
             
            scheme.privateToConfigurationID = source.record.privateToConfigurationID
            candidate.rules.append(scheme)
        }
        let proposed = draft.label.trimmingCharacters(in: .whitespacesAndNewlines)
        var recipe = ConfigurationRecipe(id: profileID, label: proposed.isEmpty ? source.record.label : proposed,
            sources: [reference], ruleSchemeID: ruleID, ruleSource: reference, dnsMode: .source)
        recipe.preservesOriginal = true
        candidate.recipes.append(recipe)
        return .init(recipe: recipe, composition: .init(document: input.document, sourceIDs: [sourceID]),
            candidate: candidate, payloads: [source])
    }
}

public extension ConfigurationLibraryStore {
     
     
     
     
     
     
     
     
     
    func registerSuppliedRules(sourceID: String, expectedGeneration: UInt64) throws -> ConfigurationLibrarySnapshot {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard let index = candidate.sources.firstIndex(where: { $0.id == sourceID }) else {
            throw ConfigurationLibraryError.missingDependency(sourceID)
        }
        guard candidate.sources[index].hasRules else { throw ConfigurationLibraryError.missingRules }
         
         
         
        guard candidate.sources[index].rulesWrittenInOriginal != true else {
            throw ConfigurationCompositionError.rulesCannotLeaveTheOriginal(source: sourceID)
        }
        candidate.sources[index].registersSuppliedRules = true
        let ruleID = "rules-" + sourceID
        if !candidate.rules.contains(where: { $0.id == ruleID }) {
            candidate.rules.append(.init(id: ruleID, label: candidate.sources[index].label, kind: .supplied, sourceID: sourceID))
        }
        return try commit(candidate, payloads: [], expectedGeneration: expectedGeneration)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func prepareComposedSourceSettingsEditing(_ profileID: String, running: OrderedJSON, edited: OrderedJSON,
        expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationSourceUpdate? {
        let current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard let recipe = current.recipes.first(where: { $0.id == profileID }), recipe.preservesOriginal != true,
              ConfigurationSourceEditScope.changesOnlySettings(running: running, edited: edited) else { return nil }
         
         
        let page = try OrderedJSON.parse(advancedSettings(profileID, includingDNS: true, resolveInput: resolveInput).json)
        let settings = ConfigurationSourceEditScope.applyingSettingsChanges(from: running, to: edited, onto: page)
        let plan = try prepareAdvancedSettingsEditing(profileID, settingsJSON: settings.serialized(),
            expectedGeneration: expectedGeneration, includingDNS: true, resolveInput: resolveInput)
        guard let composed = plan.compositions[profileID]?.document,
              ConfigurationSourceEditScope.settings(of: composed) == ConfigurationSourceEditScope.settings(of: edited) else { return nil }
        return plan
    }

     
     
     
     
     
     
     
     
     
     
     
    static func markingLegacyEditedCopiesPrivate(in snapshot: ConfigurationLibrarySnapshot)
        -> (snapshot: ConfigurationLibrarySnapshot, payloads: [ConfigurationSourcePayload])? {
        guard snapshot.legacyEditedCopiesMarked != true else { return nil }
         
         
        guard snapshot.sources.contains(where: { $0.id.hasPrefix("edited-") && $0.privateToConfigurationID == nil }) else {
            return nil
        }
        var candidate = snapshot
        candidate.legacyEditedCopiesMarked = true
        let hoppedThrough = Set(snapshot.sources.flatMap { ($0.nodeChain?.hops ?? []).map(\.source.id) })
        for index in candidate.sources.indices {
            let source = candidate.sources[index]
            guard source.id.hasPrefix("edited-"), source.privateToConfigurationID == nil,
                  source.isRetainedSnapshot != true, !hoppedThrough.contains(source.id) else { continue }
            let consumers = snapshot.recipes.filter { $0.dependencies.contains { $0.id == source.id } }
            guard consumers.count == 1, let owner = consumers.first,
                  owner.preservesOriginal == true, owner.ruleSource.id == source.id else { continue }
            let schemes = snapshot.rules.indices.filter { snapshot.rules[$0].sourceID == source.id }
             
             
             
            let shared = schemes.contains { index in
                let id = snapshot.rules[index].id
                return snapshot.rules[index].isRetainedSnapshot == true
                    || snapshot.recipes.contains { ($0.ruleSchemeID == id || $0.composedRuleSchemeID == id) && $0.id != owner.id }
                    || snapshot.rules.contains { $0.rulesFromSchemeID == id }
                    || snapshot.selectedRuleSchemeID == id
            }
            guard !shared else { continue }
            candidate.sources[index].privateToConfigurationID = owner.id
            for scheme in schemes where candidate.rules[scheme].privateToConfigurationID == nil {
                candidate.rules[scheme].privateToConfigurationID = owner.id
            }
        }
        return (candidate, [])
    }

     
     
    func prepareWholeSourceEditing(_ profileID: String, replacement: ConfigurationSourcePayload,
        expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationCreation {
        var current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard current.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let previous = current.recipes.first(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
         
         
        guard !current.sources.contains(where: { $0.id == replacement.record.id }) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        current.recipes.removeAll { $0.id == profileID }
         
         
         
         
        var replacement = replacement
        replacement.record.privateToConfigurationID = profileID
        var draft = ConfigurationCreationDraft(); draft.useOriginal(replacement)
        draft.label = previous.label
        let prepared = try prepareOriginal(draft, profileID: profileID, starting: current, resolveInput: resolveInput)
        var recipe = prepared.recipe; recipe.followsUpdates = false
         
        recipe.ownCopyOf = previous.ownCopyOf ?? .recipe(previous)
        var candidate = prepared.candidate
        candidate.recipes.removeAll { $0.id == profileID }; candidate.recipes.append(recipe)
        return .init(recipe: recipe, composition: prepared.composition, candidate: candidate, payloads: prepared.payloads)
    }

     
     
     
     
     
    func prepareOwnSourceCopy(_ profileID: String, replacement: ConfigurationSourcePayload,
        expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationCreation {
        var candidate = try snapshot()
        guard candidate.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard candidate.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let index = candidate.recipes.firstIndex(where: { $0.id == profileID }),
              candidate.recipes[index].preservesOriginal == true else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        guard !candidate.sources.contains(where: { $0.id == replacement.record.id }) else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        var source = replacement
        source.record.registersSuppliedRules = true
         
        source.record.privateToConfigurationID = profileID
        let input = try resolveInput(source)
        guard input.id == source.record.id, case .object = input.document else {
            throw ConfigurationCompositionError.invalidDocument(source.record.id)
        }
        candidate.sources.append(source.record)
        let reference = ConfigurationSourceVersion(source.record)
        var recipe = candidate.recipes[index]
         
         
        recipe.ownCopyOf = recipe.ownCopyOf ?? .recipe(recipe)
        recipe.sources = [reference]
        recipe.ruleSource = reference
        recipe.ruleSchemeID = "rules-" + source.record.id
        recipe.followsUpdates = false
        if input.document.topLevelValue("rules") != nil || input.document.topLevelValue("rule-providers") != nil
            || input.rulesWrittenInOriginal {
            var scheme = ConfigurationRuleScheme(id: recipe.ruleSchemeID, label: source.record.label, kind: .supplied,
                                                 sourceID: source.record.id)
            scheme.privateToConfigurationID = profileID
            candidate.rules.append(scheme)
        }
        candidate.recipes[index] = recipe
        let composition = ConfigurationComposition(document: try overlayingAdvancedSettings(of: recipe, onto: input.document),
                                                   sourceIDs: [source.record.id])
        return .init(recipe: recipe, composition: composition, candidate: candidate, payloads: [source])
    }
}

public extension ConfigurationLibraryStore {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func prepareOriginalUse(_ profileID: String, uses: Bool, expectedGeneration: UInt64,
        resolveInput: (ConfigurationSourcePayload) throws -> ConfigurationInput = {
            .init(id: $0.record.id, document: try OrderedJSON.parse($0.documentJSON))
        }) throws -> PreparedConfigurationCreation {
        var current = try snapshot()
        guard current.generation == expectedGeneration else { throw ConfigurationLibraryError.staleGeneration }
        guard current.pendingPublications?.isEmpty ?? true else { throw ConfigurationLibraryError.busy }
        guard let existing = current.recipes.first(where: { $0.id == profileID }) else {
            throw ConfigurationLibraryError.missingDependency(profileID)
        }
        guard (existing.preservesOriginal == true) != uses else { throw ConfigurationLibraryError.invalidIdentifier.noted() }
        guard existing.sources.count == 1, let reference = existing.sources.first else {
            throw ConfigurationLibraryError.invalidIdentifier.noted()
        }
        guard !current.sources.contains(where: { $0.id == reference.id && $0.isRetainedSnapshot == true }) else {
            throw ConfigurationLibraryError.retainedSnapshot
        }
        guard uses else {
             
             
             
             
             
            var draft = ConfigurationCreationDraft()
            draft.step = .finish
            draft.selectedSourceIDs = [reference.id]
            let remembered = existing.composedRuleSchemeID.flatMap { id in
                current.rules.first { $0.id == id && $0.isRetainedSnapshot != true } ?? ConfigurationBuiltins.schemes.first { $0.id == id }
            }
            draft.selectedRuleID = remembered?.id ?? ConfigurationBuiltins.basicRuleID
            draft.label = existing.label
             
            draft.dnsMode = existing.dnsMode == .custom ? .custom : .system
            draft.customDNSJSON = existing.customDNSJSON
            draft.nodeNameservers = existing.nodeNameservers
            return try prepareEditing(draft, profileID: profileID, expectedGeneration: expectedGeneration,
                                      resolveInput: resolveInput)
        }
         
         
        current.recipes.removeAll { $0.id == profileID }
        var draft = ConfigurationCreationDraft()
        draft.useOriginal(try payload(reference))
        draft.label = existing.label
        let prepared = try prepareOriginal(draft, profileID: profileID, starting: current, resolveInput: resolveInput)
        var recipe = prepared.recipe
        recipe.followsUpdates = existing.followsUpdates
        recipe.composedRuleSchemeID = existing.ruleSchemeID
         
         
         
         
        recipe.settingsJSON = existing.settingsJSON
        recipe.originalSettingsJSON = nil
        recipe.settingsSource = existing.settingsSource
        recipe.settingsRuleDependencies = existing.settingsRuleDependencies
         
         
         
         
         
         
         
         
        recipe.dnsMode = existing.dnsMode
        recipe.customDNSJSON = existing.customDNSJSON
        recipe.nodeNameservers = existing.nodeNameservers
        var candidate = prepared.candidate
        candidate.recipes.removeAll { $0.id == profileID }; candidate.recipes.append(recipe)
        return .init(recipe: recipe, composition: prepared.composition, candidate: candidate, payloads: prepared.payloads)
    }
}


 
 
public enum ConfigurationSourceEditScope {
     
     
    public static let routingKeys: Set<String> = ConfigurationRuleDocument.keys.union(["proxies", "proxy-providers"])

     
     
    public static func changesOnlySettings(running: OrderedJSON, edited: OrderedJSON) -> Bool {
        guard case .object = running, case .object = edited else { return false }
        return routingKeys.allSatisfy { running.topLevelValue($0) == edited.topLevelValue($0) }
    }

     
     
    public static func settings(of document: OrderedJSON) -> [String: OrderedJSON] {
        guard case .object(let entries) = document else { return [:] }
        var result: [String: OrderedJSON] = [:]
        for entry in entries where !routingKeys.contains(entry.key) { result[entry.key] = entry.value }
        return result
    }

     
     
     
    public static func applyingSettingsChanges(from running: OrderedJSON, to edited: OrderedJSON,
                                               onto page: OrderedJSON) -> OrderedJSON {
        let before = settings(of: running), after = settings(of: edited)
        var result = page
        guard case .object(let entries) = edited else { return result }
        for entry in entries where !routingKeys.contains(entry.key) && before[entry.key] != entry.value {
            result = result.settingTopLevel(entry.key, to: entry.value)
        }
        for key in before.keys where after[key] == nil { result = result.removingTopLevel(key) }
        return result
    }
}
