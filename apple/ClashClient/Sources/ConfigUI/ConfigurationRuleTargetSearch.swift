import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
final class ConfigurationRuleTargetSearch: @unchecked Sendable {
    typealias Section = ConfigurationRuleTargetCandidates.Section
     
    typealias SourceProvider = @Sendable () async -> NodePageSource?

    static let recentLimit = 10

    static func recentsKey(configurationID: String) -> String { "rule-targets.recent." + configurationID }

    let configurationID: String?
    private let source: SourceProvider
    private let defaults: UserDefaults?
    private let locale: Locale

    init(configurationID: String?, defaults: UserDefaults?, locale: Locale = .current, source: @escaping SourceProvider) {
        self.configurationID = configurationID
        self.defaults = defaults
        self.locale = locale
        self.source = source
    }

     

     
    func recents() -> [String] {
        guard let configurationID else { return [] }
        return defaults?.stringArray(forKey: Self.recentsKey(configurationID: configurationID)) ?? []
    }

     
    func recordUse(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let configurationID, let defaults, !trimmed.isEmpty,
              !ConfigurationRuleTargetCandidates.builtinPolicies.contains(trimmed) else { return }
        var names = recents().filter { $0 != trimmed }
        names.insert(trimmed, at: 0)
        defaults.set(Array(names.prefix(Self.recentLimit)), forKey: Self.recentsKey(configurationID: configurationID))
    }

     

     
     
     
     
    func sections(query: String, current: [String]) async -> [Section] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var sections: [Section] = []
        if needle.isEmpty {
            let held = unique(current.filter(isNodeName))
            if !held.isEmpty {
                sections.append(Section(id: "current", kind: .source, sourceLabel: copy("Nodes in use"), names: held))
            }
            let recent = recents().filter { !held.contains($0) }
            if !recent.isEmpty {
                sections.append(Section(id: "recent", kind: .source, sourceLabel: copy("Recently Used"), names: recent))
            }
            return sections
        }
        guard let page = try? await source()?.search(needle, offset: 0, limit: NodePaging.page) else {
             
            let held = current.filter { isNodeName($0) && $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            return held.isEmpty ? [] : [Section(id: "current", kind: .source, sourceLabel: copy("Nodes in use"), names: unique(held))]
        }
        return Self.sections(of: page, thisConfiguration: copy("This Configuration"))
    }

     
     
     
     
     
     
    static func sections(of page: ProxySearchPage, thisConfiguration: String) -> [Section] {
        var order: [String] = []
        var names: [String: [String]] = [:]
        let hidden = ModuleRouteHiding.hiddenNames()
        for item in page.items where item.source == ProxySearchPage.Item.inlineSource && !hidden.contains(item.name) {
            if names[item.source] == nil { order.append(item.source) }
            names[item.source, default: []].append(item.name)
        }
        return order.map { source in
            let isInline = source == ProxySearchPage.Item.inlineSource
            return Section(id: "search:" + source, kind: .source,
                           sourceLabel: isInline ? thisConfiguration : source,
                           names: uniqued(names[source] ?? []))
        }
    }

     

     
     
     
    func exists(_ name: String) async -> Bool {
        await existing([name]).contains(name)
    }

     
     
    func existing(_ names: [String]) async -> Set<String> {
        let wanted = Set(names.filter(isNodeName))
        var found = Set(names.filter { !isNodeName($0) })
        guard !wanted.isEmpty else { return found }
        guard let source = await source() else { return found.union(wanted) }
        for name in wanted {
             
             
             
             
            guard let lookup = try? await source.lookup(name) else {
                found.insert(name)
                continue
            }
            if lookup.found { found.insert(name) }
        }
        return found
    }

     

    private func isNodeName(_ name: String) -> Bool {
        !name.isEmpty && !ConfigurationRuleTargetCandidates.builtinPolicies.contains(name)
    }

    private func copy(_ key: String) -> String { ClashCopy.string(key, locale: locale) }

    private func unique(_ names: [String]) -> [String] { Self.uniqued(names) }

    private static func uniqued(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.filter { seen.insert($0).inserted }
    }
}

 
 
 
 
 
final class RuleTargetNodeSource: @unchecked Sendable {
    private let lock = NSLock()
    private var offlineProfileID: String??
    private let holder = OfflineNodeCatalogRegistry.Holder(id: "rule-target-" + UUID().uuidString)

    func source(profileID: String?) async -> NodePageSource? {
         
         
        if profileID == nil || profileID == Self.runningProfileID(),
           let session = await MainActor.run(body: { () -> ClashCommandClient? in
               guard let session = AppGroupDirectFetch.session, session.isConnected else { return nil }
               return session
           }) {
            return session
        }
        if lock.withLock({ offlineProfileID }) == .some(profileID),
           let held = OfflineNodeCatalogRegistry.held(by: holder) {
            return held
        }
        let holder = self.holder
        guard let catalog = await Task.detached(priority: .userInitiated, operation: { () -> OfflineNodeCatalog? in
            guard let input = OfflineProxyCatalogLoader.input(preferredProfileID: profileID) else { return nil }
            return try? OfflineProxyCatalogLoader.sharedCatalog(input, holder: holder)
        }).value else { return nil }
        lock.withLock { offlineProfileID = .some(profileID) }
        return catalog
    }

    deinit {
        OfflineNodeCatalogRegistry.release(holder)
    }

     
    static func runningProfileID() -> String? {
        guard let container = ClashAppIdentifiers.appGroupContainer,
              let store = try? ConfigResourceStore(containerURL: container)
        else { return nil }
        return try? store.activeIdentity()?.profileID
    }
}
