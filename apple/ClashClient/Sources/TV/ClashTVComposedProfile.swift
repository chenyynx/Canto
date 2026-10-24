import Foundation
import ClashClientKit

 
 
 
 
 
 
 
 
 
enum ClashTVComposedProfile {
    enum Failure: Error, Equatable, LocalizedError {
         
         
        case nodeListNeedsRules
         
         
        case noNodes(String)

        var errorDescription: String? {
            switch self {
            case .nodeListNeedsRules:
                String(localized: "This URL is a node list, not a configuration. Choose Default Rules or Lazy Rules for this profile.")
            case .noNodes(let reason):
                reason.isEmpty
                    ? String(localized: "No nodes were found at this URL.")
                    : String(localized: "No nodes were found at this URL.") + " " + reason
            }
        }
    }

    static func document(body: Data, rules: ClashTVProfileRules) throws -> String {
        guard let schemeID = rules.schemeID else {
            return try asWritten(body)
        }
        let nodesYAML: String
        do {
             
             
             
             
            nodesYAML = try ProxyImportBridge.derivedSubscription(from: body, nodesOnly: true).yaml
        } catch {
            throw Failure.noNodes(error.localizedDescription)
        }
        return try composed(nodes: try OrderedJSON.parse(try ConfigTransforms.yamlToJSON(nodesYAML)), schemeID: schemeID)
    }

     
    private static func composed(nodes source: OrderedJSON, schemeID: String) throws -> String {
        guard hasNodes(source), let scheme = try ConfigurationBuiltins.source(for: schemeID) else {
            throw Failure.noNodes("")
        }
        let composition = try ConfigurationComposer.compose(
            sources: [ConfigurationInput(id: "profile", document: source)],
            rules: ConfigurationInput(id: scheme.record.id, document: try OrderedJSON.parse(scheme.documentJSON))
        )
        return try ConfigTransforms.jsonToYAML(composition.document.serialized())
    }

     
     
     
     
     
     
    static func compose(at source: URL, rules: ClashTVProfileRules, into composed: URL) throws -> (URL, checked: Bool) {
        guard let schemeID = rules.schemeID else {
            try checkAsWritten(at: source)
            return (source, true)
        }
        let text: String
        if let document = try largeConfiguration(at: source) {
            text = try Self.composed(nodes: document, schemeID: schemeID)
            AppCore.returnFreeMemoryNow(after: text)
        } else {
            text = try document(body: try Data(contentsOf: source), rules: rules)
        }
        try Data(text.utf8).write(to: composed, options: .atomic)
        return (composed, false)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private static func largeConfiguration(at source: URL) throws -> OrderedJSON? {
        guard let bytes = (try? source.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              bytes >= ConfigTransforms.ruleSectionCutFromBytes else { return nil }
        func read(omitting keys: [String]) throws -> OrderedJSON? {
            let json = try ConfigTransforms.yamlToJSON(atPath: source, omitting: keys)
            AppCore.returnFreeMemoryNow(after: json)
            return try? OrderedJSON.parse(json)
        }
        let readsWhole = !isTooLargeToReadWhole(source)
        do {
            try ConfigTransforms.validateSource(atPath: source)
            guard let document = try read(omitting: ["rules", "proxy-groups"]), hasNodes(document) else {
                if readsWhole { return nil }
                throw Failure.noNodes("")
            }
            guard namesBeyondItsNodes(document) || hasNodeLists(document) else { return document }
            return try read(omitting: ["rules"])
        } catch let failure as Failure {
            throw failure
        } catch {
            if Task.isCancelled || error is CancellationError { throw CancellationError() }
            if readsWhole { return nil }
            throw Failure.noNodes(error.localizedDescription)
        }
    }

     
     
    nonisolated(unsafe) static var wholeReadBytes = 16 * 1024 * 1024

     
     
     
     
     
     
     
    static func isTooLargeToReadWhole(_ url: URL) -> Bool {
         
         
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber,
              case let bytes = size.intValue, bytes >= ConfigTransforms.ruleSectionCutFromBytes else { return false }
        if bytes > wholeReadBytes { return true }
        guard let data = try? Data(contentsOf: url, options: [.alwaysMapped]) else { return false }
        return data.withUnsafeBytes { raw in
            guard let rules = TopLevelYAMLSections.sectionRange("rules", inBytes: raw.bindMemory(to: UInt8.self)) else {
                return false
            }
            return rules.count >= ConfigTransforms.ruleSectionCutFromBytes
        }
    }

    private static func hasNodeLists(_ document: OrderedJSON) -> Bool {
        guard case .object(let fields) = document else { return false }
        return fields.contains { key, value in
            guard key == "proxy-providers", case .object(let providers) = value else { return false }
            return !providers.isEmpty
        }
    }

     
    private static let builtInOutbounds: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE", "GLOBAL"]

     
     
     
    private static func namesBeyondItsNodes(_ document: OrderedJSON) -> Bool {
        guard case .object(let fields) = document else { return false }
        func field(_ object: OrderedJSON, _ key: String) -> OrderedJSON? {
            guard case .object(let pairs) = object else { return nil }
            return pairs.first { $0.key == key }?.value
        }
        func text(_ value: OrderedJSON?) -> String? {
            if case .string(let string)? = value { return string }
            return nil
        }
        var nodes = Set<String>()
        var named: [String] = []
        for (key, value) in fields where key == "proxies" {
            guard case .array(let items) = value else { continue }
            for node in items {
                if let name = text(field(node, "name")) { nodes.insert(name) }
                if let dialer = text(field(node, "dialer-proxy")) { named.append(dialer) }
            }
        }
        for (key, value) in fields where key == "proxy-providers" {
            guard case .object(let providers) = value else { continue }
            for (_, provider) in providers {
                if let proxy = text(field(provider, "proxy")) { named.append(proxy) }
                if let override = field(provider, "override"), let dialer = text(field(override, "dialer-proxy")) {
                    named.append(dialer)
                }
            }
        }
        return named.contains { !nodes.contains($0) && !builtInOutbounds.contains($0) }
    }

     
     
     
     
    private static func checkAsWritten(at source: URL) throws {
        do {
            try ConfigTransforms.validateSource(atPath: source)
        } catch {
            if Task.isCancelled || error is CancellationError { throw error }
            if isTooLargeToReadWhole(source) { throw error }
            let body = (try? Data(contentsOf: source)) ?? Data()
            guard String(data: body, encoding: .utf8) != nil else {
                throw ClashTVSubscriptionFetcher.FetchError.notText
            }
            if let inspected = try? ProxyImportBridge.inspectSummary(body, context: .subscriptionBody), inspected.count > 0 {
                throw Failure.nodeListNeedsRules
            }
            throw error
        }
    }

     
     
     
     
    private static func asWritten(_ body: Data) throws -> String {
        guard let text = String(data: body, encoding: .utf8) else {
            throw ClashTVSubscriptionFetcher.FetchError.notText
        }
         
         
        if (try? ConfigTransforms.validateSource(text)) == nil,
           let inspected = try? ProxyImportBridge.inspectSummary(body, context: .subscriptionBody),
           inspected.count > 0 {
            throw Failure.nodeListNeedsRules
        }
        return text
    }

    private static func hasNodes(_ document: OrderedJSON) -> Bool {
        guard case .object(let fields) = document else { return false }
        for (key, value) in fields where key == "proxies" || key == "proxy-providers" {
            switch value {
            case .array(let items) where !items.isEmpty: return true
            case .object(let entries) where !entries.isEmpty: return true
            default: continue
            }
        }
        return false
    }
}
