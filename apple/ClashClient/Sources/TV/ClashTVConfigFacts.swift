import Foundation
import Clash

 
 
 
 
 
 
 
 
 
struct ClashTVConfigFacts: Equatable {
    let rules: [ClashRuleLineSnapshot]
     
     
     
    var ruleCount: Int { rules.count }
     
     
     
    let namesRuleIndex: Bool
    let dnsEnhancedMode: String
    let dnsNameservers: [String]
    let dnsFallback: [String]
    let dnsDefaultNameservers: [String]
     
    let proxyGroupNames: [String]
     
     
     
    let proxyGroups: [ClashProxyGroupSnapshot]
     
    let nodeCount: Int
     
    let easyTierNodeNames: Set<String>
     
    let mode: String

    enum ReadingError: LocalizedError {
        case notAnObject
        var errorDescription: String? { "The configuration did not read as a document." }
    }

    init(yaml: String) throws {
        var error: NSError?
        guard let box = ClashYamlToJSON(yaml, &error) else {
            throw error ?? ReadingError.notAnObject
        }
        guard let root = try JSONSerialization.jsonObject(with: Data(box.value.utf8)) as? [String: Any] else {
            throw ReadingError.notAnObject
        }
        try self.init(root: root)
    }

    init(root: [String: Any]) throws {
        let rawRules = root["rules"] as? [Any] ?? []
        rules = rawRules.compactMap { Self.ruleLine(from: "\($0)") }
        namesRuleIndex = root[ConfigTransforms.ruleIndexKey] != nil
        let dns = root["dns"] as? [String: Any] ?? [:]
        dnsEnhancedMode = dns["enhanced-mode"] as? String ?? ""
        dnsNameservers = Self.strings(dns["nameserver"])
        dnsFallback = Self.strings(dns["fallback"])
        dnsDefaultNameservers = Self.strings(dns["default-nameserver"])
        let declaredGroups = root["proxy-groups"] as? [[String: Any]] ?? []
         
         
         
         
         
        let rawGroups = declaredGroups.filter { $0["hidden"] as? Bool != true }
         
         
         
         
         
        proxyGroupNames = rawGroups.compactMap { $0["name"] as? String }.filter { $0 != "GLOBAL" }
        let rawProxies = root["proxies"] as? [[String: Any]] ?? []
        nodeCount = rawProxies.count
        easyTierNodeNames = Set(rawProxies.compactMap { proxy in
            guard let kind = proxy["type"] as? String,
                  kind.trimmingCharacters(in: .whitespaces).lowercased() == "easytier",
                  let name = proxy["name"] as? String
            else { return nil }
            return name
        })
        var typeByName: [String: String] = [:]
        for proxy in rawProxies {
            if let name = proxy["name"] as? String { typeByName[name] = proxy["type"] as? String ?? "" }
        }
        let groupNames = Set(declaredGroups.compactMap { $0["name"] as? String })
        for group in declaredGroups {
            if let name = group["name"] as? String { typeByName[name] = group["type"] as? String ?? "" }
        }
        let visible = rawGroups.compactMap { group -> ClashProxyGroupSnapshot? in
            guard let name = group["name"] as? String else { return nil }
            let members = Self.strings(group["proxies"]).map { member in
                ClashProxyMemberSnapshot(name: member, type: typeByName[member] ?? "", isGroup: groupNames.contains(member))
            }
            return ClashProxyGroupSnapshot(name: name, type: group["type"] as? String ?? "", members: members)
        }
         
         
         
        let authored = visible.filter { $0.name != "GLOBAL" }
        let global = visible.first { $0.name == "GLOBAL" }.map { [$0] } ?? Self.synthesizedGlobal(
            declaredGroupNames: declaredGroups.compactMap { $0["name"] as? String },
            proxies: rawProxies,
            typeByName: typeByName
        )
        proxyGroups = authored + global
        mode = (root["mode"] as? String)?.lowercased() ?? "rule"
    }

    private static func strings(_ value: Any?) -> [String] {
        (value as? [Any] ?? []).map { "\($0)" }
    }

     
     
     
     
     
     
     
     
     
     
    private static func synthesizedGlobal(
        declaredGroupNames: [String],
        proxies: [[String: Any]],
        typeByName: [String: String]
    ) -> [ClashProxyGroupSnapshot] {
        guard !declaredGroupNames.contains("GLOBAL") else { return [] }
        let builtIn = ["DIRECT", "REJECT"].map {
            ClashProxyMemberSnapshot(name: $0, type: $0.capitalized, isGroup: false)
        }
        let nodes = proxies.compactMap { proxy -> ClashProxyMemberSnapshot? in
            guard let name = proxy["name"] as? String else { return nil }
            return ClashProxyMemberSnapshot(name: name, type: proxy["type"] as? String ?? "", isGroup: false)
        }
        let groups = declaredGroupNames.map {
            ClashProxyMemberSnapshot(name: $0, type: typeByName[$0] ?? "", isGroup: true)
        }
        return [ClashProxyGroupSnapshot(name: "GLOBAL", type: "Selector", members: builtIn + nodes + groups)]
    }

     
     
     
     
     
    static func ruleLine(from raw: String) -> ClashRuleLineSnapshot? {
        let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return nil }
        if let structured = ClashStructuredRule.parse(line) {
            return ClashRuleLineSnapshot(
                raw: line,
                type: structured.action.rawValue,
                payload: structured.content,
                target: structured.target
            )
        }
        let fields = line.split(separator: ",", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard let type = fields.first, !type.isEmpty else { return nil }
        if fields.count == 1 {
            return ClashRuleLineSnapshot(raw: line, type: type, payload: "", target: "")
        }
        if fields.count == 2 {
            return ClashRuleLineSnapshot(raw: line, type: type, payload: "", target: fields[1])
        }
        let flags: Set<String> = ["no-resolve", "src"]
        var trailing = Array(fields.dropFirst())
        while trailing.count > 2, let last = trailing.last, flags.contains(last.lowercased()) {
            trailing.removeLast()
        }
        let target = trailing.last ?? ""
        let payload = trailing.dropLast().joined(separator: ",")
        return ClashRuleLineSnapshot(raw: line, type: type, payload: payload, target: target)
    }
}

 
 
 
 
 
 
struct ClashTVRuleFacts: Codable, Equatable {
    static let fileName = "tv-rules.json"
     
     
    let count: Int

     
     
    static func of(publishedYAML: String) throws -> Self? {
        guard publishedYAML.contains("x-clash-rule-index") else { return nil }
         
         
        func project(_ error: NSErrorPointer) -> ClashStringBox? {
            AppCore.guarded(error, cancelled: nil, site: "configProjectionJSON(ruleFacts:)") {
                ClashConfigProjectionJSON(publishedYAML, "merged", #"["ruleFacts"]"#, error)
            }
        }
        var error: NSError?
        guard let box = project(&error) else {
            throw error ?? ClashTVConfigFacts.ReadingError.notAnObject
        }
        struct Projection: Decodable {
            struct RuleFacts: Decodable { let ruleCount: Int }
            let ruleFacts: RuleFacts
        }
        return Self(count: try JSONDecoder().decode(Projection.self, from: Data(box.value.utf8)).ruleFacts.ruleCount)
    }

    func write(to directory: URL) throws {
        try JSONEncoder().encode(self).write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

     
    static func publishedPath(providersDirectory directory: URL) -> String {
        directory.deletingLastPathComponent().appendingPathComponent("config.resolved.yaml").path
    }

    static func read(from directory: URL) -> Self? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }
}

 
 
 
 
 
struct ClashTVIndexedRules: Equatable {
     
     
     
    var total: Int
     
    var byType: [String: Int]
     
    var loaded: [ClashStructuredRule.Category: [ClashRuleLineSnapshot]] = [:]

     
    func types(in category: ClashStructuredRule.Category) -> [String] {
        byType.keys.filter { ClashTVRulesScreen.category(of: $0) == category }.sorted()
    }

    func count(in category: ClashStructuredRule.Category) -> Int {
        byType.reduce(0) { $0 + (ClashTVRulesScreen.category(of: $1.key) == category ? $1.value : 0) }
    }

    func neverMatching(in category: ClashStructuredRule.Category) -> Int {
        byType.reduce(0) {
            $0 + (ClashTVRulesScreen.category(of: $1.key) == category && ClashTVRulesScreen.neverMatches($1.key) ? $1.value : 0)
        }
    }

     
    func hasMore(in category: ClashStructuredRule.Category) -> Bool {
        (loaded[category]?.count ?? 0) < count(in: category)
    }
}

 
 
 
 
actor ClashTVPublishedRuleReader {
    private var catalog: ClashPublishedRuleCatalog?
    private var path: String?

    struct Summary: Equatable {
        let total: Int
        let byType: [String: Int]
    }

    private func open(_ publishedPath: String) throws -> ClashPublishedRuleCatalog {
        if let catalog, path == publishedPath { return catalog }
        close()
        var error: NSError?
        guard let opened = AppCore.openPublishedRuleCatalog(publishedPath, &error) else {
            throw error ?? ClashTVConfigFacts.ReadingError.notAnObject
        }
        catalog = opened
        path = publishedPath
        return opened
    }

    func summary(publishedPath: String) throws -> Summary {
        let catalog = try open(publishedPath)
        struct SummaryAnswer: Decodable { let byType: [String: Int] }
        let answer = try JSONDecoder().decode(SummaryAnswer.self, from: Data(catalog.summaryJSON().utf8))
        return Summary(total: Int(catalog.total()), byType: answer.byType)
    }

     
    func page(publishedPath: String, types: [String], offset: Int, limit: Int) throws -> [ClashRuleLineSnapshot] {
        let catalog = try open(publishedPath)
        let typesJSON = String(decoding: try JSONSerialization.data(withJSONObject: types), as: UTF8.self)
        struct PageAnswer: Decodable {
            struct Rule: Decodable { let text: String }
            let rules: [Rule]?
            let error: String?
        }
        let answer = try JSONDecoder().decode(PageAnswer.self, from: Data(
            catalog.pageJSON(Int32(clamping: offset), limit: Int32(clamping: limit), query: "", target: "", typesJSON: typesJSON).utf8))
        if let error = answer.error { throw ClashTVPublishedRuleReaderError(message: error) }
        return (answer.rules ?? []).compactMap { ClashTVConfigFacts.ruleLine(from: $0.text) }
    }

    func close() {
        catalog?.close()
        catalog = nil
        path = nil
    }
}

struct ClashTVPublishedRuleReaderError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
