import Foundation
import ClashClientKit

 
 
 
 
 
 

enum ProviderFieldCatalog {
    static let proxyBase = "proxy-providers.*"
    static let ruleBase = "rule-providers.*"

    static func base(_ kind: ProfileProviderKind) -> String { kind == .proxy ? proxyBase : ruleBase }

     
     
     
     
    static func definitionDrawnElsewhere(_ transport: ProfileProviderTransport) -> Set<String> {
        switch transport {
        case .http: return ["type", "path", "payload"]
        case .file: return ["type", "url", "header", "payload"]
        case .inline: return ["type", "url", "header", "path"]
        }
    }

     
     
     
     
    static func definitionUnsupported(_ kind: ProfileProviderKind) -> Set<String> {
        ["proxy"]
    }

     
     
    static func types(_ catalog: ProfilesViewModel.SyntaxCatalog?, base: String) -> [String] {
        if let field = catalog?.fieldCatalog?.field(atCatalogPath: base + ".type"), !(field.values ?? []).isEmpty {
            return field.offeredValues().map(\.value)
        }
        return catalog?.ruleProvider.types ?? []
    }

     
     
     
     
     
     
    static func layout(of entry: OrderedJSON?, base: String, in catalog: ConfigurationFieldCatalog,
                       drawnElsewhere: Set<String> = [], unsupported: Set<String> = []) -> ProxyNodeCatalogLayout {
        var rows: [ProxyNodeCatalogLayout.Row] = []
        var groups: [ProxyNodeCatalogLayout.Group] = []
        var known = drawnElsewhere
        let written = entries(of: entry)
        for field in ProxyNodeCatalog.children(of: base, in: catalog) {
            let key = ProxyNodeCatalog.key(of: field)
            guard !drawnElsewhere.contains(key), !unsupported.contains(key) else { continue }
            known.insert(key)
            let value = written[key]
            if field.kind == .object, value == nil || isObject(value) {
                let inner = entries(of: value)
                var innerRows: [ProxyNodeCatalogLayout.Row] = []
                var innerKnown: Set<String> = []
                for child in ProxyNodeCatalog.children(of: base + "." + key, in: catalog) {
                    let childKey = ProxyNodeCatalog.key(of: child)
                    guard !(key == "override" && ProxyEditorHiddenFields.isHidden(childKey)) else { continue }
                    innerKnown.insert(childKey)
                    innerRows.append(.init(key: childKey, path: [key, childKey], field: child, value: inner[childKey]))
                }
                for (childKey, childValue) in inner.sorted(by: { $0.key < $1.key }) where !innerKnown.contains(childKey) {
                    innerRows.append(.init(key: childKey, path: [key, childKey], field: nil, value: childValue))
                }
                groups.append(.init(id: "object:" + key, title: key, rows: innerRows, catalogPath: base + "." + key))
            } else {
                rows.append(.init(key: key, path: [key], field: field, value: value))
            }
        }
        var result: [ProxyNodeCatalogLayout.Group] = rows.isEmpty ? [] : [.init(id: "main", title: nil, rows: rows)]
        result += groups
        let extra = written.keys.filter { !known.contains($0) }.sorted()
        if !extra.isEmpty {
            result.append(.init(id: "other", title: nil,
                                rows: extra.map { .init(key: $0, path: [$0], field: nil, value: written[$0]) }))
        }
        return ProxyNodeCatalogLayout(groups: result)
    }

     
     
    static func itemKeys(of path: [String], base: String, in catalog: ConfigurationFieldCatalog) -> [String] {
        let prefix = ([base] + path).joined(separator: ".") + "[]."
        return catalog.fields.compactMap { field in
            guard field.path.hasPrefix(prefix) else { return nil }
            let rest = field.path.dropFirst(prefix.count)
            return rest.contains(".") || rest.contains("[") ? nil : String(rest)
        }
    }

    private static func entries(of value: OrderedJSON?) -> [String: OrderedJSON] {
        guard case .object(let items)? = value else { return [:] }
        return Dictionary(items.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
    }

    private static func isObject(_ value: OrderedJSON?) -> Bool {
        if case .object? = value { return true }
        return false
    }
}

 
enum ProxyProviderCatalog {
    static let base = ProviderFieldCatalog.proxyBase

     
    static func types(_ catalog: ProfilesViewModel.SyntaxCatalog?) -> [String] {
        ProviderFieldCatalog.types(catalog, base: base)
    }

    static func layout(of entry: OrderedJSON?, in catalog: ConfigurationFieldCatalog) -> ProxyNodeCatalogLayout {
        ProviderFieldCatalog.layout(of: entry, base: base, in: catalog)
    }
}
