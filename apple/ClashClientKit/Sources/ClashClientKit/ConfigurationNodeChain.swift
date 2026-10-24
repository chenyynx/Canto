import Foundation

 
 
public struct ConfigurationNodeChain: Codable, Equatable, Sendable {
    public struct Hop: Codable, Hashable, Sendable {
        public var source: ConfigurationSourceVersion
        public var nodeName: String
        public init(source: ConfigurationSourceVersion, nodeName: String) {
            self.source = source; self.nodeName = nodeName
        }
    }
    public var entry: Hop
    public var exit: Hop
    public var hops: [Hop] { [entry, exit] }
    public init(entry: Hop, exit: Hop) { self.entry = entry; self.exit = exit }
    public static func entryName(for id: String) -> String { "__clash_chain_entry_" + id }

    public func updating(_ record: ConfigurationSourceRecord) -> Self {
        var result = self
        if entry.source.id == record.id { result.entry.source = .init(record) }
        if exit.source.id == record.id { result.exit.source = .init(record) }
        return result
    }

    public static func materialize(record original: ConfigurationSourceRecord, chain: Self,
        load: (ConfigurationSourceVersion) throws -> ConfigurationSourcePayload) throws -> ConfigurationSourcePayload {
        let label = original.label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !label.isEmpty else { throw ConfigurationLibraryError.emptyName }
        guard chain.entry.source.id != chain.exit.source.id || chain.entry.nodeName != chain.exit.nodeName else {
            throw ConfigurationNodeChainError.sameNode
        }
        var files: [String: Data] = [:]
        func node(_ hop: Hop) throws -> OrderedJSON {
            guard hop.source.id != original.id else { throw ConfigurationNodeChainError.nestedChain }
            let source = try load(hop.source)
            guard source.record.nodeChain == nil else { throw ConfigurationNodeChainError.nestedChain }
            guard case .array(let nodes) = try OrderedJSON.parse(source.documentJSON).topLevelValue("proxies") else {
                throw ConfigurationNodeChainError.missingNode(hop.nodeName)
            }
            let matches = nodes.filter { $0.topLevelValue("name") == .string(hop.nodeName) }
            guard matches.count == 1, let node = matches.first else { throw ConfigurationNodeChainError.missingNode(hop.nodeName) }
            if case .string(let dialer) = node.topLevelValue("dialer-proxy"), !dialer.isEmpty, dialer != "DIRECT" {
                throw ConfigurationNodeChainError.alreadyChained(hop.nodeName)
            }
            for (name, data) in source.resourceFiles ?? [:] {
                if let previous = files[name], previous != data { throw ConfigurationNodeChainError.resourceConflict(name) }
                files[name] = data
            }
            return node.removingTopLevel("dialer-proxy")
        }
        let privateName = entryName(for: original.id)
        let entry = try node(chain.entry).settingTopLevel("name", to: .string(privateName))
        let exit = try node(chain.exit).settingTopLevel("name", to: .string(label))
            .settingTopLevel("dialer-proxy", to: .string(privateName))
        var record = original
        record.label = label; record.nodeChain = chain; record.nodeCount = 1
        record.providerCount = 0; record.groupCount = 0; record.ruleCount = 0
        record.suppliesNodes = true; record.registersSuppliedRules = false
        record.version = UUID().uuidString; record.updatedAt = Date()
        let document = OrderedJSON.object([("proxies", .array([entry, exit]))])
        return .init(record: record, original: try JSONEncoder().encode(chain), documentJSON: document.serialized(),
            resourceFiles: files.isEmpty ? nil : files)
    }
}

public enum ConfigurationNodeChainError: LocalizedError {
    case sameNode, nestedChain
    case missingNode(String), alreadyChained(String), resourceConflict(String), referencedBy(String)
    public var errorDescription: String? {
        switch self {
        case .sameNode: return "Choose different entry and exit nodes."
        case .nestedChain: return "Choose individual nodes, not another proxy chain."
        case .missingNode: return "A node in this chain is missing or ambiguous. Edit the chain before updating this source."
        case .alreadyChained: return "This node already uses a dialer proxy. Choose a node without an existing chain."
        case .resourceConflict: return "The nodes have different resource files with the same name."
        case .referencedBy: return "This source is used by a proxy chain. Edit or delete the chain first."
        }
    }
}
