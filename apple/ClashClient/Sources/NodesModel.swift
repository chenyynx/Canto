import Combine
import Foundation
import ClashClientKit
import ClashClientUI

struct ProxyGroup: Identifiable, Equatable {
    let name: String
    let type: String        
    let now: String         
    let resolvedNow: String  
    let members: [String]
    let memberTypes: [String: String]
    let memberGroupNames: Set<String>
    let memberResolvedNames: [String: String]
     
     
     
     
    let memberPlaceholderTypes: [String: String]
    let configurationDetails: ProxyGroupConfigurationDetails?
     
    let hidden: Bool
     
     
     
     
    let testURL: String?
     
     
     
     
     
    let iconURL: String?
     
     
    let emptyFallback: String?
     
     
     
     
     
     
    let fixed: String?
     
     
     
    let memberTotal: Int
     
     
     
    let hiddenMembers: Set<String>
    var id: String { name }
     
    var hasEveryMember: Bool { members.count + hiddenMembers.count >= memberTotal }
     
    var shownMemberTotal: Int { max(memberTotal - hiddenMembers.count, members.count) }
     
     
    var isEmpty: Bool { hasEveryMember && (emptyFallback.map { members == [$0] } ?? false) }
    var selectable: Bool { type.lowercased().contains("selector") || type.lowercased() == "select" }

     
     
     
     
     
     
     
     
    var acceptsMemberChoice: Bool {
        ProxyGroupControlKind(rawType: type).acceptsMemberChoice
    }

     
     
     
     
     
     
     
     
     
     
     
     
    func holdsSelection(_ member: String) -> Bool {
        if ProxyGroupControlKind(rawType: type).canBeUnpinned {
            return fixed == member
        }
        return now == member
    }

    init(name: String, type: String, now: String, members: [String],
         resolvedNow: String? = nil, memberTypes: [String: String] = [:],
         memberGroupNames: Set<String> = [],
         memberResolvedNames: [String: String] = [:],
         memberPlaceholderTypes: [String: String] = [:],
         configurationDetails: ProxyGroupConfigurationDetails? = nil,
         hidden: Bool = false,
         testURL: String? = nil,
         iconURL: String? = nil,
         emptyFallback: String? = nil,
         fixed: String? = nil,
         memberTotal: Int? = nil,
         hiddenMembers: Set<String> = []) {
        self.memberTotal = max(memberTotal ?? members.count + hiddenMembers.count, members.count + hiddenMembers.count)
        self.hiddenMembers = hiddenMembers
        self.hidden = hidden
        self.memberPlaceholderTypes = memberPlaceholderTypes
        self.testURL = testURL
        self.iconURL = iconURL
        self.emptyFallback = emptyFallback
        self.fixed = fixed
        self.name = name
        self.type = type
        self.now = now
        self.resolvedNow = resolvedNow ?? now
        self.members = members
        self.memberTypes = memberTypes
        self.memberGroupNames = memberGroupNames
        self.memberResolvedNames = memberResolvedNames
        self.configurationDetails = configurationDetails
    }
}

@MainActor
protocol NodesCommanding: AnyObject, Sendable {
    var isConnected: Bool { get }
     
     
     
    var isReopeningControlSession: Bool { get }
    var mode: String { get }
    var proxiesData: Data? { get }
    func refreshMetadata() async
     
     
     
    func nodesRefreshMetadata() async -> Bool
    func select(group: String, name: String) async -> Bool
    func unfix(group: String) async -> Bool
     
     
     
    var lastCommandError: String { get }
    func closeConnectionsAfterProxySelection() async
    func reconnectAfterRuntimeChange()
     
     
    func nodesTestDelay(name: String, url: String) async -> Int
     
     
     
     
    func nodesTestDelayWithReason(
        name: String,
        url: String
    ) async -> (delay: Int, category: String)
     
     
    func extensionFootprintBytes() async -> Int64
    func nodesProviderCatalog() async throws -> ProviderRuntimeCatalog
     
     
     
     
     
     
     
    func nodesHealthCheckProvider(named name: String) async -> [String: Int]
     
     
     
    func nodesProxyDelays() async -> Data?
     
     
    var extensionMemoryBytes: Int64 { get }
     
     
    var nodeListRevision: String? { get }
     
     
    var nodePages: NodePageSource? { get }
     
    func nodesProxyDelaysPage(since: Int64, after: String, limit: Int) async -> Data?
     
     
    func nodesProxyDelaysPageRead(since: Int64, after: String, limit: Int) async -> DelayPageRead
     
     
    func nodesProviderReadings(named name: String, since: Int64) async -> [String: Int]?
}

 
enum DelayPageRead {
    case page(Data)
     
     
    case unsupported
     
     
    case notNow
}

extension NodesCommanding {
    var nodeListRevision: String? { nil }
    var nodePages: NodePageSource? { nil }
    func nodesProxyDelaysPage(since: Int64, after: String, limit: Int) async -> Data? { nil }
    func nodesProxyDelaysPageRead(since: Int64, after: String, limit: Int) async -> DelayPageRead {
        if let data = await nodesProxyDelaysPage(since: since, after: after, limit: limit) { return .page(data) }
        return .unsupported
    }
    func nodesProviderReadings(named name: String, since: Int64) async -> [String: Int]? { nil }
}

extension NodesCommanding {
     
     
     
     
    func nodesTestDelayWithReason(
        name: String,
        url: String
    ) async -> (delay: Int, category: String) {
        (await nodesTestDelay(name: name, url: url), "")
    }
}

extension NodesCommanding {
     
     
    var extensionMemoryBytes: Int64 { 0 }
}

extension ClashCommandClient: NodesCommanding {
    var extensionMemoryBytes: Int64 { memoryBytes }
    var nodeListRevision: String? { nodeSummary?.revision }
    var nodePages: NodePageSource? { nodeSummary == nil ? nil : self }

    func nodesTestDelay(name: String, url: String) async -> Int {
        await nodesTestDelayWithReason(name: name, url: url).delay
    }

    func nodesTestDelayWithReason(
        name: String,
        url: String
    ) async -> (delay: Int, category: String) {
        let outcome = await urlTestQuietly(name: name, url: url)
         
         
        let delay = outcome.failureCategory == "admission-deferred"
            ? -2
            : outcome.delay
        return (delay, outcome.failureCategory)
    }

    func extensionFootprintBytes() async -> Int64 {
         
         
         
        await sweepFootprintBytes()
    }

    func nodesProviderCatalog() async throws -> ProviderRuntimeCatalog {
        try await providerRuntimeCatalog()
    }

    func nodesProviderReadings(named name: String, since: Int64) async -> [String: Int]? {
        nodeSummary == nil ? nil : await providerReadings(named: name, since: since)
    }

    func nodesHealthCheckProvider(named name: String) async -> [String: Int] {
         
         
        if nodeSummary != nil {
            let started = Int64(Date().timeIntervalSince1970 * 1_000) - 1_000
            guard await healthCheckProxyProviderOnly(named: name) else { return [:] }
            return await providerReadings(named: name, since: started) ?? [:]
        }
        guard let provider = try? await healthCheckProxyProvider(named: name) else {
            return [:]
        }
        return provider.proxies.reduce(into: [String: Int]()) { result, proxy in
            if let delay = proxy.latestDelayMilliseconds, delay > 0 {
                result[proxy.name] = delay
            } else if proxy.alive == false {
                result[proxy.name] = -1
            }
        }
    }

    func reconnectAfterRuntimeChange() {
        reconnectIfNeeded()
    }

    func nodesProxyDelays() async -> Data? {
        await proxyDelays()
    }

    func nodesProxyDelaysPage(since: Int64, after: String, limit: Int) async -> Data? {
        await proxyDelaysPage(since: since, after: after, limit: limit)
    }

    func nodesProxyDelaysPageRead(since: Int64, after: String, limit: Int) async -> DelayPageRead {
        await proxyDelaysPageRead(since: since, after: after, limit: limit)
    }

    func nodesRefreshMetadata() async -> Bool {
        await refreshMetadataReadingProxies()
    }
}

extension NodesCommanding {
     
    var isReopeningControlSession: Bool { false }

    func extensionFootprintBytes() async -> Int64 { 0 }

    var mode: String { "rule" }
    func unfix(group: String) async -> Bool { false }
    var lastCommandError: String { "" }
    func reconnectAfterRuntimeChange() {}
    func nodesProviderCatalog() async throws -> ProviderRuntimeCatalog { .empty }
    func nodesHealthCheckProvider(named name: String) async -> [String: Int] { [:] }
    func nodesProxyDelays() async -> Data? { nil }
    func nodesRefreshMetadata() async -> Bool {
        await refreshMetadata()
        return true
    }
}

extension JSONEncoder {
     
    static var sortedKeys: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

struct NodesRuntimeIdentity: Equatable {
    let profileID: String
    let revision: String

    static func load() -> NodesRuntimeIdentity? {
        guard let container = ClashAppIdentifiers.appGroupContainer,
        let store = try? ConfigResourceStore(containerURL: container),
        let pointer = try? store.activeIdentity() else {
            return nil
        }
        return NodesRuntimeIdentity(
            profileID: pointer.profileID,
            revision: pointer.revision
        )
    }
}

 
 
 
 
 
 
 
 
 
enum ConfigurationSections {
     
    static let longLines = 5_000

    private struct Outline: Decodable {
        struct Item: Decodable { let start: Int; let end: Int }
        struct Section: Decodable { let key: String; let start: Int; let end: Int; let items: [Item]? }
        let ok: Bool
        let sections: [Section]?
    }

     
     
     
     
    static func entries(mentioning name: String, inSection key: String, of yaml: String) -> [String]? {
         
         
         
         
        var text = yaml
        if yaml.utf8.count >= ConfigTransforms.ruleSectionCutFromBytes,
           let section = text.withUTF8({ TopLevelYAMLSections.section(key, inBytes: $0) }), !section.isEmpty,
           let items = SequenceLines.items(of: section) {
            return items.filter { $0.contains(name) }.map { "\(key):\n" + $0 }
        }
        guard let json = try? ConfigTransforms.yamlOutline(original: yaml),
              let outline = try? JSONDecoder().decode(Outline.self, from: Data(json.utf8)), outline.ok
        else { return nil }
        guard let section = outline.sections?.first(where: { $0.key == key }), let items = section.items else { return [] }
        let lines = yaml.split(separator: "\n", omittingEmptySubsequences: false)
        return items.compactMap { item in
            guard item.start >= 1, item.end <= lines.count, item.start <= item.end else { return nil }
            let text = lines[(item.start - 1)...(item.end - 1)].joined(separator: "\n")
            return text.contains(name) ? "\(key):\n" + text : nil
        }
    }

     
     
     
     
     
     
    static func writesNodes(inFileAt url: URL) -> Bool {
        guard let data = try? Data(contentsOf: url, options: [.alwaysMapped]) else { return false }
        let section = data.withUnsafeBytes { TopLevelYAMLSections.section("proxies", inBytes: $0.bindMemory(to: UInt8.self)) }
        if let section { return !section.isEmpty && writesNodes(in: section) }
        return (try? String(contentsOf: url, encoding: .utf8)).map(writesNodes(in:)) ?? false
    }

    static func writesNodes(in yaml: String) -> Bool {
        var from = yaml.startIndex
        while let key = yaml.range(of: "proxies:", range: from..<yaml.endIndex) {
            from = key.upperBound
            guard key.lowerBound == yaml.startIndex || yaml[yaml.index(before: key.lowerBound)] == "\n" else { continue }
            var lines = yaml[key.upperBound...].split(separator: "\n", maxSplits: 64, omittingEmptySubsequences: false)
                .makeIterator()
            let inline = (lines.next() ?? "").trimmingCharacters(in: .whitespaces)
            if !inline.isEmpty, !inline.hasPrefix("#") {
                 
                return inline != "[]" && inline != "~" && inline != "null"
            }
            while let line = lines.next() {
                let entry = line.trimmingCharacters(in: .whitespaces)
                if entry.isEmpty || entry.hasPrefix("#") { continue }
                return entry.hasPrefix("-") && line.first != nil && (line.first == " " || line.first == "-" || line.first == "\t")
            }
            return false
        }
        return false
    }

     
     
     
    static func entryCount(ofSection key: String, in yaml: String) -> Int? {
        if yaml.utf8.count >= ConfigTransforms.ruleSectionCutFromBytes {
             
            var text = yaml
            switch text.withUTF8({ TopLevelYAMLSections.section(key, inBytes: $0) }) {
            case ""?: return 0
            case let section?: if let count = SequenceLines.count(of: section) { return count }
            case nil: break
            }
        }
        guard let json = try? ConfigTransforms.yamlOutline(original: yaml),
              let outline = try? JSONDecoder().decode(Outline.self, from: Data(json.utf8)), outline.ok
        else { return nil }
        return outline.sections?.first(where: { $0.key == key })?.items?.count ?? 0
    }

     
     
    static func entryCount(ofSection key: String, inFileAt url: URL) -> Int? {
        guard let data = try? Data(contentsOf: url, options: [.alwaysMapped]) else { return nil }
        switch data.withUnsafeBytes({ TopLevelYAMLSections.section(key, inBytes: $0.bindMemory(to: UInt8.self)) }) {
        case ""?: return 0
        case let section?: return SequenceLines.count(of: section)
        case nil: return nil
        }
    }

     
     
    static func droppingLong(_ keys: Set<String>, from yaml: String) -> String? {
        droppingLongCounting(keys, from: yaml)?.text
    }

     
     
    static func droppingLongCounting(_ keys: Set<String>, from yaml: String) -> (text: String, counts: [String: Int])? {
         
         
         
        if yaml.utf8.count >= ConfigTransforms.ruleSectionCutFromBytes,
           let cut = TopLevelYAMLSections.cutting(keys, from: yaml) {
            var long: [String: Int] = [:]
            var readable = true
            for section in cut.sections {
                guard let count = SequenceLines.count(of: section.text) else { readable = false; break }
                if SequenceLines.lineSpan(of: section.text) >= longLines { long[section.key] = count }
            }
            if readable {
                guard !long.isEmpty else { return nil }
                if long.count == cut.sections.count { return (cut.rest, long) }
                if let longCut = TopLevelYAMLSections.cutting(Set(long.keys), from: yaml) { return (longCut.rest, long) }
            }
        }
        guard let json = try? ConfigTransforms.yamlOutline(original: yaml),
              let outline = try? JSONDecoder().decode(Outline.self, from: Data(json.utf8)), outline.ok
        else { return nil }
        let dropped = (outline.sections ?? []).filter { keys.contains($0.key) && $0.end - $0.start >= longLines }
        guard !dropped.isEmpty else { return nil }
        let counts = Dictionary(dropped.map { ($0.key, $0.items?.count ?? 0) }, uniquingKeysWith: { first, _ in first })
        var kept: [Substring] = []
        var lineNumber = 0
        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            if dropped.contains(where: { lineNumber >= $0.start && lineNumber <= $0.end }) { continue }
            kept.append(line)
        }
        return (kept.joined(separator: "\n"), counts)
    }
}

struct NodesInventoryProjection: Equatable, Sendable {
    var protocolDetails: [String: ProxyProtocolDetails] = [:]
    var groupDetails: [String: ProxyGroupConfigurationDetails] = [:]
    var order: ConfiguredProxyOrder = .none
    var trafficUsage: [String: ProxyTrafficUsage] = [:]

     
    static var wholeReadBytes: Int {
        get { ConfigTransforms.largeTextBytes }
        set { ConfigTransforms.largeTextBytes = newValue }
    }

    static func read(yaml: String) -> NodesInventoryProjection {
         
         
         
         
         
         
         
        if yaml.utf8.count > wholeReadBytes, let reduced = ConfigurationSections.droppingLong(["proxies", "rules"], from: yaml) {
            return NodesInventoryProjection(
                protocolDetails: [:],
                groupDetails: ProxyGroupConfigurationInspector.detailsByGroupName(yaml: reduced),
                order: ConfiguredProxyOrder.read(yaml: reduced),
                trafficUsage: ProxyTrafficUsageInspector.summariesByGroupName(yaml: reduced)
            )
        }
        return NodesInventoryProjection(
            protocolDetails: ProxyConfigurationInspector.detailsByNodeName(yaml: yaml),
            groupDetails: ProxyGroupConfigurationInspector.detailsByGroupName(yaml: yaml),
            order: ConfiguredProxyOrder.read(yaml: yaml),
            trafficUsage: ProxyTrafficUsageInspector.summariesByGroupName(yaml: yaml)
        )
    }
}

 
 
 
 
 
enum OfflineCatalogChange {
    static func isUnchanged(
        _ snapshot: OfflineProxyCatalogSnapshot?,
        previousRuntime: Data?,
        previousYAML: String?,
        previousProviderCatalog: ProviderRuntimeCatalog = .empty
    ) -> Bool {
        guard let snapshot, let previousYAML else { return false }
        return snapshot.runtimeData == previousRuntime && snapshot.yaml == previousYAML
            && snapshot.providerCatalog == previousProviderCatalog
    }
}

struct OfflineProxyCatalogSnapshot {
    let profileID: String
    let yaml: String
    let selectedMap: [String: String]
    let runtimeData: Data
    var cachedProviderNodeCount: Int? = nil
     
     
    var providerCatalog: ProviderRuntimeCatalog = .empty
}

 
 
 
 
 
 
 
 
enum OfflineProxyCatalogBuilder {
    static func runtimeData(
        yaml: String,
        selectedMap: [String: String],
        resourceMapJSON: String = ""
    ) -> Data? {
        guard let selections = try? JSONEncoder().encode(selectedMap),
              let catalog = try? OfflineProxyCatalogLoader.catalog(
                  configContent: yaml,
                  resourceMapJSON: resourceMapJSON,
                  selectionsJSON: String(decoding: selections, as: UTF8.self)
              )
        else { return nil }
        return runtimeData(kernelCatalog: catalog)?.data
    }

     
     
     
     
     
     
     
    static func runtimeData(kernelCatalog: Data) -> (
        data: Data, providerCatalog: ProviderRuntimeCatalog, providerNodeCount: Int
    )? {
        guard let root = try? JSONSerialization.jsonObject(with: kernelCatalog) as? [String: Any],
              var proxies = root["proxies"] as? [String: Any]
        else { return nil }
        for (name, value) in proxies {
            guard var entry = value as? [String: Any], entry["fixed"] != nil else { continue }
            entry.removeValue(forKey: "fixed")
            proxies[name] = entry
        }
         
         
         
         
         
        let providersDocument = ["providers": root["providers"] ?? [String: Any]()]
        guard let data = try? JSONSerialization.data(withJSONObject: ["proxies": proxies]),
              let providersData = try? JSONSerialization.data(withJSONObject: providersDocument),
              let providerCatalog = try? ProviderRuntimeCatalogParser.catalog(
                  proxyJSON: String(decoding: providersData, as: UTF8.self),
                  ruleJSON: #"{"providers":{}}"#
              )
        else { return nil }
        let providerNodeCount = providerCatalog.proxyProviders.values
            .filter { !$0.isKernelInternal }
            .reduce(0) { $0 + $1.nodeCount }
        return (data, providerCatalog, providerNodeCount)
    }
}

enum OfflineProxyCatalogLoader {
     
     
    private struct SourceKey: Equatable {
        let profileID: String
        let pointer: ActiveConfigurationPointer?
        let sidecarSize: Int
        let sidecarModified: Double
         
         
         
         
        let presentation: String
    }

     
     
     
     
     
     
    private static let memoLock = NSLock()
    private static var textMemo: (key: SourceKey, text: String)?
    private static var snapshotMemo: (key: String, snapshot: OfflineProxyCatalogSnapshot?)?

    static func resetMemoForTesting() {
        memoLock.lock(); defer { memoLock.unlock() }
        textMemo = nil
        snapshotMemo = nil
    }

    static func load() -> OfflineProxyCatalogSnapshot? {
        guard let container = ClashAppIdentifiers.appGroupContainer else { return nil }
        return load(containerURL: container)
    }

     
     
     
    private struct PresentedDocument {
        let working: URL
        let configStore: ConfigResourceStore?
        let activePointer: ActiveConfigurationPointer?
        let profileID: String
        let profile: Profile
        let sourceKey: SourceKey
        let yaml: String
         
         
        var publishedRevision: String? = nil
         
         
        var sourceWritesNodes: Bool? = nil
    }

    private static func presentedDocument(
        containerURL container: URL,
        preferredProfileID: String?,
        readingPublication: Bool = true
    ) -> PresentedDocument? {
        let working = container.appendingPathComponent("working", isDirectory: true)
        let profileStore = ProfileStore(
            fileURL: working.appendingPathComponent("store/profiles.json")
        )
        try? LocalDefaultProfileProvisioner.provisionIfNeeded(
            store: profileStore,
            workingDirectory: working
        )
        let profiles = profileStore.load().sorted { $0.order < $1.order }
        let configStore = try? ConfigResourceStore(containerURL: container)
        let activePointer: ActiveConfigurationPointer? = {
            guard let configStore else { return nil }
            return try? configStore.activeIdentity()
        }()
        let profileID = preferredProfileID
            ?? activePointer?.profileID
            ?? ProfileCenterPolicy.automaticSelectionID(
                profiles: profiles,
                activeProfileID: nil
            )
        guard let profileID,
              let profile = profiles.first(where: { $0.id == profileID }) else { return nil }

        let sidecarURL = working
            .appendingPathComponent("store/\(profileID)", isDirectory: true)
            .appendingPathComponent("source.yaml")
         
         
        let sidecarAttributes = try? FileManager.default.attributesOfItem(atPath: sidecarURL.path)
        let usesPointer = sidecarAttributes == nil && activePointer?.profileID == profileID && configStore != nil
         
         
         
         
        let sidecarBytes = (sidecarAttributes?[.size] as? NSNumber)?.intValue ?? -1
        let mayReadPublished = readingPublication && !usesPointer && sidecarBytes > PublishedPresentation.largeSourceBytes
            && activePointer?.profileID == profileID && configStore != nil
        let scriptBody = usesPointer
            ? nil
            : ScriptLibrary.load().first { $0.id == profile.selectedScriptID }?.body
        let sourceKey = SourceKey(
            profileID: profileID,
            pointer: usesPointer || mayReadPublished ? activePointer : nil,
            sidecarSize: (sidecarAttributes?[.size] as? NSNumber)?.intValue ?? -1,
            sidecarModified: (sidecarAttributes?[.modificationDate] as? Date)?
                .timeIntervalSince1970 ?? -1,
            presentation: usesPointer
                ? ""
                : ProxiesPresentedDocument.key(projectionKey: "", profile: profile, scriptBody: scriptBody)
        )
        memoLock.lock()
        let rememberedText = textMemo.flatMap { $0.key == sourceKey ? $0.text : nil }
        memoLock.unlock()

        let yaml: String
        var publishedRevision: String?
        var sourceWritesNodes: Bool?
        if let rememberedText {
            yaml = rememberedText
            if mayReadPublished, let pointer = activePointer, ConfigTransforms.nodeLibraryPath(in: rememberedText) != nil {
                publishedRevision = pointer.revision
                sourceWritesNodes = ConfigurationSections.writesNodes(inFileAt: sidecarURL)
            }
        } else if usesPointer,
           let configStore,
           let current = try? configStore.loadCurrent().text {
            yaml = current
        } else {
            let source = working
                .appendingPathComponent("store/\(profileID)", isDirectory: true)
                .appendingPathComponent("source.yaml")
             
             
             
            if mayReadPublished, let configStore, let pointer = activePointer,
               let prefix = PublishedPresentation.sourcePrefix(fileAt: source),
               let published = PublishedPresentation.currentText(
                   of: pointer, store: configStore, sourcePrefix: prefix, profile: profile, workingDirectory: working) {
                yaml = published
                publishedRevision = pointer.revision
                sourceWritesNodes = ConfigurationSections.writesNodes(inFileAt: source)
            } else if let leaving = ProfilesViewModel.presentedDocumentLeavingRules(sourceAt: source, profile: profile,
                                                                                   marked: false) {
                 
                 
                 
                yaml = leaving
            } else {
                guard let stored = try? String(contentsOf: source, encoding: .utf8) else {
                    return nil
                }
                 
                 
                 
                 
                 
                 
                 
                 
                 
                 
                yaml = ProxiesPresentedDocument.make(source: stored, profile: profile, fallback: nil)
                    ?? CustomNodesGroupMaterializer.projectForUI(sourceYAML: stored, profile: profile)
                    ?? stored
            }
        }
         
         
         
        memoLock.lock()
        textMemo = (sourceKey, yaml)
        memoLock.unlock()
        return PresentedDocument(
            working: working, configStore: configStore, activePointer: activePointer,
            profileID: profileID, profile: profile, sourceKey: sourceKey, yaml: yaml,
            publishedRevision: publishedRevision, sourceWritesNodes: sourceWritesNodes
        )
    }

     
     
     
     
     
    private static func checkedDocument(
        containerURL container: URL,
        preferredProfileID: String?
    ) -> (document: PresentedDocument, input: OfflineProxyCatalogInput)? {
        guard let document = presentedDocument(containerURL: container, preferredProfileID: preferredProfileID),
              let input = input(document)
        else { return nil }
        guard let revision = document.publishedRevision, let sourceWritesNodes = document.sourceWritesNodes,
              !PublishedPresentation.opensWhole(input.configContent, revision: revision,
                                                sourceWritesNodes: sourceWritesNodes,
                                                resourceMapJSON: input.resourceMapJSON,
                                                selectionsJSON: input.selectionsJSON)
        else { return (document, input) }
        guard let built = presentedDocument(containerURL: container, preferredProfileID: preferredProfileID,
                                            readingPublication: false),
              let builtInput = Self.input(built)
        else { return nil }
        return (built, builtInput)
    }

    static func load(
        containerURL container: URL,
        preferredProfileID: String? = nil
    ) -> OfflineProxyCatalogSnapshot? {
        guard let (document, input) = checkedDocument(containerURL: container, preferredProfileID: preferredProfileID)
        else { return nil }
        let (profileID, profile, sourceKey, yaml) = (
            document.profileID, document.profile, document.sourceKey, document.yaml
        )
        memoLock.lock()
        let remembered = snapshotMemo.flatMap { $0.key == input.fingerprint ? $0 : nil }
        memoLock.unlock()
        if let remembered { return remembered.snapshot }
         
         
         
        let catalog: Data
        do {
             
             
             
            catalog = try Self.catalog(input)
        } catch OfflineProxyCatalogError.coreUnavailable {
             
             
             
            memoLock.lock()
            let last = snapshotMemo?.snapshot.flatMap { $0.profileID == profileID ? $0 : nil }
            memoLock.unlock()
            return last
        } catch is CancellationError {
             
            memoLock.lock()
            let last = snapshotMemo?.snapshot.flatMap { $0.profileID == profileID ? $0 : nil }
            memoLock.unlock()
            return last
        } catch {
            catalog = Data()
        }
        guard let runtime = OfflineProxyCatalogBuilder.runtimeData(kernelCatalog: catalog) else {
            memoLock.lock()
            snapshotMemo = (input.fingerprint, nil)
            memoLock.unlock()
            return nil
        }
        let snapshot = OfflineProxyCatalogSnapshot(
            profileID: profileID,
            yaml: yaml,
            selectedMap: profile.selectedMap,
            runtimeData: runtime.data,
            cachedProviderNodeCount: runtime.providerNodeCount,
            providerCatalog: runtime.providerCatalog
        )
        memoLock.lock()
        snapshotMemo = (input.fingerprint, snapshot)
        memoLock.unlock()
        return snapshot
    }

     
     
     
     
     
    static func input(
        containerURL: URL? = ClashAppIdentifiers.appGroupContainer,
        preferredProfileID: String? = nil
    ) -> OfflineProxyCatalogInput? {
        guard let containerURL else { return nil }
        return checkedDocument(containerURL: containerURL, preferredProfileID: preferredProfileID)?.input
    }

     
     
     
     
     
     
     
     
    private static func input(_ document: PresentedDocument) -> OfflineProxyCatalogInput? {
        var files = ConfigurationCollectionContentBridge.cachedNodeFiles(
            yaml: document.yaml, workingDirectory: document.working
        )
         
         
        var published: (directory: URL, catalog: ProviderCatalog)?
        if let pointer = document.activePointer, pointer.profileID == document.profileID,
           let directory = document.configStore?.providersDirectory(
               profileID: pointer.profileID, revision: pointer.revision
           ),
           let catalog = ProviderCatalog.load(providersDir: directory) {
            published = (directory, catalog)
        }
        if let (directory, catalog) = published {
             
             
            let definitionsText = document.yaml.utf8.count > NodesInventoryProjection.wholeReadBytes
                ? ConfigurationSections.droppingLong(["proxies", "rules"], from: document.yaml) ?? document.yaml
                : document.yaml
            let definitions = ConfigTransforms.parsedRoot(forYAML: definitionsText)?
                .root["proxy-providers"] as? [String: [String: Any]] ?? [:]
            func modified(_ file: URL) -> Date {
                (try? FileManager.default.attributesOfItem(atPath: file.path)[.modificationDate]) as? Date ?? .distantPast
            }
            for entry in catalog.entries where entry.kind == "proxy" {
                guard let url = definitions[entry.name]?["url"] as? String,
                      (entry.payloadURL ?? entry.url) == url else { continue }
                let file = directory.appendingPathComponent(entry.path)
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                if let library = files[entry.name], modified(library) >= modified(file) { continue }
                files[entry.name] = file
            }
        }
         
         
         
         
        var ruleFiles: [String: URL] = [:]
        if let (directory, catalog) = published {
            for entry in catalog.entries where entry.kind == "rule" {
                let file = directory.appendingPathComponent(entry.path)
                if FileManager.default.fileExists(atPath: file.path) { ruleFiles[entry.name] = file }
            }
        }
        var providerPaths: [String: String] = [:]
        var fileStamps: [String] = []
        for (name, file) in ruleFiles {
            providerPaths["rule:\(name)"] = file.path
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            fileStamps.append(
                "rule:" + name + "=" + file.path + ":" + String(describing: attributes?[.size]) + ":"
                    + String((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1)
            )
        }
        for (name, file) in files {
            providerPaths["proxy:\(name)"] = file.path
            let attributes = try? FileManager.default.attributesOfItem(atPath: file.path)
            fileStamps.append(
                name + "=" + file.path + ":" + String(describing: attributes?[.size]) + ":"
                    + String((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? -1)
            )
        }
        let selectedMap = document.profile.selectedMap
         
         
         
         
        let libraries = NodeLibraries.directory(container: document.working.deletingLastPathComponent())
        guard let map = try? JSONSerialization.data(
                  withJSONObject: ["providerPaths": providerPaths, "nodeLibraryDirectory": libraries.path],
                  options: [.sortedKeys]),
              let selections = try? JSONEncoder().encode(selectedMap)
        else { return nil }
         
         
         
         
         
         
         
        let downloadStamps = ["proxies", "rules"].flatMap { folder -> [String] in
            let cache = document.working.appendingPathComponent(folder, isDirectory: true)
            return ((try? FileManager.default.contentsOfDirectory(
                at: cache, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            )) ?? []).map { file -> String in
                let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return folder + "/" + file.lastPathComponent + ":" + String(values?.fileSize ?? -1) + ":"
                    + String(values?.contentModificationDate?.timeIntervalSince1970 ?? -1)
            }
        }.sorted().joined(separator: ",")
        let sourceKey = document.sourceKey
        let fingerprint = [
            downloadStamps,
            sourceKey.profileID,
            String(describing: sourceKey.pointer),
            "\(sourceKey.sidecarSize):\(sourceKey.sidecarModified)",
            sourceKey.presentation,
            fileStamps.sorted().joined(separator: ","),
            selectedMap.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ","),
        ].joined(separator: "|")
        return OfflineProxyCatalogInput(
            profileID: document.profileID,
            configContent: document.yaml,
            resourceMapJSON: String(decoding: map, as: UTF8.self),
            selectionsJSON: String(decoding: selections, as: UTF8.self),
            fingerprint: fingerprint,
            libraryContainer: document.working.deletingLastPathComponent()
        )
    }
}

extension OfflineProxyCatalogLoader {
     
     
     
     
     
     
     
     
     
    static func catalog(
        _ input: OfflineProxyCatalogInput,
        holder: OfflineNodeCatalogRegistry.Holder? = .nodesPage,
        containerURL: URL? = AppCoreSetup.applicationContainer
    ) throws -> Data {
         
         
         
         
         
         
        if let hit = CatalogAnswerMemo.answer(for: input.fingerprint),
           holder.map({ OfflineNodeCatalogRegistry.isHeld(input.fingerprint, by: $0) }) ?? true {
            return hit
        }
        let answer = try catalog(
            configContent: input.configContent,
            resourceMapJSON: input.resourceMapJSON,
            selectionsJSON: input.selectionsJSON,
            containerURL: containerURL,
            fingerprint: input.fingerprint,
            holder: holder,
            libraryContainer: input.libraryContainer
        )
        CatalogAnswerMemo.remember(answer, for: input.fingerprint)
        return answer
    }

     
     
     
     
     
     
     
    static func catalog(
        configContent: String,
        resourceMapJSON: String,
        selectionsJSON: String,
        containerURL: URL? = AppCoreSetup.applicationContainer,
        fingerprint: String? = nil,
        holder: OfflineNodeCatalogRegistry.Holder? = .nodesPage,
        libraryContainer: URL? = nil
    ) throws -> Data {
        guard let container = containerURL else { throw OfflineProxyCatalogError.coreUnavailable }
        let key = fingerprint ?? "\(configContent.hashValue)|\(resourceMapJSON)|\(selectionsJSON)"
         
        let reader = holder ?? OfflineNodeCatalogRegistry.Holder(id: "answer-" + UUID().uuidString)
        defer { if holder == nil { OfflineNodeCatalogRegistry.release(reader) } }
        let answer: Result<String, Error>
        do {
            answer = try AppCoreSetup.withConfiguration(container: container) {
                Result {
                     
                     
                     
                     
                     
                    let catalog = try openedCatalog(
                        configContent: configContent, resourceMapJSON: resourceMapJSON,
                        selectionsJSON: selectionsJSON, container: libraryContainer ?? container, fingerprint: key,
                        holder: reader
                    )
                    let answer = try CompactProxiesDocument.offlineCatalogAnswer(catalog)
                    return String(decoding: answer, as: UTF8.self)
                }
            }
        } catch {
            throw OfflineProxyCatalogError.coreUnavailable
        }
        return try verdict(answer)
    }

     
     
     
     
     
     
     
     
     
     
     
    static func publishedNodeCount(
        profileID: String,
        containerURL: URL? = ClashAppIdentifiers.appGroupContainer
    ) -> Int? {
        guard let containerURL,
              let document = presentedDocument(containerURL: containerURL, preferredProfileID: profileID),
              ConfigTransforms.nodeLibraryPath(in: document.yaml) != nil,
              let input = input(document)
        else { return nil }
        let holder = OfflineNodeCatalogRegistry.Holder(id: "home-count-" + UUID().uuidString)
        defer { OfflineNodeCatalogRegistry.release(holder) }
        guard let catalog = try? sharedCatalog(input, holder: holder),
              let data = try? catalog.withCatalog({ Data($0.summaryJSON().utf8) }),
              let summary = try? data.decoded(NodeSummary.self)
        else { return nil }
        return summary.nodes
    }

     
     
     
     
     
     
     
     
     
    static func nodeConfig(
        named name: String,
        profileID: String?,
        containerURL: URL? = ClashAppIdentifiers.appGroupContainer
    ) -> NodeConfigAnswer? {
        guard let input = input(containerURL: containerURL, preferredProfileID: profileID) else { return nil }
        let holder = OfflineNodeCatalogRegistry.Holder(id: "node-detail-" + UUID().uuidString)
        defer { OfflineNodeCatalogRegistry.release(holder) }
        guard let catalog = try? sharedCatalog(input, holder: holder),
              let json = try? catalog.withCatalog({ AppCore.nodeConfigJSON($0, provider: "*", name: name) })
        else { return nil }
        return NodeConfigAnswer(json: json)
    }

    static func sharedCatalog(
        _ input: OfflineProxyCatalogInput,
        holder: OfflineNodeCatalogRegistry.Holder,
        containerURL: URL? = AppCoreSetup.applicationContainer
    ) throws -> OfflineNodeCatalog {
        guard let container = containerURL else { throw OfflineProxyCatalogError.coreUnavailable }
        let opened: Result<OfflineNodeCatalog, Error>
        do {
            opened = try AppCoreSetup.withConfiguration(container: container) {
                Result {
                    try openedCatalog(
                        configContent: input.configContent, resourceMapJSON: input.resourceMapJSON,
                        selectionsJSON: input.selectionsJSON, container: input.libraryContainer ?? container,
                        fingerprint: input.fingerprint, holder: holder
                    )
                }
            }
        } catch {
            throw OfflineProxyCatalogError.coreUnavailable
        }
        return try opened.get()
    }

     
     
    private static func openedCatalog(
        configContent: String,
        resourceMapJSON: String,
        selectionsJSON: String,
        container: URL,
        fingerprint: String,
        holder: OfflineNodeCatalogRegistry.Holder
    ) throws -> OfflineNodeCatalog {
        var opened = false
        let catalog = try OfflineNodeCatalogRegistry.take(fingerprint, for: holder) {
            opened = true
            let text = catalogText(configContent, resourceMapJSON: resourceMapJSON, container: container)
            noteOpening(text, resourceMapJSON: resourceMapJSON, selectionsJSON: selectionsJSON,
                        holder: holder.id, key: fingerprint)
            var error: NSError?
            guard let catalog = AppCore.openNodeCatalog(text, resourceMapJSON, selectionsJSON, &error) else {
                throw error ?? NodePageSourceError.unavailable
            }
            return OfflineNodeCatalog(catalog)
        }
        if !opened {
            ClashLogStore.shared.append("offline catalog reused  key=\(fingerprint.prefix(16)) holder=\(holder.id)", stream: .app)
        }
        return catalog
    }

     
     
     
     
    static func noteOpening(_ text: String, resourceMapJSON: String, selectionsJSON: String, holder: String, key: String) {
        let library = ConfigTransforms.nodeLibraryPath(in: text) ?? "none"
        ClashLogStore.shared.append(
            "offline catalog opens  bytes=\(text.utf8.count) library=\(library) holder=\(holder) key=\(key.prefix(16))",
            stream: .app)


    }

     
     
     
     
     
     
     
     
     
    static func catalogText(_ content: String, resourceMapJSON: String, container: URL) -> String {
        guard content.utf8.count > PublishedPresentation.largeSourceBytes,
              ConfigTransforms.nodeLibraryPath(in: content) == nil,
              let map = try? JSONSerialization.jsonObject(with: Data(resourceMapJSON.utf8)) as? [String: Any]
        else { return content }
        let paths = map["providerPaths"] as? [String: String] ?? [:]
        guard let finalized = try? ConfigTransforms.finalize(
                  mergedYAML: content, providerPaths: paths,
                  nodeLibraryDirectory: NodeLibraries.directory(container: container),
                  ruleIndexDirectory: NodeLibraries.directory(container: container)),
              ConfigTransforms.nodeLibraryPath(in: finalized) != nil
        else { return content }
        return finalized
    }

     
     
    static func releaseForConnection() {
        guard OfflineNodeCatalogRegistry.held(by: .nodesPage) != nil else { return }
        OfflineNodeCatalogRegistry.release(.nodesPage)
        memoLock.lock()
        snapshotMemo = nil
        memoLock.unlock()
        CatalogAnswerMemo.forget()
    }

     
     
     
    static func verdict(_ answer: Result<String, Error>) throws -> Data {
        switch answer {
        case .success(let text): return Data(text.utf8)
        case .failure(let error as CancellationError): throw error
        case .failure(let error): throw OfflineProxyCatalogError.refused(error.localizedDescription)
        }
    }
}

 
private enum CatalogAnswerMemo {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var last: (fingerprint: String, data: Data)?

    static func answer(for fingerprint: String) -> Data? {
        lock.lock(); defer { lock.unlock() }
        guard let last, last.fingerprint == fingerprint else { return nil }
        return last.data
    }

    static func remember(_ data: Data, for fingerprint: String) {
        lock.lock(); defer { lock.unlock() }
        last = (fingerprint, data)
    }

    static func forget() {
        lock.lock(); defer { lock.unlock() }
        last = nil
    }
}

extension OfflineProxyCatalogLoader {
     
     
     
     
     
     
     
     
     
     
    static func ruleSetCounts(_ input: OfflineProxyCatalogInput) -> [String: Int] {
        ruleSetMemoLock.lock()
        if let remembered = ruleSetMemo, remembered.key == input.fingerprint {
            ruleSetMemoLock.unlock()
            return remembered.counts
        }
        ruleSetMemoLock.unlock()
         
         
         
        guard let counts = countRuleSets(input) else { return [:] }
        ruleSetMemoLock.lock()
        ruleSetMemo = (input.fingerprint, counts)
        ruleSetMemoLock.unlock()
        return counts
    }

    private static let ruleSetMemoLock = NSLock()
    nonisolated(unsafe) private static var ruleSetMemo: (key: String, counts: [String: Int])?

    private static func countRuleSets(_ input: OfflineProxyCatalogInput) -> [String: Int]? {
        guard let container = AppCoreSetup.applicationContainer,
              let text = try? AppCoreSetup.withConfiguration(container: container, {
                  try ConfigTransforms.ruleProviderCatalog(
                      configContent: input.configContent,
                      resourceMapJSON: input.resourceMapJSON,
                      compileRuleSets: true
                  )
              }),
              let root = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        else { return nil }
        var counts: [String: Int] = [:]
        for case let (name, provider as [String: Any]) in (root["providers"] as? [String: Any]) ?? [:] {
            if let count = provider["ruleCount"] as? Int { counts[name] = count }
        }
        return counts
    }
}

enum OfflineProxyCatalogError: Error, Equatable {
    case coreUnavailable
     
    case refused(String)
}

 
 
struct OfflineProxyCatalogInput: Equatable, Sendable {
    let profileID: String
    let configContent: String
    let resourceMapJSON: String
    let selectionsJSON: String
    let fingerprint: String
     
     
     
     
    var libraryContainer: URL? = nil
}

 
 
 
 
 
 
 
 
enum BuiltinProxyName {
    static let direct = "DIRECT"
    static let all = LatencyProbeNamePolicy.builtinNames
}

 
 
 
 
 
 
enum GlobalProxySelectionPolicy {
    static let groupName = "GLOBAL"

     
     
     
     
    static func remembers(group: String) -> Bool { group != groupName }

    static func target(
        groups: [ProxyGroup],
        preferredGroupName: String?
    ) -> String? {
        guard let global = globalGroup(in: groups),
              ProxyGroupControlKind(rawType: global.type) == .manual else {
            return nil
        }

        let hasSafeCurrentRoute = isProxyMember(
            global.now,
            of: global,
            allGroups: groups
        )

         
         
         
         
        if hasSafeCurrentRoute,
           isExplicitProxyChoice(global.now, groups: groups) {
            return global.now
        }
        if let preferredGroupName,
           isProxyMember(preferredGroupName, of: global, allGroups: groups),
           isSafeManualGroup(preferredGroupName, groups: groups) {
            return preferredGroupName
        }
        if hasSafeCurrentRoute {
            return global.now
        }
        return global.members.first {
            isProxyMember($0, of: global, allGroups: groups)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func refusal(groups: [ProxyGroup]) -> String? {
        guard let global = globalGroup(in: groups) else {
             
             
            return """
                The core has not reported the built-in GLOBAL group yet. \
                Reconnect and try again.
                """
        }
         
         
         
         
        guard global.members.contains(where: {
            isProxyMember($0, of: global, allGroups: groups)
        }) else {
            return """
                The GLOBAL group has no proxy or policy group to select. Global \
                mode sends every flow through GLOBAL, so this profile needs at \
                least one outbound.
                """
        }
        return nil
    }

    static func isProxySelected(groups: [ProxyGroup]) -> Bool {
        guard let global = globalGroup(in: groups) else { return false }
        return isProxyMember(global.now, of: global, allGroups: groups)
    }

    static func isSafeManualGroup(
        _ name: String,
        groups: [ProxyGroup]
    ) -> Bool {
        guard let group = groups.first(where: { $0.name == name }),
              ProxyGroupControlKind(rawType: group.type) == .manual else {
            return false
        }
        let resolved = group.resolvedNow
        guard !resolved.isEmpty,
              !BuiltinProxyName.all.contains(resolved) else {
            return false
        }
        return !groups.contains { $0.name == resolved }
    }

    private static func globalGroup(in groups: [ProxyGroup]) -> ProxyGroup? {
         
         
        groups.first { $0.name == groupName }
    }

    private static func isExplicitProxyChoice(
        _ name: String,
        groups: [ProxyGroup]
    ) -> Bool {
        guard groups.contains(where: { $0.name == name }) else {
            return true
        }
        return isSafeManualGroup(name, groups: groups)
    }

    private static func isProxyMember(
        _ member: String,
        of global: ProxyGroup,
        allGroups: [ProxyGroup]
    ) -> Bool {
        guard !member.isEmpty, global.members.contains(member) else {
            return false
        }
        let resolved = global.memberResolvedNames[member] ?? member
        guard !resolved.isEmpty,
              !BuiltinProxyName.all.contains(resolved) else {
            return false
        }
         
         
        return !allGroups.contains { $0.name == resolved }
    }
}

enum NodeInventory {
     
     
    static func memberDelay(_ name: String, delays: [String: Int]) -> Int? {
        delays[name]
    }

     
     
    static func memberDelay(_ name: String, in group: ProxyGroup, delays: [String: Int]) -> Int? {
        ClashLatencyKey.reading(latencyKey(name, readingURL: readingURL(of: group)), in: delays)
    }

     
     
    static let kernelDefaultTestURL = "https://www.gstatic.com/generate_204"

     
     
     
     
     
     
     
     
     
     
    static func readingURL(of group: ProxyGroup) -> String? {
        switch ProxyGroupControlKind(rawType: group.type) {
        case .automatic, .loadBalance: return group.testURL ?? kernelDefaultTestURL
        case .manual, .readOnly: return nil
        }
    }

     
    static func readingURLs(of groups: [ProxyGroup]) -> Set<String> {
        Set(groups.compactMap(readingURL(of:)))
    }

     
     
     
    static func latencyKey(_ name: String, readingURL: String?) -> String {
        readingURL.map { ClashLatencyKey.recordKey(name, url: $0) } ?? name
    }


     
     
    static func isURLRecordKey(_ key: String) -> Bool {
        ClashLatencyKey.nodeName(ofRecordKey: key) != nil
    }

     
    static func nodeName(ofKey key: String) -> String {
        ClashLatencyKey.nodeName(ofRecordKey: key) ?? key
    }

     
     
     
    static func routeDelay(from groupName: String, groups: [ProxyGroup], delays: [String: Int]) -> Int? {
        routeDelay(
            from: groupName,
            byName: Dictionary(groups.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }),
            delays: delays
        )
    }

     
     
    static func routeDelay(from groupName: String, byName: [String: ProxyGroup], delays: [String: Int]) -> Int? {
        var current = byName[groupName]
        var visited = Set<String>()
        while let group = current, visited.insert(group.name).inserted {
            if let inner = byName[group.now] { current = inner; continue }
            return memberDelay(group.now, in: group, delays: delays)
        }
        return nil
    }

     
     
     
     
     
    static func groupTerminalKeys(groups: [ProxyGroup], defaultURL: String) -> [String: String] {
        let byName = Dictionary(groups.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var keys: [String: String] = [:]
        for start in groups {
            var current = start
            var visited: Set<String> = [start.name]
            while let inner = byName[current.now], visited.insert(inner.name).inserted { current = inner }
            guard byName[current.now] == nil, !current.now.isEmpty else { continue }
            keys[start.name] = latencyKey(current.now, readingURL: readingURL(of: current))
        }
        return keys
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static func latencyTarget(
        of name: String, inGroup groupName: String?, groups: [ProxyGroup]
    ) -> (name: String, endpoint: String?) {
        let byName = Dictionary(groups.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        guard let start = byName[name] else {
             
             
             
            return (name, groupName.flatMap { byName[$0] }.flatMap(probeURL(of:)))
        }
        var current = start
        var visited: Set<String> = [start.name]
        while let inner = byName[current.now], visited.insert(inner.name).inserted { current = inner }
        guard byName[current.now] == nil, !current.now.isEmpty else { return (name, start.testURL) }
        return (current.now, probeURL(of: current))
    }

     
     
    static func probeURL(of group: ProxyGroup) -> String? {
        readingURL(of: group) ?? group.testURL
    }

     
     
     
     
     
     
    struct PolledDelays {
        struct Selection: Equatable {
            let now: String
            let fixed: String?
        }
        let revision: String
        let selections: [String: Selection]
        let readings: [String: Int]

         
         
         
        func selectionsMatch(_ groups: [ProxyGroup]) -> Bool {
            groups.allSatisfy { selections[$0.name] == Selection(now: $0.now, fixed: $0.fixed) }
        }
    }

     
     
    struct DelayPageCursor: Decodable {
        let now: Int64?
        let next: String?
    }

    static func delayPageCursor(_ data: Data) -> DelayPageCursor? {
        guard let cursor = try? JSONDecoder().decode(DelayPageCursor.self, from: data) else { return nil }
        return DelayPageCursor(now: cursor.now, next: cursor.next.flatMap { $0.isEmpty ? nil : $0 })
    }

     
     
     
    static func mergedDelayPages(_ pages: [Data], readingURLs: Set<String> = []) -> (PolledDelays, Int64)? {
        var first: PolledDelays?
        var readings: [String: Int] = [:]
        var now: Int64 = 0
        for data in pages {
            guard let polled = polledDelays(from: data, readingURLs: readingURLs) else { return nil }
            if let first, first.revision != polled.revision { return nil }
            if first == nil {
                first = polled
                 
                 
                 
                now = delayPageCursor(data)?.now ?? 0
            }
            readings.merge(polled.readings) { _, newer in newer }
        }
        guard let first else { return nil }
        return (PolledDelays(revision: first.revision, selections: first.selections, readings: readings), now)
    }

     
     
    static func providerReadings(named name: String, in data: Data) -> [String: Int] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let nodes = (root["providers"] as? [String: Any])?[name] as? [String: Any]
        else { return [:] }
        var readings: [String: Int] = [:]
        for (node, raw) in nodes {
            guard let record = raw as? [String: Any] else { continue }
            if let delay = record["delay"] as? Int, delay > 0 {
                readings[node] = delay
            } else if record["alive"] as? Bool == false || record["delay"] != nil {
                readings[node] = -1
            }
        }
        return readings
    }

     
     
     
    static func polledDelays(from data: Data, readingURLs: Set<String> = []) -> PolledDelays? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let revision = root["revision"] as? String, !revision.isEmpty
        else { return nil }
        var readings: [String: Int] = [:]
         
        func readURLRecords(of name: String, in record: [String: Any]) {
            guard !readingURLs.isEmpty, let extra = record["extra"] as? [String: Any] else { return }
            for (url, raw) in extra where readingURLs.contains(url) {
                guard let state = raw as? [String: Any] else { continue }
                let reading: Int
                if let delay = state["delay"] as? Int, delay > 0 {
                    reading = delay
                } else if state["alive"] as? Bool == false || state["delay"] != nil {
                    reading = -1
                } else {
                    continue
                }
                readings[latencyKey(name, readingURL: url)] = reading
            }
        }
        for case let nodes as [String: Any] in ((root["providers"] as? [String: Any]) ?? [:]).values {
            for (name, raw) in nodes {
                guard let record = raw as? [String: Any] else { continue }
                if let delay = record["delay"] as? Int, delay > 0 {
                    readings[name] = delay
                } else if record["alive"] as? Bool == false {
                    readings[name] = -1
                }
                readURLRecords(of: name, in: record)
            }
        }
         
         
         
        for (name, raw) in (root["proxies"] as? [String: Any]) ?? [:] {
            guard let record = raw as? [String: Any] else { continue }
            if let delay = record["delay"] as? Int { readings[name] = delay > 0 ? delay : -1 }
            readURLRecords(of: name, in: record)
        }
        var selections: [String: PolledDelays.Selection] = [:]
        for (name, raw) in (root["groups"] as? [String: Any]) ?? [:] {
            guard let group = raw as? [String: Any] else { continue }
            selections[name] = .init(
                now: group["now"] as? String ?? "",
                fixed: (group["fixed"] as? String).flatMap { $0.isEmpty ? nil : $0 }
            )
            if let delay = group["delay"] as? Int { readings[name] = delay > 0 ? delay : -1 }
        }
        return PolledDelays(revision: revision, selections: selections, readings: readings)
    }

     
     
    static func reading(delays: [Int], alive: Bool?) -> Int? {
         
         
        if let last = delays.last { return last > 0 ? last : -1 }
        return alive == false ? -1 : nil
    }

     
     
     
     
    static func proxies(in data: Data?) -> [String: Any]? {
        guard let data,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
         
        guard let proxies = root["proxies"] as? [String: Any] else { return nil }
        return ModuleRouteHiding.stripping(proxies, hiding: ModuleRouteHiding.hiddenNames())
    }

    static func parse(
        _ data: Data?,
        groupConfigurationDetailsByName: [String: ProxyGroupConfigurationDetails] = [:],
        providerCatalog: ProviderRuntimeCatalog = .empty,
        configuredOrder: ConfiguredProxyOrder = .none
    ) -> ([ProxyGroup], [String: Int]) {
        parse(
            proxies: proxies(in: data),
            groupConfigurationDetailsByName: groupConfigurationDetailsByName,
            providerCatalog: providerCatalog,
            configuredOrder: configuredOrder
        )
    }

    static func parse(
        proxies: [String: Any]?,
        groupConfigurationDetailsByName: [String: ProxyGroupConfigurationDetails] = [:],
        providerCatalog: ProviderRuntimeCatalog = .empty,
        configuredOrder: ConfiguredProxyOrder = .none
    ) -> ([ProxyGroup], [String: Int]) {
        guard let proxies else { return ([], [:]) }

        var rawGroups: [
            String: (
                type: String, now: String, members: [String], hidden: Bool,
                testURL: String?, iconURL: String?, emptyFallback: String?, fixed: String?,
                total: Int?
            )
        ] = [:]
        var proxyTypes: [String: String] = [:]
         
         
         
         
        var proxyPlaceholderTypes: [String: String] = [:]
         
        var hiddenByGroup: [String: Set<String>] = [:]
        var delays: [String: Int] = [:]
         
         
        var urlRecords: [String: [String: Any]] = [:]

         
         
         
         
         
         
         
        for provider in providerCatalog.proxyProviders.values {
            for proxy in provider.proxies {
                if let type = proxy.type, !type.isEmpty {
                    proxyTypes[proxy.name] = type
                }
                if let delay = proxy.latestDelayMilliseconds, delay > 0 {
                    delays[proxy.name] = delay
                } else if proxy.alive == false {
                     
                     
                    delays[proxy.name] = -1
                }
            }
        }

        func firstOccurrences(of members: [String]) -> [String] {
            var seen = Set<String>()
            return members.filter { seen.insert($0).inserted }
        }

         
         
         
         
         
         
         
        func native(_ value: String) -> String {
            var copy = value
            copy.makeContiguousUTF8()
            return copy
        }
        for (rawName, raw) in proxies {
            guard let proxy = raw as? [String: Any] else { continue }
            let name = native(rawName)
            proxyTypes[name] = (proxy["type"] as? String).map(native) ?? "?"
            if let placeholder = proxy["placeholderType"] as? String, !placeholder.isEmpty {
                proxyPlaceholderTypes[name] = native(placeholder)
            }
            if let history = proxy["history"] as? [[String: Any]], let last = history.last {
                delays[name] = last["delay"] as? Int ?? -1
            }
            if let extra = proxy["extra"] as? [String: Any], proxy["all"] == nil {
                urlRecords[name] = extra
            }
            if let members = proxy["all"] as? [String] {
                if let hidden = proxy[ModuleRouteHiding.hiddenMembersKey] as? [String], !hidden.isEmpty {
                    hiddenByGroup[name] = Set(hidden.map(native))
                }
                let declaredURL = (proxy["testUrl"] as? String)
                    .flatMap { $0.isEmpty ? nil : native($0) }
                let declaredIcon = (proxy["icon"] as? String)
                    .flatMap { $0.isEmpty ? nil : native($0) }
                rawGroups[name] = (
                    (proxy["type"] as? String).map(native) ?? "?",
                    (proxy["now"] as? String).map(native) ?? "",
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    firstOccurrences(of: members.map(native)),
                    proxy["hidden"] as? Bool ?? false,
                    declaredURL,
                    declaredIcon,
                    (proxy["emptyFallback"] as? String).flatMap { $0.isEmpty ? nil : native($0) },
                     
                    (proxy["fixed"] as? String).flatMap { $0.isEmpty ? nil : native($0) },
                     
                     
                    proxy["total"] as? Int
                )
            }
        }

        func resolve(_ value: String) -> String {
            var current = value
            var visited = Set<String>()
            while let group = rawGroups[current], visited.insert(current).inserted,
                  !group.now.isEmpty {
                current = group.now
            }
            return current
        }

        let groups = rawGroups.map { name, value in
            ProxyGroup(
                name: name,
                type: value.type,
                now: value.now,
                members: value.members,
                resolvedNow: resolve(value.now),
                memberTypes: Dictionary(uniqueKeysWithValues: value.members.map {
                    ($0, proxyTypes[$0] ?? "?")
                }),
                memberGroupNames: Set(value.members.filter { rawGroups[$0] != nil }),
                memberResolvedNames: Dictionary(uniqueKeysWithValues: value.members.compactMap {
                    rawGroups[$0] == nil ? nil : ($0, resolve($0))
                }),
                memberPlaceholderTypes: Dictionary(uniqueKeysWithValues: value.members.compactMap {
                    member in proxyPlaceholderTypes[member].map { (member, $0) }
                }),
                configurationDetails: groupConfigurationDetailsByName[name],
                hidden: value.hidden,
                testURL: value.testURL,
                iconURL: value.iconURL,
                emptyFallback: value.emptyFallback,
                fixed: value.fixed,
                memberTotal: value.total,
                hiddenMembers: hiddenByGroup[name] ?? []
            )
        }
         
         
         
        let decidingURLs = readingURLs(of: groups)
        if !decidingURLs.isEmpty {
            for provider in providerCatalog.proxyProviders.values {
                for proxy in provider.proxies {
                    for (url, delay) in proxy.delaysByURL where decidingURLs.contains(url) {
                        delays[latencyKey(proxy.name, readingURL: url)] = delay
                    }
                }
            }
            for (name, extra) in urlRecords {
                for (url, raw) in extra where decidingURLs.contains(url) {
                    guard let state = raw as? [String: Any] else { continue }
                    let history = (state["history"] as? [[String: Any]])?.compactMap { $0["delay"] as? Int } ?? []
                    if let reading = reading(delays: history, alive: state["alive"] as? Bool) {
                        delays[latencyKey(name, readingURL: url)] = reading
                    }
                }
            }
        }
         
         
         
         
         
         
         
         
         
         
         
         
        let ordered = configuredOrder.sortedGroups(groups) { $0.name }
        return (ordered, delays)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func probeURLsByMember(
        in groups: [ProxyGroup],
        fallback: String
    ) -> [String: String] {
        var urls: [String: String] = [:]
        for group in groups where ProxyGroupControlKind(rawType: group.type).canBeUnpinned {
            guard let endpoint = group.testURL else { continue }
            for member in group.members {
                let resolved = group.memberResolvedNames[member] ?? member
                guard urls[resolved] == nil else { continue }
                urls[resolved] = endpoint
            }
        }
        for group in groups {
            for member in group.members {
                let resolved = group.memberResolvedNames[member] ?? member
                guard urls[resolved] == nil else { continue }
                urls[resolved] = group.testURL ?? fallback
            }
        }
        return urls
    }

    static func filter(_ groups: [ProxyGroup], query: String) -> [ProxyGroup] {
         
         
        let visible = groups.filter { !$0.hidden }
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return visible }
        return visible.compactMap { group in
            if group.name.localizedCaseInsensitiveContains(value) { return group }
            let members = group.members.filter { $0.localizedCaseInsensitiveContains(value) }
            guard !members.isEmpty else { return nil }
             
             
             
            let survivors = Set(members)
            return ProxyGroup(
                name: group.name,
                type: group.type,
                now: group.now,
                members: members,
                resolvedNow: group.resolvedNow,
                memberTypes: group.memberTypes.filter { survivors.contains($0.key) },
                memberGroupNames: group.memberGroupNames.intersection(survivors),
                memberResolvedNames: group.memberResolvedNames.filter {
                    survivors.contains($0.key)
                },
                memberPlaceholderTypes: group.memberPlaceholderTypes.filter {
                    survivors.contains($0.key)
                },
                configurationDetails: group.configurationDetails,
                hidden: group.hidden,
                testURL: group.testURL,
                iconURL: group.iconURL,
                emptyFallback: group.emptyFallback,
                fixed: group.fixed
            )
        }
    }

    static func nodeCatalog(
        _ data: Data?,
        protocolDetailsByNodeName: [String: ProxyProtocolDetails] = [:],
        providerCatalog: ProviderRuntimeCatalog = .empty,
        configuredOrder: ConfiguredProxyOrder = .none
    ) -> [ProxyNodeRecord] {
        nodeCatalog(
            proxies: proxies(in: data),
            protocolDetailsByNodeName: protocolDetailsByNodeName,
            providerCatalog: providerCatalog,
            configuredOrder: configuredOrder
        )
    }

    static func nodeCatalog(
        proxies: [String: Any]?,
        protocolDetailsByNodeName: [String: ProxyProtocolDetails] = [:],
        providerCatalog: ProviderRuntimeCatalog = .empty,
        configuredOrder: ConfiguredProxyOrder = .none
    ) -> [ProxyNodeRecord] {
        guard let proxies else { return [] }

        let groupNames = Set(proxies.compactMap { name, raw -> String? in
            guard let proxy = raw as? [String: Any], proxy["all"] is [String] else {
                return nil
            }
            return name
        })
        var memberships: [String: Set<String>] = [:]
        for (groupName, raw) in proxies {
            guard let proxy = raw as? [String: Any],
                  let members = proxy["all"] as? [String] else { continue }
            for member in members where !groupNames.contains(member) {
                memberships[member, default: []].insert(groupName)
            }
        }

        var records = proxies.compactMap { name, raw -> ProxyNodeRecord? in
            guard !groupNames.contains(name),
                  !BuiltinProxyName.all.contains(name),
                  let proxy = raw as? [String: Any] else { return nil }
            let history = proxy["history"] as? [[String: Any]]
            return ProxyNodeRecord(
                name: name,
                type: proxy["type"] as? String ?? "?",
                delay: history?.last?["delay"] as? Int,
                groupNames: (memberships[name] ?? []).sorted(),
                protocolDetails: protocolDetailsByNodeName[name]
            )
        }

         
         
         
         
         
        let known = Set(records.map(\.name))
         
         
         
         
        var runtimeNodeOrder: [String: Int] = [:]
        let orderedProviders = configuredOrder.sortedProviders(
            Array(providerCatalog.proxyProviders.keys)
        ) { $0 }
        for providerName in orderedProviders {
            guard let provider = providerCatalog.proxyProviders[providerName] else { continue }
            for proxy in provider.proxies where runtimeNodeOrder[proxy.name] == nil {
                runtimeNodeOrder[proxy.name] = runtimeNodeOrder.count
            }
        }
        for providerName in orderedProviders {
            guard let provider = providerCatalog.proxyProviders[providerName] else { continue }
            for proxy in provider.proxies where !known.contains(proxy.name)
                && !groupNames.contains(proxy.name) {
                records.append(
                    ProxyNodeRecord(
                        name: proxy.name,
                        type: proxy.type ?? "?",
                        delay: proxy.latestDelayMilliseconds
                            ?? (proxy.alive == false ? -1 : nil),
                        groupNames: (memberships[proxy.name] ?? []).sorted(),
                        protocolDetails: protocolDetailsByNodeName[proxy.name]
                    )
                )
            }
        }

         
         
         
         
        return configuredOrder.sortedNodes(records, runtimeOrder: runtimeNodeOrder) { $0.name }
    }
}

@MainActor
final class NodesModel: ObservableObject {
    @Published var groups: [ProxyGroup] = [] {
        didSet {
            ClashPerf.count("pub.nodes.groups")
            deriveGroupSelections()
        }
    }
     
     
     
     
     
     
     
     
     
     
     
     
    @Published var delays: [String: Int] = [:] {
        didSet { ClashPerf.count("pub.nodes.delays") }
    }
     
     
    private var measuredNames: Set<String> = []
     
    private var measuredProfile: String?
     
     
    private var latencyRunProfile: String?
     
     
    var defaultDelayTestURL: String { DelayTestSettings.effectiveURL() }
     
     
     
    private var runEndpoints: [String: String] = [:]
    private var runHealthServed = LockedNameSet()
     
     
     
    private var runRecordKeys: [String: String] = [:]
     
    private var runDecidingURLs: [String] = []

     
     
     
     
     
     
    private func fileRunResult(_ name: String, _ value: Int, into table: inout [String: Int]) {
        table[name] = value
         
         
         
         
         
        guard !runHealthServed.contains(name) else { return }
        let measured = urlRecordKey(ofRunResult: name)
        if let measured { table[measured] = value }
        for url in runDecidingURLs {
            let key = NodeInventory.latencyKey(name, readingURL: url)
            guard key != measured else { continue }
            if let standing = delays[key] { table[key] = standing }
        }
    }

     
     
     
    private func urlRecordKey(ofRunResult name: String) -> String? {
        guard let key = runRecordKeys[name], !runHealthServed.contains(name) else { return nil }
        return key
    }

    func delay(of name: String, in group: ProxyGroup) -> Int? {
        NodeInventory.memberDelay(name, in: group, delays: delays)
    }

    func routeDelay(from groupName: String) -> Int? {
        NodeInventory.routeDelay(from: groupName, groups: groups, delays: delays)
    }
    @Published private(set) var nodeCatalog: [ProxyNodeRecord] = [] {
        didSet {
            ClashPerf.count("pub.nodes.catalog")
            deriveRuntimeProxies()
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private(set) var nowByGroup: [String: String] = [:]
    private(set) var resolvedNowByGroup: [String: String] = [:]
     
    private(set) var fixedByGroup: [String: String] = [:]
    private(set) var runtimeProxies: [ProxiesOverviewModel.Proxy] = []

    private func deriveGroupSelections() {
         
         
        nowByGroup = Dictionary(
            groups.map { ($0.name, $0.now) },
            uniquingKeysWith: { first, _ in first }
        )
        resolvedNowByGroup = Self.groupTerminals(groups)
        fixedByGroup = Dictionary(
            groups.compactMap { group in group.fixed.map { (group.name, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

     
     
     
     
     
     
     
     
     
     
    nonisolated static func groupTerminals(_ groups: [ProxyGroup]) -> [String: String] {
        Dictionary(
            groups.compactMap { $0.isEmpty || $0.resolvedNow.isEmpty ? nil : ($0.name, $0.resolvedNow) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func deriveRuntimeProxies() {
        runtimeProxies = nodeCatalog.map {
            ProxiesOverviewModel.Proxy(name: $0.name, type: $0.type)
        }
    }
     
     
    private(set) var catalogRebuild: Task<Void, Never>?
    private var catalogGeneration: UInt64 = 0
     
     
     
     
     
     
    private var extendedMembers: [String: (list: String, members: [NodeMember], from: Int)] = [:]
     
    @Published private(set) var membersLoading: Set<String> = []
     
     
    private var searchedMembers: [String: [NodeMember]] = [:]
    private var searchedList: String?
     
     
    private var delaysSince: Int64 = 0
     
     
     
     
     
     
    private var loadedProviderNodes: [String: LoadedProviderNodes] = [:]

    struct LoadedProviderNodes {
        let list: String
        let updatedAt: Date?
        let total: Int
        let proxies: [ProxyProviderRuntime.Proxy]
    }
     
    @Published private(set) var providerNodesLoading: Set<String> = []

     
     
     
     
     
    var providerNodeTotal: Int? {
        if command?.isConnected == true {
            return runtimeProviderCatalog.proxyProviders.values
                .filter { !$0.isKernelInternal }
                .reduce(0) { $0 + $1.nodeCount }
        }
        return cachedProviderNodeCount
    }
    private var inventoryApplyGeneration: UInt64 = 0
    @Published var query = ""
    @Published private(set) var testingNames = Set<String>() {
        didSet { ClashPerf.count("pub.nodes.testing") }
    }
    @Published private(set) var currentGroupName: String? {
        didSet { ClashPerf.count("pub.nodes.current") }
    }
    @Published private(set) var unfoldedGroups = Set<String>() {
        didSet { ClashPerf.count("pub.nodes.unfolded") }
    }
     
     
     
     
     
     
     
    private(set) var foldStateRecorded = false
    var readerFoldedAllGroups: Bool { foldStateRecorded && unfoldedGroups.isEmpty }
    @Published private(set) var isSwitchingProxy = false {
        didSet { ClashPerf.count("pub.nodes.switching") }
    }
     
     
     
     
     
    @Published private(set) var routeGeneration = 0

    func noteRouteChanged() {
        routeGeneration &+= 1
    }
    @Published private(set) var providerNamesByProxy: [String: String] = [:]
     
     
     
    @Published private(set) var cachedProviderNodeCount: Int?
    @Published private(set) var runtimeProviderCatalog = ProviderRuntimeCatalog.empty {
        didSet { ClashPerf.count("pub.nodes.providers") }
    }
     
     
    private var appliedProviderCatalog = ProviderRuntimeCatalog.empty
     
     
    private var offlineProviderCatalog = ProviderRuntimeCatalog.empty
     
     
     
     
    private var inventoryProviderCatalog: ProviderRuntimeCatalog {
        isRuntimeAvailable ? runtimeProviderCatalog : offlineProviderCatalog
    }
     
    private var appliedProxiesData: Data?
    private var appliedProtocolDetails: [String: ProxyProtocolDetails] = [:]
    private var appliedGroupDetails: [String: ProxyGroupConfigurationDetails] = [:]
     
     
     
    @Published private(set) var actionRefusals: [String: String] = [:]
    @Published private(set) var isRuntimeAvailable = false
    @Published private(set) var trafficUsageByGroupName: [String: ProxyTrafficUsage] = [:] {
        didSet { ClashPerf.count("pub.nodes.traffic") }
    }
    @Published private(set) var isTestingLatency = false
     
     
     
     
     
     
     
     
     
    static var postSweepSelectionSyncNanoseconds: UInt64 = 11_000_000_000
    private var postSweepSelectionSync: Task<Void, Never>?
    @Published private(set) var latencyCompletedCount = 0
    @Published private(set) var latencyTotalCount = 0

    var testing: Bool { isTestingLatency }

    private weak var command: NodesCommanding?
     
    private var unfixingGroups: Set<String> = []
     
     
     
    var isConnected: Bool { command?.isConnected ?? false }
    private let preferences: NodeProfilePreferencesStore?
    private let protocolDetailsLoader: () -> [String: ProxyProtocolDetails]
    private let groupConfigurationDetailsLoader: () -> [String: ProxyGroupConfigurationDetails]
    private let configuredOrderLoader: () -> ConfiguredProxyOrder
    private let trafficUsageLoader: () -> [String: ProxyTrafficUsage]
    private let offlineCatalogLoader: () -> OfflineProxyCatalogSnapshot?
     
     
     
     
    @Published private(set) var offlineGroupsProfileID: String?
    private let runtimeIdentityLoader: () -> NodesRuntimeIdentity?
    private var protocolDetailsByNodeName: [String: ProxyProtocolDetails] = [:]
    private var locallyEditedProtocolDetails: [String: ProxyProtocolDetails] = [:]
    private var groupConfigurationDetailsByName: [String: ProxyGroupConfigurationDetails] = [:]
     
     
    private var configuredOrder: ConfiguredProxyOrder = .none
     
     
    private var lastRuntimeInventory: Data?
     
    private var lastOfflineYAML: String?
    private var inventoryProjectionGeneration: UInt64 = 0
    private var inventoryProjectionTasks: [UInt64: Task<Void, Never>] = [:]
     
     
    private(set) var inventoryApplications = 0
    private var observedRuntimeIdentity: NodesRuntimeIdentity?
    private var restoredRuntimeKey: String?
    private var providerCatalogGeneration: UInt64 = 0
    private var providerArrivalTask: Task<Void, Never>?
    private let providerCatalogRetryDelayNanoseconds: UInt64
    private var latencyRunID: UInt64 = 0
    private var latencyTask: Task<LatencyProbeSummary, Never>?
     
    private var subscriptionHealth: SubscriptionHealthRuns?
    private var latencyCancellation: LatencyProbeCancellation?
    private let shouldCloseConnectionsOnSwitch: () -> Bool

    init(
        preferences: NodeProfilePreferencesStore? = .live(),
        protocolDetailsLoader: @escaping () -> [String: ProxyProtocolDetails] = {
            ProxyConfigurationInspector.activeDetails()
        },
        groupConfigurationDetailsLoader: @escaping () -> [String: ProxyGroupConfigurationDetails] = {
            ProxyGroupConfigurationInspector.activeDetails()
        },
        configuredOrderLoader: @escaping () -> ConfiguredProxyOrder = {
            ProxyGroupConfigurationInspector.activeConfiguredOrder()
        },
        trafficUsageLoader: @escaping () -> [String: ProxyTrafficUsage] = {
            ProxyTrafficUsageInspector.activeSummaries()
        },
        offlineCatalogLoader: @escaping () -> OfflineProxyCatalogSnapshot? = {
            OfflineProxyCatalogLoader.load()
        },
        runtimeIdentityLoader: @escaping () -> NodesRuntimeIdentity? = {
            NodesRuntimeIdentity.load()
        },
        shouldCloseConnectionsOnSwitch: @escaping () -> Bool = {
            NodeSwitchSettings.autoCloseOnSwitch()
        },
        runtimeRestartGrace: TimeInterval = 20,
        providerCatalogRetryDelayNanoseconds: UInt64 = 2_000_000_000,
        memorySentryNow: @escaping @Sendable () -> UInt64 = {
            DispatchTime.now().uptimeNanoseconds
        },
        memorySentrySleep: @escaping @Sendable (UInt64) async throws -> Void = {
            try await Task.sleep(nanoseconds: $0)
        }
    ) {
        self.preferences = preferences
        self.protocolDetailsLoader = protocolDetailsLoader
        self.groupConfigurationDetailsLoader = groupConfigurationDetailsLoader
        self.configuredOrderLoader = configuredOrderLoader
        self.trafficUsageLoader = trafficUsageLoader
        self.offlineCatalogLoader = offlineCatalogLoader
        self.runtimeIdentityLoader = runtimeIdentityLoader
        self.shouldCloseConnectionsOnSwitch =
            shouldCloseConnectionsOnSwitch
        self.runtimeRestartGrace = runtimeRestartGrace
        self.providerCatalogRetryDelayNanoseconds = providerCatalogRetryDelayNanoseconds
        self.memorySentryNow = memorySentryNow
        self.memorySentrySleep = memorySentrySleep
    }

     
     
     
     
    private let runtimeRestartGrace: TimeInterval
    private let memorySentryNow: @Sendable () -> UInt64
    private let memorySentrySleep: @Sendable (UInt64) async throws -> Void
     
     
    private var runtimeRestartRequestedAt: Date?

    func bind(command: NodesCommanding) {
        self.command = command
         
        polledRevision = nil
        if observedRuntimeIdentity == nil {
            observedRuntimeIdentity = currentRuntimeIdentity()
        }
        providerCatalogGeneration &+= 1
        let providerToken = providerCatalogGeneration
        providerNamesByProxy = [:]
        loadMeasuredDelays()
        let hadInventory = !groups.isEmpty
        ClashPerf.measure("nodes.reloadInventory") {
            reloadInventory(command: command)
        }
        if !hadInventory,
           unfoldedGroups.isEmpty,
           preferences?.load()?.unfoldedGroups == nil {
            unfoldedGroups = Set(groups.map(\.name))
        }
         
         
         
         
         
         
        bindSettle = Task { [weak self, weak command] in
            guard let self, let command else { return }
            await self.restoreActiveProfileSelectionIfNeeded(command: command)
            await self.loadProviderSources(command: command, token: providerToken)
        }
    }

     
     
     
    private func loadMeasuredDelays() {
        guard let store = preferences?.latencyResults else { return }
        let profile = preferences?.activeProfileKey()
        guard profile != measuredProfile || delays.isEmpty else { return }
        measuredProfile = profile
        delays = profile.map { store.readings(profile: $0) } ?? [:]
        measuredNames = Set(delays.keys)
    }

     
     
    private func recordMeasured(_ results: [String: Int]) {
        guard !results.isEmpty else { return }
         
         
         
        let readersOwn = results.filter { !NodeInventory.isURLRecordKey($0.key) }
        if let profile = latencyRunProfile ?? measuredProfile {
            if !readersOwn.isEmpty { preferences?.latencyResults?.record(readersOwn, profile: profile) }
            guard profile == measuredProfile else { return }
        }
        var merged = delays
        for (name, delay) in results { merged[name] = delay }
        for name in readersOwn.keys where runHealthServed.contains(name) {
            for url in runDecidingURLs { merged[NodeInventory.latencyKey(name, readingURL: url)] = nil }
        }
        delays = merged
        measuredNames.formUnion(readersOwn.keys)
    }

     
     
    private var bindSettle: Task<Void, Never>?

    func refresh() async {
        if let settle = bindSettle {
            bindSettle = nil
            await settle.value
        }
        guard let command else {
             
             
             
             
             
             
             
             
            ClashLogStore.shared.append(
                "proxies refresh ignored: no command \("channel") bound",
                stream: .app,
                level: .warning
            )
             
             
             
            FrameLogFile.append("proxies refresh ignored: no command \("channel")")
            return
        }
        if await transitionRuntimeIfNeeded(command: command) {
            return
        }
        if !command.isConnected {
            await cancelLatencyTests(reason: .disconnected)
             
             
             
             
             
             
             
            restoredRuntimeKey = nil
        }
        providerCatalogGeneration &+= 1
        let providerToken = providerCatalogGeneration
        if command.isConnected {
             
             
            OfflineProxyCatalogLoader.releaseForConnection()
            await command.refreshMetadata()
        }
         
         
         
         
         
         
         
        await reloadInventoryOffMain(command: command)
        await restoreActiveProfileSelectionIfNeeded(command: command)
        await loadProviderSources(command: command, token: providerToken)
         
         
         
         
        FrameLogFile.append(
            "proxies refresh done connected=\(command.isConnected) groups=\(groups.count)"
        )
    }

    func select(group: String, name: String) async {
        guard let command, !isSwitchingProxy,
              let targetGroup = groups.first(where: { $0.name == group }),
              ProxyGroupControlKind(rawType: targetGroup.type).acceptsMemberChoice,
              targetGroup.members.contains(name) else { return }
        if command.isConnected {
            isSwitchingProxy = true
            defer { isSwitchingProxy = false }
            let confirmed = await command.select(
                group: group,
                name: name
            )
             
             
             
             
            if confirmed { noteKernelAcceptedSelection(group: group, name: name) }
            await applyInventoryOffMain(command.proxiesData, reason: .selectionReadback)
             
             
             
             
             
            guard confirmed,
                  groups.first(where: { $0.name == group })?
                    .holdsSelection(name) == true else {
                 
                 
                 
                refuse(group: group, because: command.lastCommandError,
                       otherwise: "The running proxy group did not confirm the selected route.")
                return
            }

            if command.mode.trimmingCharacters(
                in: .whitespacesAndNewlines
            ).lowercased() == "global",
               group != GlobalProxySelectionPolicy.groupName,
               let global = groups.first(where: {
                    $0.name == GlobalProxySelectionPolicy.groupName
               }),
               !global.holdsSelection(group),
               global.members.contains(group),
               GlobalProxySelectionPolicy.isSafeManualGroup(
                    group,
                    groups: groups
               ) {
                let retargeted = await command.select(
                    group: global.name,
                    name: group
                )
                if retargeted { noteKernelAcceptedSelection(group: global.name, name: group) }
                await command.refreshMetadata()
                await applyInventoryOffMain(command.proxiesData, reason: .selectionReadback)
                guard retargeted,
                      groups.first(where: {
                          $0.name == GlobalProxySelectionPolicy.groupName
                      })?.holdsSelection(group) == true else {
                    refuse(group: group, because: command.lastCommandError,
                           otherwise: "The running proxy group did not confirm the selected route.")
                    return
                }
            }
            actionRefusals[group] = nil
        }
        preferences?.saveSelection(group: group, proxy: name)
        noteRouteChanged()
        ClashLogStore.shared.append(
            "node switched  group=\(group) -> \(name)",
            stream: .app
        )
        if GlobalProxySelectionPolicy.remembers(group: group) { currentGroupName = group }
        if !command.isConnected {
            applyOfflineSelection(group: group, name: name)
        }
        if command.isConnected, shouldCloseConnectionsOnSwitch() {
            await command.closeConnectionsAfterProxySelection()
        }
    }

     
     
     
     
    @discardableResult
    func ensureGlobalProxySelection() async -> Bool {
        guard let command, command.isConnected else { return false }
        await command.refreshMetadata()
        await applyInventoryOffMain(command.proxiesData, reason: .selectionReadback)

        guard GlobalProxySelectionPolicy.refusal(groups: groups) == nil,
              let global = groups.first(where: {
                  $0.name == GlobalProxySelectionPolicy.groupName
              }) else {
            return false
        }

         
         
         
         
        if let target = GlobalProxySelectionPolicy.target(
            groups: groups,
            preferredGroupName: currentGroupName
        ), global.now != target {
            await select(group: global.name, name: target)
        }
         
         
         
         
         
         
         
        return GlobalProxySelectionPolicy.isProxySelected(groups: groups)
    }

     
     
     
     
     
     
     
     
     
     
    func unfix(group: String) async {
         
         
         
         
         
         
         
         
         
         
        guard let command, command.isConnected else {
             
             
             
             
             
            let forgotten = preferences?.clearSelection(group: group) ?? false
             
             
             
            if forgotten { actionRefusals[group] = nil }
            ClashLogStore.shared.append(
                "unfix  tunnel down  group=\(group)  profile pin forgotten=\(forgotten)",
                stream: .app, level: .info
            )
            return
        }
        guard let target = groups.first(where: { $0.name == group }) else {
            ClashLogStore.shared.append("unfix refused  no such group=\(group)", stream: .app, level: .warning)
            refuse(group: group, because: "This group is no longer in the running configuration.")
            return
        }
        guard ProxyGroupControlKind(rawType: target.type).canBeUnpinned else {
            ClashLogStore.shared.append("unfix refused  group=\(group) type=\(target.type) cannot be unpinned", stream: .app, level: .warning)
            refuse(group: group, because: "A \(target.type) group has no pin to release.")
            return
        }
         
         
         
        guard !unfixingGroups.contains(group) else { return }
        unfixingGroups.insert(group)
        defer { unfixingGroups.remove(group) }
         
         
         
         
         
         
         
         
         
         
         
         
        if isTestingLatency {
            ClashLogStore.shared.append(
                "unfix  group=\(group)  sweep in progress, releasing without re-measuring",
                stream: .app, level: .info
            )
        } else {
            ClashLogStore.shared.append(
                "unfix  group=\(group)  re-measuring against \(target.testURL ?? "the app endpoint") before release",
                stream: .app, level: .info
            )
            await test(group: target)
        }
        if let preferences, let pinned = preferences.load()?.selectedMap[group] {
            guard preferences.clearSelection(group: group) else {
                 
                 
                 
                ClashLogStore.shared.append(
                    "unfix refused  group=\(group)  the profile's pin could not be cleared",
                    stream: .app, level: .warning
                )
                refuse(group: group, because: "The profile's saved selection could not be cleared.")
                return
            }
            guard await command.unfix(group: group) else {
                ClashLogStore.shared.append(
                    "unfix refused by core  group=\(group)  reason=\(command.lastCommandError)",
                    stream: .app, level: .warning
                )
                refuse(group: group, because: command.lastCommandError)
                if !preferences.restoreSelection(group: group, proxy: pinned) {
                     
                     
                     
                     
                     
                    await applyInventoryOffMain(command.proxiesData, reason: .selectionReadback)
                }
                return
            }
        } else {
            guard await command.unfix(group: group) else {
                ClashLogStore.shared.append(
                    "unfix refused by core  group=\(group)  reason=\(command.lastCommandError)",
                    stream: .app, level: .warning
                )
                refuse(group: group, because: command.lastCommandError)
                return
            }
        }
        actionRefusals[group] = nil
         
         
        ClashLogStore.shared.append("unfix  group=\(group)  released", stream: .app)
        await applyInventoryOffMain(command.proxiesData, reason: .selectionReadback)
    }

     
     
     
    func noteOfflinePick(group: String, refusal: String?) {
        guard let refusal else { actionRefusals[group] = nil; return }
        refuse(group: group, because: refusal,
               otherwise: "The running proxy group did not confirm the selected route.")
    }

     
     
     
     
    private func refuse(
        group: String,
        because reason: String,
        otherwise silent: String = "The core did not release this group's pin."
    ) {
        let sentence = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        actionRefusals[group] = sentence.isEmpty ? silent : sentence
    }

     
     
     
     
     
     
     
     
     
     
     
     
    private var readerFoldBase: Set<String> {
        !foldStateRecorded || unfoldedGroups.count > 1 ? [] : unfoldedGroups
    }

     
     
     
     
    nonisolated static func storedFoldStateIsTheReaders(_ stored: Set<String>?) -> Bool {
        stored.map { $0.count <= 1 } ?? false
    }

    func setExpanded(_ expanded: Bool, group: String) {
        var next = readerFoldBase
        if expanded {
            next.insert(group)
            currentGroupName = group
        } else {
            next.remove(group)
        }
        foldStateRecorded = true
        unfoldedGroups = next
        preferences?.savePresentation(
            currentGroup: currentGroupName,
            unfoldedGroups: unfoldedGroups
        )
    }

     
     
     
     
     
     
     
     
     
     
    func setExpanded(_ expanded: Bool, groups names: [String]) {
        guard !names.isEmpty else { return }
        var next = readerFoldBase
        if expanded {
            next.formUnion(names)
        } else {
            next.subtract(names)
        }
        foldStateRecorded = true
        unfoldedGroups = next
        preferences?.savePresentation(
            currentGroup: currentGroupName,
            unfoldedGroups: unfoldedGroups
        )
    }

    func setCurrentGroup(_ group: String) {
        guard groups.contains(where: { $0.name == group }) else { return }
         
         
         
         
         
         
         
         
        guard GlobalProxySelectionPolicy.remembers(group: group),
              currentGroupName != group else { return }
        currentGroupName = group
        preferences?.savePresentation(
            currentGroup: group,
            unfoldedGroups: unfoldedGroups
        )
    }

    func test(_ name: String, inGroup groupName: String? = nil) async {
         
         
        testAllSession &+= 1
         
         
        let target = NodeInventory.latencyTarget(of: name, inGroup: groupName, groups: groups)
        await runLatencyTest(
            plan: makeLatencyPlan(
                groups: [ProxyGroup(name: "requested", type: "", now: target.name, members: [target.name])],
                visibleGroupNames: ["requested"]
            ),
            endpoint: target.endpoint
        )
    }

     
     
     
     
     
     
     
     
     
     
    func test(group: ProxyGroup) async {
        testAllSession &+= 1
        let session = testAllSession
         
         
        await loadRemainingMembers(ofEvery: [group.name])
        guard session == testAllSession else { return }
        let group = groups.first { $0.name == group.name } ?? group
        await runLatencyTest(
            plan: makeLatencyPlan(groups: [group], visibleGroupNames: [group.name]),
             
             
             
             
            endpoint: NodeInventory.probeURL(of: group)
        )
    }



     
     
     
    func testAll() async {
        testAllSession &+= 1
        let session = testAllSession
        await loadRemainingMembers(ofEvery: groups.filter { !$0.hasEveryMember }.map(\.name))
         
         
        guard session == testAllSession else { return }
        await runLatencyTest(
            plan: makeLatencyPlan(
                groups: groups,
                visibleGroupNames: currentGroupName.map { [$0] } ?? []
            )
        )
    }

     
     
     
    private var testAllSession: UInt64 = 0

    func cancelLatencyTests(reason: LatencyProbeCancellationReason) async {
        if reason == .backgrounded { healthCheckFollowPaused = true }
        postSweepSelectionSync?.cancel()
        postSweepSelectionSync = nil
        await cancelLatencyTests(reason: reason, expectedOperation: nil)
    }

    private func cancelLatencyTests(
        reason: LatencyProbeCancellationReason,
        expectedOperation: MemorySentryOperation?
    ) async {
        if let expectedOperation,
           !isCurrentMemorySentry(expectedOperation) { return }
        if isTestingLatency {
            ClashLogStore.shared.append(
                "sweep interrupted  reason=\(reason)  completed=\(sweepCompleted)/\(latencyTotalCount)",
                stream: .app,
                level: .warning
            )
        }
        testAllSession &+= 1
        latencyRunID &+= 1
        let cancellationRunID = latencyRunID
        func stillOwnsCancellation() -> Bool {
            guard let expectedOperation else { return true }
             
             
             
            return latencyRunID == cancellationRunID
                && latencyCancellation === expectedOperation.cancellation
        }
        let ownedCancellation = expectedOperation?.cancellation ?? latencyCancellation
        await ownedCancellation?.cancel(reason: reason)
        guard stillOwnsCancellation() else { return }
        latencyTask?.cancel()
         
         
         
         
        if let health = subscriptionHealth {
            subscriptionHealth = nil
            await health.cancel()
        }
        guard stillOwnsCancellation() else { return }
         
         
        let completed = sweepCompleted
        let total = latencyTotalCount
        let settledDelays = sweepDelays
        commitSweepToPublished(completed: completed, total: total)
        sendSweepBatch(
                results: settledDelays, testing: [],
                completed: completed, total: total, finished: true
            )
    }

     
     
     
    func applyNodeEdit(name: String, configurationJSON: String) {
        guard let mapping = ProxyProtocolCatalog.mapping(from: configurationJSON),
              let details = ProxyProtocolCatalog.details(for: mapping) else { return }
        locallyEditedProtocolDetails[name] = details
        protocolDetailsByNodeName[name] = details
        nodeCatalog = nodeCatalog.map { record in
            guard record.name == name else { return record }
            return ProxyNodeRecord(
                name: record.name,
                type: record.type,
                delay: record.delay,
                groupNames: record.groupNames,
                protocolDetails: details
            )
        }
    }

    func makeLatencyPlan(
        groups: [ProxyGroup],
        visibleGroupNames: [String]
    ) -> LatencyProbePlan {
         
         
         
         
        var probeGroups = groups.map { group in
            LatencyProbeGroup(
                name: group.name,
                members: group.members.map {
                    group.memberResolvedNames[$0] ?? $0
                },
                selectedName: group.members.contains(group.now)
                    ? (group.memberResolvedNames[group.now] ?? group.now)
                    : nil
            )
        }
         
         
         
         
         
         
         
         
         
         
         
         
        let members = probeGroups.flatMap(\.members)
         
         
         
        let excludedNames = Set(members.filter {
            LatencyProbeNamePolicy.probeExcludedNames.contains($0)
        })
        let freshnessByName = Dictionary(uniqueKeysWithValues: Set(members).map { name in
            let freshness: LatencyProbeFreshness
            if let delay = delays[name] {
                freshness = delay > 0 ? .fresh : .failed
            } else if sessionProbeFailures.contains(name) {
                freshness = .failed
            } else {
                freshness = .neverTested
            }
            return (name, freshness)
        })
        return LatencyProbePlan(
            groups: probeGroups,
            visibleGroupNames: visibleGroupNames,
            freshnessByName: freshnessByName,
            excludedNames: excludedNames
        )
    }

    private struct MemorySentryOperation: Sendable {
        let cancellation: LatencyProbeCancellation
        let runID: UInt64
    }

    private func isCurrentMemorySentry(_ operation: MemorySentryOperation) -> Bool {
        !Task.isCancelled && latencyRunID == operation.runID
            && latencyCancellation === operation.cancellation
    }

    private func readMemorySentryFootprint(
        command: NodesCommanding, operation: MemorySentryOperation
    ) async -> Int64? {
        guard isCurrentMemorySentry(operation) else { return nil }
        let value = await command.extensionFootprintBytes()
         
         
        guard isCurrentMemorySentry(operation) else { return nil }
        return value
    }

     
     
    func startMemorySentry(cancellation: LatencyProbeCancellation) -> Task<Void, Never> {
        latencyCancellation = cancellation
        let operation = MemorySentryOperation(cancellation: cancellation, runID: latencyRunID)
        let clockNow = memorySentryNow
        let sentrySleep = memorySentrySleep
        return Task { [weak self] in
             
             
             
             
             
             
             
             
            let pauseAtBytes: Int64 = 42_500_000
            let resumeAtBytes: Int64 = 41_000_000
            let maxPauseNanoseconds: UInt64 = 20_000_000_000
            var pauses = 0
            var blindTicks = 0
            while !Task.isCancelled {
                do {
                    try await sentrySleep(1_000_000_000)
                } catch { return }
                guard !Task.isCancelled else { return }
                guard let self else { return }
                guard let command = await MainActor.run(body: { self.command }) else { continue }
                guard let footprint = await self.readMemorySentryFootprint(
                    command: command, operation: operation
                ) else { return }
                if footprint <= 0 {
                     
                     
                     
                    blindTicks += 1
                    if blindTicks == 10 {
                        ClashLogStore.shared.append(
                            "sweep sentry blind  no footprint after \(blindTicks)s; pause/resume disabled for this run",
                            stream: .app, level: .warning)
                    }
                    continue
                }
                guard footprint >= pauseAtBytes else { continue }

                pauses += 1
                let progress = await MainActor.run {
                    "\(self.sweepCompleted)/\(self.latencyTotalCount)"
                }
                guard self.isCurrentMemorySentry(operation) else { return }
                await cancellation.pause()
                guard self.isCurrentMemorySentry(operation) else { return }
                ClashLogStore.shared.append(
                    "sweep paused  reason=memoryPressure  pause=#\(pauses)  completed=\(progress)  footprint=\(footprint)",
                    stream: .app, level: .warning)
                let pausedAt = clockNow()
                var recovered = false
                while self.isCurrentMemorySentry(operation),
                      clockNow() &- pausedAt < maxPauseNanoseconds {
                    do {
                        try await sentrySleep(1_000_000_000)
                    } catch { return }
                    guard !Task.isCancelled else { return }
                    guard let now = await self.readMemorySentryFootprint(
                        command: command, operation: operation
                    ) else { return }
                    if now > 0, now <= resumeAtBytes {
                        recovered = true
                        ClashLogStore.shared.append(
                            "sweep resumed  after=\((clockNow() &- pausedAt) / 1_000_000_000)s  pause=#\(pauses)  footprint=\(now)",
                            stream: .app, level: .info)
                        break
                    }
                }
                guard self.isCurrentMemorySentry(operation) else { return }
                if recovered {
                    await cancellation.resume()
                } else {
                    ClashLogStore.shared.append(
                        "sweep interrupted  reason=memoryPressure  pause=#\(pauses) never recovered in 20s",
                        stream: .app, level: .warning)
                    await self.cancelLatencyTests(
                        reason: .memoryPressure, expectedOperation: operation
                    )
                    return
                }
            }
        }
    }

     
     
    private func runLatencyTest(
        plan: LatencyProbePlan,
        endpoint: String? = nil
    ) async {
        guard let command, command.isConnected else { return }

        latencyRunID &+= 1
        let runID = latencyRunID
         
         
        postSweepSelectionSync?.cancel()
        postSweepSelectionSync = nil
        let previousTask = latencyTask
        await latencyCancellation?.cancel(reason: .superseded)
        previousTask?.cancel()
        if let previousTask {
             
             
             
             
            let yielded = await withTaskGroup(of: Bool.self) { group in
                group.addTask { _ = await previousTask.value; return true }
                group.addTask {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    return false
                }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            if !yielded {
                let verdict = "unresponsive"
                ClashLogStore.shared.append(
                    "sweep supersede  previous run \(verdict), proceeding",
                    stream: .app, level: .warning)
            }
        }
        guard runID == latencyRunID, command.isConnected else {
            ClashLogStore.shared.append(
                "sweep refused  connected=\(command.isConnected)  reopening=\(command.isReopeningControlSession)",
                stream: .app, level: .warning)
            return
        }
        if command.isReopeningControlSession {
             
             
             
            let why = "reopening"
            ClashLogStore.shared.append(
                "sweep refused  control session \(why)",
                stream: .app, level: .warning)
            return
        }

        let orderedNames = LatencyProbeScheduler.orderedNames(for: plan)
        let totalCount = orderedNames.count
        guard totalCount > 0 else { return }
        logSweepCoverage(planned: orderedNames)
        let cancellation = LatencyProbeCancellation()
         
         
         
         
         
         
         
         
         
         
         
        let memorySentry = startMemorySentry(cancellation: cancellation)
        defer { memorySentry.cancel() }
        latencyCompletedCount = 0
        latencyTotalCount = totalCount
        isTestingLatency = true
        testingNames.removeAll()
         
         
         
         
         
        latencyRunProfile = measuredProfile
        sweepDelays = [:]
        sweepTesting = []
        sweepCompleted = 0
         
         
        failureReasons = [:]
        let testURL = DelayTestSettings.effectiveURL()
        let urlsByMember = NodeInventory.probeURLsByMember(
            in: groups,
            fallback: testURL
        )
        runHealthServed = LockedNameSet()
        runEndpoints = Dictionary(uniqueKeysWithValues: orderedNames.map {
            ($0, endpoint ?? urlsByMember[$0] ?? testURL)
        })
        let decidingURLs = NodeInventory.readingURLs(of: groups)
        runDecidingURLs = Array(decidingURLs)
        runRecordKeys = decidingURLs.isEmpty ? [:] : runEndpoints.reduce(into: [:]) { keys, entry in
            if decidingURLs.contains(entry.value) {
                keys[entry.key] = NodeInventory.latencyKey(entry.key, readingURL: entry.value)
            }
        }
        let healthServed = runHealthServed
         
         
         
         
         
        var latencyPolicy = Self.activeLatencyPolicy
         
         
         
         
         
         
        latencyPolicy.deferredRetryWindowNanoseconds = .max
         
         
         
         
         
         
        announceLatencyRoster(Set(orderedNames), total: totalCount)
        let subscriptionHealth = SubscriptionHealthRuns(
            providerNamesByProxy: providerNamesByProxy,
             
             
            usesBulkHealth: endpoint == nil && latencyPolicy.usesBulkProviderHealth(
                for: totalCount,
                 
                 
                 
                 
                 
                 
                 
                catalogCount: groups.reduce(0) { $0 + $1.members.count }
                    + providerNamesByProxy.count
            )
        )
        self.subscriptionHealth = subscriptionHealth
        let task = Task { [weak self] in
            await LatencyProbeScheduler.run(
                runID: runID,
                plan: plan,
                policy: latencyPolicy,
                cancellation: cancellation,
                onEvent: { [weak self] event in
                    await self?.applyLatencyEvent(event)
                },
                probe: { name in
                     
                     
                     
                    final class Phase: @unchecked Sendable {
                        private let lock = NSLock()
                        private var value = "health-wait"
                        func set(_ v: String) { lock.lock(); value = v; lock.unlock() }
                        func get() -> String { lock.lock(); defer { lock.unlock() }; return value }
                    }
                    let phase = Phase()
                    let outcome: LatencyProbeOutcome? = await withTaskGroup(
                        of: LatencyProbeOutcome?.self
                    ) { group in
                        group.addTask {
                            if let measured = await subscriptionHealth.delay(
                                for: name, command: command
                            ) {
                                healthServed.insert(name)
                                return measured > 0
                                    ? .success(milliseconds: measured) : .failure
                            }
                            phase.set("urltest")
                            let probe = await command.nodesTestDelayWithReason(
                                name: name,
                                url: endpoint ?? urlsByMember[name] ?? testURL
                            )
                            if probe.delay == -2 { return .deferred }
                            if probe.delay <= 0 {
                                 
                                 
                                 
                                await MainActor.run { [weak self] in
                                     
                                     
                                     
                                    guard let self, runID == self.latencyRunID else { return }
                                    self.recordFailureReason(
                                        name, category: probe.category
                                    )
                                }
                                return .failure
                            }
                            return .success(milliseconds: probe.delay)
                        }
                        group.addTask {
                            try? await Task.sleep(nanoseconds: 20_000_000_000)
                            return nil
                        }
                        let first = await group.next() ?? nil
                        group.cancelAll()
                        return first
                    }
                    guard let outcome else {
                        ClashLogStore.shared.append(
                            "probe stalled  name=\(name)  phase=\(phase.get())",
                            stream: .app, level: .warning)
                        return .failure
                    }
                    return outcome
                }
            )
        }
        latencyTask = task
        let heartbeat = Task { @MainActor [weak self] in
            var beat = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                guard let self, self.isTestingLatency else { break }
                beat += 1
                ClashLogStore.shared.append(
                    "sweep heartbeat  #\(beat)  completed=\(self.sweepCompleted)/\(self.latencyTotalCount)  testing=\(self.sweepTesting.count)",
                    stream: .app, level: .info)
            }
        }
        _ = await task.value
        heartbeat.cancel()
         
         
         
         
         
        if !healthServed.isEmpty, command.isConnected {
            await loadProviderSources(command: command, token: providerCatalogGeneration)
        }
        guard runID == latencyRunID else { return }
        let ok = sweepDelays.values.filter { $0 > 0 }.count
        ClashLogStore.shared.append(
             
             
             
             
             
            "sweep done  planned=\(totalCount)  measured=\(sweepDelays.count)  ok=\(ok)  causes=\(failureCauseSummary())",
            stream: .app, level: ok == 0 ? .warning : .info)
        latencyTask = nil
        latencyCancellation = nil
    }

     
     
     
     
     
     
     
    private var pendingLatency: [String: LatencyProbeEvent] = [:]
    private var pendingStartedNames: Set<String> = []
    private var latencyFlushScheduled = false
     
     
     
     
     
     
     
     
     
    let latencySweepConduit = PassthroughSubject<LatencySweepBatch, Never>()
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func sendSweepBatch(
        results: [String: Int], testing: Set<String>,
        completed: Int, total: Int, finished: Bool
    ) {
        let terminals = NodeInventory.groupTerminalKeys(groups: groups, defaultURL: defaultDelayTestURL)
        latencySweepConduit.send(LatencySweepBatch(
            results: results, testing: testing, groupTerminals: resolvedNowByGroup,
            groupTerminalKeys: terminals,
            completed: completed, total: total, finished: finished
        ))
    }

    func announceLatencyRoster(_ roster: Set<String>, total: Int) {
        guard !roster.isEmpty else { return }
        sweepTesting = roster
        sendSweepBatch(
                results: [:], testing: roster,
                completed: 0, total: total, finished: false
            )
    }

    func announceLatencyRosterForTesting(_ roster: Set<String>, total: Int) {
        isTestingLatency = true
        latencyTotalCount = total
        announceLatencyRoster(roster, total: total)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @Published private(set) var failureReasons: [String: String] = [:]

     
     
    func failureCauseSummary() -> String {
        guard !failureReasons.isEmpty else { return "-" }
        let tally = failureReasons.values.reduce(into: [String: Int]()) {
            $0[$1, default: 0] += 1
        }
        return tally
            .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key)×\($0.value)" }
            .joined(separator: " ")
    }

    func failureReason(for name: String) -> String? {
        failureReasons[name]
    }

    func recordFailureReason(_ name: String, category: String) {
        guard !category.isEmpty, category != "admission-deferred" else { return }
        failureReasons[name] = category
    }

    func recordFailureReasonForTesting(_ name: String, category: String) {
        recordFailureReason(name, category: category)
    }

    private var sweepDelays: [String: Int] = [:]
     
     
     
     
     
     
     
     
     
     
    static var activeLatencyPolicy: LatencyProbePolicy {
        var policy = LatencyProbePolicy.currentPlatform


        return policy
    }



    var sessionProbeFailures: Set<String> = []
    private var sweepTesting: Set<String> = []
    private var sweepCompleted = 0
     
     
    static var latencyFlushNanoseconds: UInt64 = 250_000_000



    private func applyLatencyEvent(_ event: LatencyProbeEvent) {
        switch event {
        case .started(let started):
            guard started.runID == latencyRunID else { return }
            pendingStartedNames.insert(started.name)
            pendingLatency["started:\(started.name)"] = event
            scheduleLatencyFlush()
        case .result(let result):
            guard result.runID == latencyRunID else { return }
            pendingStartedNames.remove(result.name)
            pendingLatency["result:\(result.name)"] = event
            scheduleLatencyFlush()
        case .cancelled(let cancelled):
            guard cancelled.runID == latencyRunID else { return }
            pendingStartedNames.remove(cancelled.name)
            pendingLatency["cancelled:\(cancelled.name)"] = event
            scheduleLatencyFlush()
        case .finished:
             
            pendingLatency["finished"] = event
            flushLatencyEvents()
        }
    }

    private func scheduleLatencyFlush() {
        guard !latencyFlushScheduled else { return }
        latencyFlushScheduled = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.latencyFlushNanoseconds)
            self?.flushLatencyEvents()
        }
    }

     
     
     
     
     
     
    var latencyPublishQuietUntil: Date?

    private func flushLatencyEvents() {
        latencyFlushScheduled = false
        guard !pendingLatency.isEmpty else { return }
        if let until = latencyPublishQuietUntil {
            if Date() < until {
                scheduleLatencyFlush()
                return
            }
            latencyPublishQuietUntil = nil
        }
        let batch = pendingLatency
        pendingLatency.removeAll()
        let flushSpan = ClashPerf.signposter.beginInterval(
            "latency.flush", id: ClashPerf.signposter.makeSignpostID()
        )
        let flushBegan = DispatchTime.now().uptimeNanoseconds
        defer {
            ClashPerf.signposter.endInterval("latency.flush", flushSpan)
            let elapsed = Double(
                DispatchTime.now().uptimeNanoseconds - flushBegan
            ) / 1_000_000
            ClashPerf.span(
                "latency.flush",
                milliseconds: elapsed,
                detail: "batch=\(batch.count) groups=\(groups.count)"
            )
        }

        var names = isTestingLatency ? sweepTesting : testingNames
        var newDelays: [String: Int] = [:]
        var completed = isTestingLatency ? sweepCompleted : latencyCompletedCount
        var total = latencyTotalCount
        var finishedSummary: LatencyProbeEvent?

        for event in batch.values {
            switch event {
            case .started(let started):
                 
                 
                if pendingStartedNames.contains(started.name)
                    || batch["result:\(started.name)"] == nil {
                    names.insert(started.name)
                }
                completed = max(completed, started.completedCount)
                total = started.totalCount
            case .result(let result):
                names.remove(result.name)
                switch result.outcome {
                case .success(let milliseconds):
                    fileRunResult(result.name, milliseconds, into: &newDelays)
                    sessionProbeFailures.remove(result.name)
                case .failure:
                    fileRunResult(result.name, -1, into: &newDelays)
                    sessionProbeFailures.insert(result.name)
                case .deferred:
                     
                     
                     
                     
                    break
                }
                completed = max(completed, result.completedCount)
                total = result.totalCount
            case .cancelled(let cancelled):
                names.remove(cancelled.name)
            case .finished:
                finishedSummary = event
            }
        }

        if let finishedSummary,
           case .finished(let summary) = finishedSummary,
           summary.runID == latencyRunID {
             
             
            sweepDelays.merge(newDelays) { _, new in new }
             
             
            ClashLogStore.shared.append(
                "sweep finished  completed=\(summary.completedCount)/\(summary.totalCount)  cancelled=\(summary.cancellationReason.map(String.init(describing:)) ?? "no")  ok=\(sweepDelays.values.filter { $0 > 0 }.count)  failed=\(sweepDelays.values.filter { $0 <= 0 }.count)  untested=\(max(0, summary.totalCount - sweepDelays.count))",
                stream: .app, level: .info)
             
             
             
             
            let settledDelays = sweepDelays
            commitSweepToPublished(
                completed: summary.completedCount,
                total: summary.totalCount
            )
            schedulePostSweepSelectionSync()
             
             
             
             
             
             
             
            latencyRunID &+= 1
            pendingLatency.removeAll()
            pendingStartedNames.removeAll()
            sendSweepBatch(
                results: settledDelays, testing: [],
                completed: summary.completedCount, total: summary.totalCount, finished: true
            )
            return
        }

        if isTestingLatency {
             
             
            sweepTesting = names
            sweepDelays.merge(newDelays) { _, new in new }
            sweepCompleted = completed
            sendSweepBatch(
                results: newDelays, testing: names,
                completed: completed, total: total, finished: false
            )
            return
        }

         
         
        testingNames = names
        if !newDelays.isEmpty {
            recordMeasured(newDelays)
            nodeCatalog = nodeCatalog.map { record in
                guard let delay = newDelays[record.name] else { return record }
                return ProxyNodeRecord(
                    name: record.name,
                    type: record.type,
                    delay: delay,
                    groupNames: record.groupNames,
                    protocolDetails: record.protocolDetails
                )
            }
        }
        latencyCompletedCount = completed
        latencyTotalCount = total
    }

     
     
     
     
     
     
     
     
     
    private func commitSweepToPublished(completed: Int, total: Int) {
         
         
        recordMeasured(sweepDelays)
        sweepDelays = [:]
        sweepTesting = []
        sweepCompleted = 0
        failureReasons = [:]
        testingNames.removeAll()
        latencyCompletedCount = completed
        latencyTotalCount = total
        isTestingLatency = false
    }

     
     
     
     
     
     
    private func schedulePostSweepSelectionSync() {
        postSweepSelectionSync?.cancel()
        postSweepSelectionSync = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.postSweepSelectionSyncNanoseconds)
            guard !Task.isCancelled, let self, let command = self.command,
                  command.isConnected, !self.isTestingLatency
            else { return }
            await command.refreshMetadata()
            guard !Task.isCancelled, command.isConnected, !self.isTestingLatency else { return }
            await self.reloadInventoryOffMain(command: command)
            let groupCount = self.groups.count
            ClashLogStore.shared.append(
                "sweep follow-up  group selections re-read  groups=\(groupCount)",
                stream: .app, level: .info)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func followHealthChecksWhileVisible() async {
        healthCheckFollowers += 1
        defer { healthCheckFollowers -= 1 }
        await readKernelReadingsOnArrival()
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: Self.healthCheckFollowNanoseconds)
            guard !Task.isCancelled else { return }
            await readKernelHealthChecks()
        }
    }

     
     
     
    static var healthCheckFollowNanoseconds: UInt64 = 10_000_000_000
     
     
    private var healthCheckFollowers = 0
    var isFollowingHealthChecks: Bool { healthCheckFollowers > 0 }
     
     
     
    private var healthCheckFollowPaused = false

    func applicationBecameActive() {
        healthCheckFollowPaused = false
    }

     
     
     
     
    func readOnForeground() async -> Bool {
        guard isFollowingHealthChecks else { return false }
        await refresh()
        return true
    }

     
     
     
     
     
    private var polledRevision: String?

    private func readKernelHealthChecks() async {
        guard !healthCheckFollowPaused, let command, command.isConnected, !isTestingLatency else { return }
         
         
         
         
         
         
         
         
        var revisionRead: String?
        var readings: [String: Int] = [:]
        switch await readDelaysPaged(command) {
        case .read(let polled, let now):
            guard !Task.isCancelled, !healthCheckFollowPaused, command.isConnected, !isTestingLatency else { return }
            if polled.revision == polledRevision, polled.selectionsMatch(groups),
               Self.listHolds(polled.revision, in: command) {
                fillUntestedReadings(polled.readings, revision: polled.revision)
                delaysSince = now
                return
            }
            revisionRead = polled.revision
            readings = polled.readings
        case .notNow:
             
             
            return
        case .unsupported:
            guard !Task.isCancelled else { return }
            if let data = await command.nodesProxyDelays(),
               let polled = NodeInventory.polledDelays(from: data, readingURLs: NodeInventory.readingURLs(of: groups)) {
                guard !Task.isCancelled, !healthCheckFollowPaused, command.isConnected, !isTestingLatency else { return }
                if polled.revision == polledRevision, polled.selectionsMatch(groups),
                   Self.listHolds(polled.revision, in: command) {
                    fillUntestedReadings(polled.readings, revision: polled.revision)
                    return
                }
                revisionRead = polled.revision
            }
        }
        polledRevision = nil
         
         
        delaysSince = 0
        let proxiesRead = await command.nodesRefreshMetadata()
        guard !Task.isCancelled, !healthCheckFollowPaused, command.isConnected, !isTestingLatency else { return }
         
         
         
         
         
         
         
         
         
        let roundHolds = { [weak self, weak command] () -> Bool in
            guard let self, let command else { return false }
            return !Task.isCancelled && !self.healthCheckFollowPaused && self.command === command
                && command.isConnected && !self.isTestingLatency
        }
        if let catalog = try? await command.nodesProviderCatalog(), roundHolds(),
           catalog != runtimeProviderCatalog {
            providerNamesByProxy = ProxyProviderAttribution.uniqueProviderNames(in: catalog)
            runtimeProviderCatalog = withLoadedProviderNodes(catalog)
        }
        guard roundHolds() else { return }
        await reloadInventoryOffMain(command: command, stillWanted: roundHolds)
        guard roundHolds() else { return }
         
         
         
        if !readings.isEmpty, Self.listHolds(revisionRead, in: command) { fillUntestedReadings(readings, revision: revisionRead) }
        if proxiesRead, self.command === command, !Task.isCancelled { polledRevision = revisionRead }
    }

     
     
    private static func listHolds(_ revision: String?, in command: NodesCommanding) -> Bool {
        command.nodeListRevision.map { $0 == revision } ?? true
    }

     
     
     
     
     
     
     
     
     
    private func readKernelReadingsOnArrival() async {
        guard !healthCheckFollowPaused, let command, command.isConnected, !isTestingLatency else { return }
        let list = command.nodeListRevision ?? polledRevision
        var polled: NodeInventory.PolledDelays?
        var clock: Int64?
        switch await readDelaysPaged(command, since: 0) {
        case .read(let read, let now): polled = read; clock = now
        case .notNow: return
        case .unsupported:
            guard !Task.isCancelled else { return }
            if let data = await command.nodesProxyDelays() {
                polled = NodeInventory.polledDelays(from: data, readingURLs: NodeInventory.readingURLs(of: groups))
            }
        }
        guard let polled, !polled.readings.isEmpty, !Task.isCancelled, self.command === command,
              !healthCheckFollowPaused, command.isConnected, !isTestingLatency,
              (command.nodeListRevision ?? polledRevision) == list,
              list == nil || polled.revision == list
        else { return }
        fillUntestedReadings(polled.readings, revision: polled.revision)
         
         
         
        if let clock, let revision = command.nodeListRevision, revision == polled.revision {
            polledRevision = revision
            delaysSince = clock
        }
    }

     
    private enum DelaysRead {
        case read(NodeInventory.PolledDelays, now: Int64)
         
        case unsupported
         
         
        case notNow
    }

     
     
     
     
     
    private func readDelaysPaged(_ command: NodesCommanding, since asked: Int64? = nil) async -> DelaysRead {
        let since = asked ?? (polledRevision == nil ? 0 : delaysSince)
        let urls = NodeInventory.readingURLs(of: groups)
        var first: (revision: String, selections: [String: NodeInventory.PolledDelays.Selection], now: Int64)?
        var readings: [String: Int] = [:]
        var after = ""
        pages: for _ in 0..<1_000 {
            switch await command.nodesProxyDelaysPageRead(since: since, after: after, limit: 5_000) {
            case .unsupported:
                return first == nil ? .unsupported : .notNow
            case .notNow:
                return .notNow
            case .page(let data):
                if Task.isCancelled { return .notNow }
                let cursor = NodeInventory.delayPageCursor(data)
                 
                 
                 
                guard let polled = NodeInventory.polledDelays(from: data, readingURLs: urls) else { return .notNow }
                if let first {
                    guard first.revision == polled.revision else { return .notNow }
                } else {
                     
                     
                     
                    first = (polled.revision, polled.selections, cursor?.now ?? 0)
                }
                readings.merge(polled.readings) { _, newer in newer }
                guard let next = cursor?.next else { break pages }
                after = next
            }
        }
        guard let first else { return .notNow }
        return .read(.init(revision: first.revision, selections: first.selections, readings: readings), now: first.now)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func fillUntestedReadings(_ readings: [String: Int], revision: String? = nil) {
         
         
        var changes: [String: Int] = [:]
        for (key, delay) in readings where delays[key] != delay
            && (NodeInventory.isURLRecordKey(key) || !measuredNames.contains(key)) {
            changes[key] = delay
        }
        var gone = Set<String>()
        if let revision, revision != recordsRevision {
            if recordsRevision != nil { gone = Set(delays.keys.filter(NodeInventory.isURLRecordKey)) }
            recordsRevision = revision
        }
        let urls = NodeInventory.readingURLs(of: groups)
        if !urls.isEmpty {
            let named = Set(readings.keys.map(NodeInventory.nodeName(ofKey:)))
            for node in named {
                for url in urls {
                    let key = NodeInventory.latencyKey(node, readingURL: url)
                    if readings[key] == nil, delays[key] != nil { gone.insert(key) }
                }
            }
        }
        gone.subtract(readings.keys)
        guard !changes.isEmpty || !gone.isEmpty else { return }
        var merged = delays
        for key in gone { merged[key] = nil }
        merged.merge(changes) { _, new in new }
        delays = merged
    }

     
    private var recordsRevision: String?

     
     
    enum InventoryApplicationReason {
         
         
        case periodicRefresh
         
         
         
         
         
        case selectionReadback
    }

     
    nonisolated static func inventorySkipsDuringSweep(
        reason: InventoryApplicationReason,
        hasGroups: Bool,
        hasData: Bool
    ) -> Bool {
        guard case .periodicRefresh = reason else { return false }
        return hasGroups && hasData
    }

    private func applyInventory(
        _ data: Data?,
        reason: InventoryApplicationReason = .periodicRefresh
    ) {
        guard inventoryApplicationIsWanted(data, reason: reason) else { return }
        inventoryApplyGeneration &+= 1
         
         
         
        let proxies = ClashPerf.measure("inventory.decode") {
            NodeInventory.proxies(in: data)
        }
        let providerCatalog = inventoryProviderCatalog
        let inventory = ClashPerf.measure(
            "inventory.parse",
            detail: "entries=\(proxies?.count ?? 0) providers=\(providerCatalog.proxyProviders.count)"
        ) {
            NodeInventory.parse(
                proxies: proxies,
                groupConfigurationDetailsByName: groupConfigurationDetailsByName,
                providerCatalog: providerCatalog,
                configuredOrder: configuredOrder
            )
        }
        publishInventory(data: data, proxies: proxies, inventory: inventory, providerCatalog: providerCatalog)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func applyInventoryOffMain(
        _ data: Data?,
        reason: InventoryApplicationReason,
        stillWanted: (() -> Bool)? = nil
    ) async {
        guard inventoryApplicationIsWanted(data, reason: reason) else { return }
        inventoryApplyGeneration &+= 1
        let generation = inventoryApplyGeneration
        let groupDetails = groupConfigurationDetailsByName
        let providerCatalog = inventoryProviderCatalog
        let order = configuredOrder
        let parsed = await Task.detached(
            priority: .userInitiated
        ) { () -> ([String: Any]?, ([ProxyGroup], [String: Int]), Double) in
            let began = DispatchTime.now().uptimeNanoseconds
            let proxies = NodeInventory.proxies(in: data)
            let inventory = NodeInventory.parse(
                proxies: proxies,
                groupConfigurationDetailsByName: groupDetails,
                providerCatalog: providerCatalog,
                configuredOrder: order
            )
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
            return (proxies, inventory, elapsed)
        }.value
        ClashPerf.span(
            "inventory.parse.offmain",
            milliseconds: parsed.2,
            detail: "entries=\(parsed.0?.count ?? 0)"
        )
         
         
         
         
         
         
         
        if let stillWanted, !stillWanted() { return }
        if let command, command.isConnected, let latest = command.proxiesData {
            if latest != data {
                await applyInventoryOffMain(latest, reason: reason, stillWanted: stillWanted)
                return
            }
        } else if generation != inventoryApplyGeneration {
            return
        }
         
         
         
         
        if providerCatalog != inventoryProviderCatalog {
            await applyInventoryOffMain(data, reason: reason, stillWanted: stillWanted)
            return
        }
         
         
        if data == appliedProxiesData, providerCatalog == appliedProviderCatalog, !groups.isEmpty { return }
        if let stillWanted, !stillWanted() { return }
        publishInventory(data: data, proxies: parsed.0, inventory: parsed.1,
                         providerCatalog: providerCatalog)
    }

     
     
     
    private func inventoryApplicationIsWanted(
        _ data: Data?,
        reason: InventoryApplicationReason
    ) -> Bool {
        inventoryApplications &+= 1
         
         
         
         
         
         
         
         
        if isTestingLatency,
           Self.inventorySkipsDuringSweep(
               reason: reason,
               hasGroups: !groups.isEmpty,
               hasData: data != nil
           ) {
            return false
        }
         
         
         
         
         
         
         
         
         
         
         
         
         
        if let data,
           data == appliedProxiesData,
           inventoryProviderCatalog == appliedProviderCatalog,
           protocolDetailsByNodeName == appliedProtocolDetails,
           groupConfigurationDetailsByName == appliedGroupDetails,
           !groups.isEmpty {
            return false
        }
        return true
    }

    private func publishInventory(
        data: Data?,
        proxies: [String: Any]?,
        inventory: ([ProxyGroup], [String: Int]),
         
         
         
        providerCatalog: ProviderRuntimeCatalog
    ) {
        appliedProxiesData = data
        appliedProviderCatalog = providerCatalog
        appliedProtocolDetails = protocolDetailsByNodeName
        appliedGroupDetails = groupConfigurationDetailsByName
         
         
         
        ClashPerf.measure("inventory.publish") {
            groups = reapplyingExtendedMembers(to: inventory.0)
            fillUntestedReadings(inventory.1)
        }
        ClashPerf.measure("inventory.catalog") {
            rebuildCatalog(from: proxies, providerCatalog: providerCatalog)
        }
    }

     
     
     
    private func reloadInventoryOffMain(command: NodesCommanding, stillWanted: (() -> Bool)? = nil) async {
        guard command.isConnected, let data = command.proxiesData else {
            reloadInventory(command: command)
            return
        }
        runtimeRestartRequestedAt = nil
        isRuntimeAvailable = true
        lastRuntimeInventory = data
        await applyInventoryOffMain(data, reason: .periodicRefresh, stillWanted: stillWanted)
        if let stillWanted, !stillWanted() { return }
        scheduleConnectedProjection()
    }

    private func rebuildCatalog(from proxies: [String: Any]?, providerCatalog: ProviderRuntimeCatalog) {
        catalogGeneration &+= 1
        let generation = catalogGeneration
        guard let proxies else {
            catalogRebuild = nil
            nodeCatalog = []
            return
        }
        let details = protocolDetailsByNodeName
        let order = configuredOrder
        catalogRebuild = Task { [weak self] in
            let records = await Task.detached(priority: .userInitiated) {
                NodeInventory.nodeCatalog(
                    proxies: proxies,
                    protocolDetailsByNodeName: details,
                    providerCatalog: providerCatalog,
                    configuredOrder: order
                )
            }.value
            guard let self, generation == self.catalogGeneration else { return }
            self.nodeCatalog = records.map { record in
                ProxyNodeRecord(
                    name: record.name,
                    type: record.type,
                    delay: self.delays[record.name],
                    groupNames: record.groupNames,
                    protocolDetails: record.protocolDetails
                )
            }
        }
    }

    private func reloadInventory(command: NodesCommanding) {
        if command.isConnected, let data = command.proxiesData {
            runtimeRestartRequestedAt = nil
            isRuntimeAvailable = true
             
             
             
             
             
             
            lastRuntimeInventory = data
            applyInventory(data)
            scheduleConnectedProjection()
            return
        }

         
         
         
         
         
         
        if command.isReopeningControlSession { return }

         
         
         
         
        if let requested = runtimeRestartRequestedAt {
            if Date().timeIntervalSince(requested) < runtimeRestartGrace,
               !groups.isEmpty {
                return
            }
            runtimeRestartRequestedAt = nil
        }

        isRuntimeAvailable = false
        providerNamesByProxy = [:]
         
         
         
         
         
         
        let load = offlineCatalogLoader
        scheduleOfflineCatalog(load)
    }

    private func scheduleOfflineCatalog(
        _ load: @escaping @Sendable () -> OfflineProxyCatalogSnapshot?
    ) {
        inventoryProjectionGeneration &+= 1
        let generation = inventoryProjectionGeneration
        let previousRuntime = lastRuntimeInventory
        let previousYAML = groups.isEmpty ? nil : lastOfflineYAML
        let previousProviderCatalog = offlineProviderCatalog
        inventoryProjectionTasks[generation] = Task.detached(priority: .userInitiated) { [weak self] in
            let began = DispatchTime.now().uptimeNanoseconds
            let snapshot = load()
             
             
             
            if OfflineCatalogChange.isUnchanged(
                snapshot, previousRuntime: previousRuntime, previousYAML: previousYAML,
                previousProviderCatalog: previousProviderCatalog
            ) {
                await MainActor.run { self?.inventoryProjectionTasks[generation] = nil }
                return
            }
            let projection = snapshot.map { NodesInventoryProjection.read(yaml: $0.yaml) }
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
            await MainActor.run {
                self?.receiveOfflineCatalog(
                    snapshot,
                    projection: projection,
                    generation: generation,
                    milliseconds: elapsed
                )
            }
        }
    }

    private func receiveOfflineCatalog(
        _ snapshot: OfflineProxyCatalogSnapshot?,
        projection: NodesInventoryProjection?,
        generation: UInt64,
        milliseconds: Double
    ) {
        inventoryProjectionTasks[generation] = nil
        guard generation == inventoryProjectionGeneration else { return }
        ClashPerf.span(
            "proxies.offline",
            milliseconds: milliseconds,
            detail: "nodes=\(projection?.protocolDetails.count ?? 0)"
        )
        cachedProviderNodeCount = snapshot?.cachedProviderNodeCount
        offlineGroupsProfileID = snapshot?.profileID
        guard let snapshot, let projection else {
            lastRuntimeInventory = nil
            protocolDetailsByNodeName = [:]
            groupConfigurationDetailsByName = [:]
            configuredOrder = .none
            trafficUsageByGroupName = [:]
            applyInventory(nil)
            return
        }
        let protocolDetails = projection.protocolDetails.merging(
            locallyEditedProtocolDetails
        ) { _, edited in edited }
        if !groups.isEmpty,
           lastRuntimeInventory == snapshot.runtimeData,
           snapshot.providerCatalog == offlineProviderCatalog,
           protocolDetails == protocolDetailsByNodeName,
           projection.groupDetails == groupConfigurationDetailsByName,
           projection.order == configuredOrder,
           projection.trafficUsage == trafficUsageByGroupName {
            return
        }
        protocolDetailsByNodeName = protocolDetails
        groupConfigurationDetailsByName = projection.groupDetails
        configuredOrder = projection.order
        trafficUsageByGroupName = projection.trafficUsage
        lastRuntimeInventory = snapshot.runtimeData
        lastOfflineYAML = snapshot.yaml
        offlineProviderCatalog = snapshot.providerCatalog
        applyInventory(snapshot.runtimeData)
    }

     
    private func scheduleConnectedProjection() {
        let protocolDetails = protocolDetailsLoader
        let groupDetails = groupConfigurationDetailsLoader
        let order = configuredOrderLoader
        let trafficUsage = trafficUsageLoader
        scheduleInventoryProjection {
            NodesInventoryProjection(
                protocolDetails: protocolDetails(),
                groupDetails: groupDetails(),
                order: order(),
                trafficUsage: trafficUsage()
            )
        }
    }

     
     
     
    private func scheduleInventoryProjection(
        _ read: @escaping @Sendable () -> NodesInventoryProjection
    ) {
        inventoryProjectionGeneration &+= 1
        let generation = inventoryProjectionGeneration
        inventoryProjectionTasks[generation] = Task.detached(priority: .userInitiated) { [weak self] in
            let began = DispatchTime.now().uptimeNanoseconds
            let projection = read()
            let elapsed = Double(DispatchTime.now().uptimeNanoseconds - began) / 1_000_000
            await MainActor.run {
                self?.receiveInventoryProjection(
                    projection,
                    generation: generation,
                    milliseconds: elapsed
                )
            }
        }
    }

    private func receiveInventoryProjection(
        _ projection: NodesInventoryProjection,
        generation: UInt64,
        milliseconds: Double
    ) {
        inventoryProjectionTasks[generation] = nil
        guard generation == inventoryProjectionGeneration else { return }
        ClashPerf.span(
            "proxies.projection",
            milliseconds: milliseconds,
            detail: "nodes=\(projection.protocolDetails.count) groups=\(projection.groupDetails.count)"
        )
        let protocolDetails = projection.protocolDetails.merging(
            locallyEditedProtocolDetails
        ) { _, edited in edited }
        if protocolDetails == protocolDetailsByNodeName,
           projection.groupDetails == groupConfigurationDetailsByName,
           projection.order == configuredOrder,
           projection.trafficUsage == trafficUsageByGroupName {
            return
        }
        protocolDetailsByNodeName = protocolDetails
        groupConfigurationDetailsByName = projection.groupDetails
        configuredOrder = projection.order
        trafficUsageByGroupName = projection.trafficUsage
         
         
         
        if let command, command.isConnected, let current = command.proxiesData {
            lastRuntimeInventory = current
        }
        applyInventory(lastRuntimeInventory)
    }

     
     
    func settleInventoryProjection() async {
        for task in inventoryProjectionTasks.values {
            await task.value
        }
    }

     
     
     
    private func noteKernelAcceptedSelection(group: String, name: String) {
        applyOfflineSelection(group: group, name: name, kernelConfirmed: true)
    }

     
     
     
     
    private func applyOfflineSelection(
        group: String,
        name: String,
        kernelConfirmed: Bool = false
    ) {
        guard let index = groups.firstIndex(where: { $0.name == group }) else { return }
        let current = groups[index]
        groups[index] = ProxyGroup(
            name: current.name,
            type: current.type,
            now: name,
            members: current.members,
            resolvedNow: current.memberResolvedNames[name] ?? name,
            memberTypes: current.memberTypes,
            memberGroupNames: current.memberGroupNames,
            memberResolvedNames: current.memberResolvedNames,
             
             
             
             
            memberPlaceholderTypes: current.memberPlaceholderTypes,
            configurationDetails: current.configurationDetails,
            hidden: current.hidden,
            testURL: current.testURL,
            iconURL: current.iconURL,
            emptyFallback: current.emptyFallback,
             
             
             
             
             
            fixed: kernelConfirmed
                && ProxyGroupControlKind(rawType: current.type).canBeUnpinned
                ? name
                : current.fixed,
            memberTotal: current.memberTotal,
            hiddenMembers: current.hiddenMembers
        )
    }

    private func restoreActiveProfileSelectionIfNeeded(command: NodesCommanding) async {
        guard let state = preferences?.load() else { return }
         
         
         
         
         
         
         
         
         
         
         
        let runtimeKey = selectionRuntimeKey(state)
        guard runtimeKey != restoredRuntimeKey else { return }
         
         
         
         
        func stillTheSame() -> Bool {
             
             
            !isSwitchingProxy && preferences?.load().map(selectionRuntimeKey) == runtimeKey
        }
        currentGroupName = state.currentGroupName
         
         
         
        foldStateRecorded = Self.storedFoldStateIsTheReaders(state.unfoldedGroups)
        unfoldedGroups = state.unfoldedGroups ?? Set(groups.map(\.name))

         
         
         
        guard command.isConnected else { return }
         
         
         
         
         
        guard isRuntimeAvailable else { return }

        var restorePlan: [(group: String, member: String)] = []
         
         
         
        var leftOpen = false
         
         
         
         
         
        let hidden = ModuleRouteHiding.hiddenNames()
        for group in groups where group.acceptsMemberChoice && hidden.contains(group.now) {
             
            if let preferred = state.selectedMap[group.name], !hidden.contains(preferred) { continue }
            guard let shown = group.members.first(where: { !hidden.contains($0) }) else { continue }
            restorePlan.append((group.name, shown))
        }
        for group in groups where !restorePlan.contains(where: { $0.group == group.name }) {
            guard let preferred = state.selectedMap[group.name], group.acceptsMemberChoice, !hidden.contains(preferred) else { continue }
             
             
             
            let listed = await groupLists(preferred, in: group, runtimeKey: runtimeKey)
            guard stillTheSame() else { return }
            switch listed {
            case true?: restorePlan.append((group.name, preferred))
            case false?:
                 
                 
                if hidden.contains(group.now), let shown = group.members.first(where: { !hidden.contains($0) }) {
                    restorePlan.append((group.name, shown))
                }
            case nil: leftOpen = true
            }
        }
        var restoredManualGroup: String?
        for item in restorePlan {
            guard let current = groups.first(
                where: { $0.name == item.group }
            ) else {
                continue
            }
            if ProxyGroupControlKind(rawType: current.type) == .manual,
               item.group != GlobalProxySelectionPolicy.groupName {
                restoredManualGroup = restoredManualGroup ?? item.group
            }
            guard !current.holdsSelection(item.member) else { continue }
            guard stillTheSame() else { return }
            let confirmed = await command.select(
                group: item.group,
                name: item.member
            )
            if confirmed { noteKernelAcceptedSelection(group: item.group, name: item.member) }
            await applyInventoryOffMain(command.proxiesData, reason: .selectionReadback)
            guard stillTheSame() else { return }
            guard confirmed,
                  groups.first(where: { $0.name == item.group })?
                    .holdsSelection(item.member) == true else {
                 
                 
                return
            }
        }

        if command.mode.trimmingCharacters(
            in: .whitespacesAndNewlines
        ).lowercased() == "global",
           let global = groups.first(where: {
               $0.name == GlobalProxySelectionPolicy.groupName
           }) {
            let candidates = [
                state.currentGroupName,
                restoredManualGroup,
            ].compactMap { $0 }
            let preferred = candidates.first {
                global.members.contains($0)
                    && GlobalProxySelectionPolicy.isSafeManualGroup(
                        $0,
                        groups: groups
                    )
            }
            if let preferred, !global.holdsSelection(preferred) {
                let confirmed = await command.select(
                    group: global.name,
                    name: preferred
                )
                if confirmed { noteKernelAcceptedSelection(group: global.name, name: preferred) }
                await applyInventoryOffMain(command.proxiesData, reason: .selectionReadback)
                guard confirmed,
                      groups.first(where: {
                          $0.name == GlobalProxySelectionPolicy.groupName
                      })?.holdsSelection(preferred) == true else {
                    return
                }
            }
        }

        await applyInventoryOffMain(command.proxiesData, reason: .selectionReadback)
         
         
        guard !leftOpen, stillTheSame() else { return }
        restoredRuntimeKey = runtimeKey
    }

     
     
     
     
     
    private func selectionRuntimeKey(_ state: ActiveNodeProfileState) -> String {
        let selectionFingerprint = (try? JSONEncoder.sortedKeys.encode(
            state.selectedMap
        )).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return (currentRuntimeIdentity().map {
            "\($0.profileID)|\($0.revision)"
        } ?? state.profileID) + "|" + selectionFingerprint
    }

     
     
     
    private func groupLists(_ name: String, in group: ProxyGroup, runtimeKey: String) async -> Bool? {
        if group.members.contains(name) { return true }
        guard !group.hasEveryMember else { return false }
        guard let source = memberPages else { return nil }
         
         
         
         
         
        let progressKey = runtimeKey + "\u{0}" + group.name + "\u{0}" + name
        var offset = membershipSearchOffset[progressKey] ?? 0
        for _ in 0..<20 {
            guard let page = try? await source.searchGroupMembers(group.name, query: name, offset: offset, limit: NodePaging.page)
            else {
                membershipSearchOffset[progressKey] = offset
                return nil
            }
            if page.members.contains(where: { $0.name == name }) {
                membershipSearchOffset[progressKey] = nil
                return true
            }
            offset += page.members.count
            if page.members.isEmpty || offset >= page.total {
                membershipSearchOffset[progressKey] = nil
                return false
            }
        }
        membershipSearchOffset[progressKey] = offset
        return nil
    }

     
     
    private var membershipSearchOffset: [String: Int] = [:]

    private func currentRuntimeIdentity() -> NodesRuntimeIdentity? {
        if let identity = runtimeIdentityLoader() {
            return identity
        }
        return preferences?.load().map {
            NodesRuntimeIdentity(profileID: $0.profileID, revision: "")
        }
    }

     
     
     
     
     
     
    private func transitionRuntimeIfNeeded(command: NodesCommanding) async -> Bool {
        guard let identity = currentRuntimeIdentity() else { return false }
        guard let previous = observedRuntimeIdentity else {
            observedRuntimeIdentity = identity
            return false
        }
        guard identity != previous else { return false }
        observedRuntimeIdentity = identity
         
        testAllSession &+= 1

        await cancelLatencyTests(reason: .superseded)
        providerCatalogGeneration &+= 1
         
         
        inventoryProjectionGeneration &+= 1
        restoredRuntimeKey = nil
         
         
         
         
         
         
         
        if preferences?.latencyResults != nil {
            loadMeasuredDelays()
        } else {
            delays = [:]
            measuredNames = []
        }
        sessionProbeFailures = []
        nodeCatalog = []
        query = ""
        testingNames = []
        currentGroupName = nil
        unfoldedGroups = []
        isSwitchingProxy = false
        providerNamesByProxy = [:]
        isRuntimeAvailable = false
        trafficUsageByGroupName = [:]
        protocolDetailsByNodeName = [:]
        locallyEditedProtocolDetails = [:]
        groupConfigurationDetailsByName = [:]
        latencyCompletedCount = 0
        latencyTotalCount = 0

        guard command.isConnected else { return false }
        await command.closeConnectionsAfterProxySelection()
         
         
         
         
         
         
        runtimeRestartRequestedAt = Date()
        command.reconnectAfterRuntimeChange()
        return false
    }

    private func loadProviderSources(command: NodesCommanding, token: UInt64) async {
        providerArrivalTask?.cancel()
        providerArrivalTask = nil
        defer { watchPendingProviders(command: command, token: token) }
        guard command.isConnected else {
            if token == providerCatalogGeneration {
                providerNamesByProxy = [:]
                runtimeProviderCatalog = .empty
            }
            return
        }
        do {
            let catalog = try await command.nodesProviderCatalog()
            guard token == providerCatalogGeneration else { return }
            providerNamesByProxy = ProxyProviderAttribution.uniqueProviderNames(in: catalog)
            runtimeProviderCatalog = withLoadedProviderNodes(catalog)
             
             
             
             
            reapplyInventoryWithProviderCatalog(command: command)
        } catch {
            guard token == providerCatalogGeneration else { return }
            providerNamesByProxy = [:]
            runtimeProviderCatalog = .empty
             
             
             
             
             
             
             
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard token == providerCatalogGeneration,
                  command.isConnected,
                  let retried = try? await command.nodesProviderCatalog(),
                  token == providerCatalogGeneration else { return }
            providerNamesByProxy = ProxyProviderAttribution.uniqueProviderNames(in: retried)
            runtimeProviderCatalog = withLoadedProviderNodes(retried)
            reapplyInventoryWithProviderCatalog(command: command)
        }
    }

    private var hasPendingProviderNodes: Bool {
        if runtimeProviderCatalog.proxyProviders.isEmpty { return true }
        if configuredOrder.providerNames.contains(where: { runtimeProviderCatalog.proxyProviders[$0] == nil }) { return true }
        return runtimeProviderCatalog.proxyProviders.values.contains { !$0.isKernelInternal && $0.proxies.isEmpty }
    }

     
     
     
    private func watchPendingProviders(command: NodesCommanding, token: UInt64) {
        guard token == providerCatalogGeneration, command.isConnected, hasPendingProviderNodes else { return }
        let delay = providerCatalogRetryDelayNanoseconds
        providerArrivalTask = Task { [weak self, weak command] in
            for _ in 0..<15 {
                do { try await Task.sleep(nanoseconds: delay) } catch { return }
                guard let self, let command, command.isConnected,
                      token == self.providerCatalogGeneration, !Task.isCancelled else { return }
                guard let catalog = try? await command.nodesProviderCatalog() else { continue }
                guard token == self.providerCatalogGeneration, command.isConnected, !Task.isCancelled else { return }
                if catalog != self.runtimeProviderCatalog {
                    await command.refreshMetadata()
                    guard token == self.providerCatalogGeneration, command.isConnected, !Task.isCancelled else { return }
                    self.providerNamesByProxy = ProxyProviderAttribution.uniqueProviderNames(in: catalog)
                    self.runtimeProviderCatalog = self.withLoadedProviderNodes(catalog)
                    if let data = command.proxiesData { await self.applyInventoryOffMain(data, reason: .periodicRefresh) }
                }
                if !self.hasPendingProviderNodes { return }
            }
        }
    }

     
     
     
     
     
     
     
     
    private func reapplyInventoryWithProviderCatalog(command: NodesCommanding) {
        guard runtimeProviderCatalog != appliedProviderCatalog,
              command.isConnected,
              let data = command.proxiesData else { return }
        applyInventory(data)
    }

}

 
 
 
 
 
 
 
private actor SubscriptionHealthRuns {
    private let providerNamesByProxy: [String: String]
    private let usesBulkHealth: Bool
    private let startedAt: Date
    private var runs: [String: Task<[String: Int], Never>] = [:]
     
    private var early: [String: Int] = [:]
    private var finished: Set<String> = []
    private var cancelled = false

    init(
        providerNamesByProxy: [String: String],
        usesBulkHealth: Bool = true,
        startedAt: Date = Date()
    ) {
        self.providerNamesByProxy = providerNamesByProxy
        self.usesBulkHealth = usesBulkHealth
        self.startedAt = startedAt
    }

     
     
    func delay(for name: String, command: NodesCommanding) async -> Int? {
        guard usesBulkHealth,
              let provider = providerNamesByProxy[name] else { return nil }
        let run = run(for: provider, command: command)
         
         
         
        while !finished.contains(provider), !cancelled, !Task.isCancelled {
            if let seen = early[name] { return seen }
            await pollOnce(provider: provider, command: command)
        }
         
         
         
         
        guard !cancelled, !Task.isCancelled else { return -1 }
        if let measured = await run.value[name], measured > 0 {
            return measured
        }
        if let seen = early[name] { return seen }
         
         
         
         
         
         
        return nil
    }

     
    func cancel() {
        cancelled = true
        for run in runs.values { run.cancel() }
    }

    private func run(
        for provider: String, command: NodesCommanding
    ) -> Task<[String: Int], Never> {
        if let existing = runs[provider] { return existing }
        let began = Date()
        ClashLogStore.shared.append(
            "provider-health start  provider=\(provider)",
            stream: .app, level: .info)
        let created = Task { await command.nodesHealthCheckProvider(named: provider) }
        runs[provider] = created
        Task { [weak self] in
            let map = await created.value
            let ok = map.values.filter { $0 > 0 }.count
            ClashLogStore.shared.append(
                "provider-health done  provider=\(provider)  ok=\(ok)/\(map.count)  in=\(String(format: "%.1f", Date().timeIntervalSince(began)))s",
                stream: .app, level: ok == 0 ? .warning : .info)
            await self?.markFinished(provider)
        }
        return created
    }

    private func markFinished(_ provider: String) {
        finished.insert(provider)
    }

     
     
     
     
    private func pollOnce(provider: String, command: NodesCommanding) async {
        try? await Task.sleep(nanoseconds: 250_000_000)
        guard !cancelled, !Task.isCancelled else { return }
         
         
        if let readings = await command.nodesProviderReadings(
            named: provider, since: Int64(startedAt.timeIntervalSince1970 * 1_000) - 1_000
        ) {
            early.merge(readings) { _, newer in newer }
            return
        }
        guard let catalog = try? await command.nodesProviderCatalog(),
              let live = catalog.proxyProviders[provider] else { return }
        for proxy in live.proxies {
            guard let measuredAt = proxy.measuredAt, measuredAt >= startedAt else { continue }
            if let delay = proxy.latestDelayMilliseconds, delay > 0 {
                early[proxy.name] = delay
            } else if proxy.alive == false {
                early[proxy.name] = -1
            }
        }
    }
}


extension NodesModel {
     
     
     
     
     
     
    private func logSweepCoverage(planned: [String]) {
        let subscriptionNames = runtimeProviderCatalog.proxyProviders.values
            .filter { !$0.isKernelInternal }
            .flatMap { $0.proxies.map(\.name) }
        guard !subscriptionNames.isEmpty else { return }
        var seen: Set<String> = []
        var folded: [String] = []
        for name in subscriptionNames {
            if !seen.insert(name).inserted { folded.append(name) }
        }
        let plannedSet = Set(planned)
        let excluded = plannedSet.isEmpty ? [] : Array(
            Set(subscriptionNames).subtracting(plannedSet)
                .subtracting(folded)
        ).sorted().prefix(6)
        var parts = [
            "sweep coverage  catalog=\(subscriptionNames.count)",
            "planned=\(planned.count)",
            "workers=\(Self.activeLatencyPolicy.concurrentProbeCount(for: planned.count))",
            "providerHealth=\(LatencyProbePolicy.currentPlatform.usesBulkProviderHealth(for: planned.count, catalogCount: groups.reduce(0) { $0 + $1.members.count } + providerNamesByProxy.count) ? "bulk" : "per-node")",
        ]
        if !folded.isEmpty {
            parts.append("folded=\(folded.count) [\(folded.prefix(6).joined(separator: ", "))]")
        }
        if !excluded.isEmpty {
            parts.append("unplanned=[\(excluded.joined(separator: ", "))]")
        }
        ClashLogStore.shared.append(parts.joined(separator: "  "), stream: .app)
    }
}

 
final class LockedNameSet: @unchecked Sendable {
    private let lock = NSLock()
    private var names = Set<String>()
    func insert(_ name: String) { lock.lock(); names.insert(name); lock.unlock() }
    func contains(_ name: String) -> Bool { lock.lock(); defer { lock.unlock() }; return names.contains(name) }
    func removeAll() { lock.lock(); names.removeAll(); lock.unlock() }
    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return names.isEmpty }
}

struct LatencySweepBatch: Equatable, Sendable {
     
    let results: [String: Int]
     
    let testing: Set<String>
     
    let groupTerminals: [String: String]
     
     
    var groupTerminalKeys: [String: String] = [:]
    let completed: Int
    let total: Int
    let finished: Bool
}

 

extension NodesModel {
     
     
    private var memberPages: NodePageSource? {
        if let command, command.isConnected { return command.nodePages }
        return OfflineNodeCatalogRegistry.current
    }

     
     
     
     
    private var nodeListIdentity: String? {
        if let command, command.isConnected { return command.nodeListRevision.map { "tunnel:" + $0 } }
        return OfflineNodeCatalogRegistry.current.map { "catalog:\($0.serial)" }
    }

     
     
     
     
    func searchMembers(matching query: String) async {
        guard let source = memberPages else { return }
        let list = nodeListIdentity
        if searchedList != list { searchedMembers = [:] }
        searchedList = list
        let partial = groups.filter { !$0.hasEveryMember }.map(\.name)
        for name in partial {
            guard let page = try? await source.searchGroupMembers(name, query: query, offset: 0, limit: NodePaging.page)
            else { continue }
             
             
            guard nodeListIdentity == list else { return }
             
             
            if let pageRevision = page.revision, let shown = command?.nodeListRevision, pageRevision != shown { return }
            let found = ModuleRouteHiding.visible(page.members, name: \.name, hiding: ModuleRouteHiding.hiddenNames())
            guard !found.isEmpty, let index = groups.firstIndex(where: { $0.name == name }) else { continue }
            searchedMembers[name] = found
            groups[index] = Self.extending(groups[index], with: found, in: groups)
        }
    }

     
    enum MemberLanding {
         
         
        case asItLands
         
        case whenDone
    }

     
    nonisolated static let firstMemberLanding = 1_000

     
     
     
     
     
     
    func loadRemainingMembers(of groupName: String, landing: MemberLanding = .asItLands) async {
        let command = self.command
        guard let source = memberPages,
              let current = groups.first(where: { $0.name == groupName }), !current.hasEveryMember,
              !membersLoading.contains(groupName)
        else { return }
        membersLoading.insert(groupName)
        defer { membersLoading.remove(groupName) }
        let connected = command?.isConnected == true
        let revision = command?.nodeListRevision
        let list = nodeListIdentity
        let kept = list.flatMap { list in extendedMembers[groupName].flatMap { $0.list == list ? $0 : nil } }
         
         
         
        let firstPageWhole = current.members.count + current.hiddenMembers.count >= min(NodePaging.firstMembers, current.memberTotal)
        let from = kept?.from ?? (firstPageWhole ? NodePaging.firstMembers : 0)
        var read = kept?.members ?? []
        var pending: [NodeMember] = []
        var nextLanding = max(Self.firstMemberLanding, read.count * 2)
        func land() {
             
             
            if let list { extendedMembers[groupName] = (list, read, from) }
            guard !pending.isEmpty, let index = groups.firstIndex(where: { $0.name == groupName }) else { return }
            groups[index] = Self.extending(groups[index], with: pending, in: groups)
            pending.removeAll(keepingCapacity: true)
        }
        var offset = from + read.count
        while offset < current.memberTotal {
            guard let page = try? await source.groupMembers(groupName, offset: offset, limit: NodePaging.page),
                  !page.members.isEmpty
            else {
                 
                if self.command === command, (command?.isConnected == true) == connected, nodeListIdentity == list { land() }
                return
            }
             
             
             
            guard self.command === command, (command?.isConnected == true) == connected, nodeListIdentity == list else { return }
            if let pageRevision = page.revision, let revision, pageRevision != revision { return }
            read += page.members
            pending += page.members
            offset += page.members.count
            if landing == .asItLands, read.count >= nextLanding {
                land()
                nextLanding = read.count * 2
            }
        }
        land()
    }

     
     
     
    func loadRemainingMembers(ofEvery names: [String]) async {
        for name in names {
            await loadRemainingMembers(of: name, landing: .whenDone)
        }
    }

     
    private func reapplyingExtendedMembers(to fresh: [ProxyGroup]) -> [ProxyGroup] {
         
         
        let list = nodeListIdentity
        extendedMembers = extendedMembers.filter { $0.value.list == list }
        if searchedList != list { searchedMembers = [:] }
        guard !extendedMembers.isEmpty || !searchedMembers.isEmpty else { return fresh }
        return fresh.map { group in
            guard !group.hasEveryMember else { return group }
            let extra = (extendedMembers[group.name]?.members ?? []) + (searchedMembers[group.name] ?? [])
            return extra.isEmpty ? group : Self.extending(group, with: extra, in: fresh)
        }
    }

     
     
     
    nonisolated static func extending(_ group: ProxyGroup, with page: [NodeMember], in groups: [ProxyGroup]) -> ProxyGroup {
        let byName = Dictionary(groups.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        func resolve(_ name: String) -> String {
            var current = name
            var visited = Set<String>()
            while let inner = byName[current], visited.insert(current).inserted, !inner.now.isEmpty {
                current = inner.now
            }
            return current
        }
        var members = group.members
        var seen = Set(members)
        var types = group.memberTypes
        var groupNames = group.memberGroupNames
        var resolved = group.memberResolvedNames
        var placeholders = group.memberPlaceholderTypes
        let hidden = ModuleRouteHiding.hiddenNames()
        var hiddenMembers = group.hiddenMembers
        for member in page {
             
            if hidden.contains(member.name) {
                hiddenMembers.insert(member.name)
                continue
            }
            guard seen.insert(member.name).inserted else { continue }
            members.append(member.name)
            types[member.name] = byName[member.name]?.type ?? member.type
            if byName[member.name] != nil {
                groupNames.insert(member.name)
                resolved[member.name] = resolve(member.name)
            } else if let placeholder = member.placeholderType {
                placeholders[member.name] = placeholder
            }
        }
        return ProxyGroup(
            name: group.name, type: group.type, now: group.now, members: members,
            resolvedNow: group.resolvedNow, memberTypes: types, memberGroupNames: groupNames,
            memberResolvedNames: resolved, memberPlaceholderTypes: placeholders,
            configurationDetails: group.configurationDetails, hidden: group.hidden,
            testURL: group.testURL, iconURL: group.iconURL, emptyFallback: group.emptyFallback,
            fixed: group.fixed, memberTotal: group.memberTotal, hiddenMembers: hiddenMembers
        )
    }
}

 

extension NodesModel {
     
     
    func loadProviderNodes(named name: String) async {
        guard let command, command.isConnected, let source = command.nodePages,
              let provider = runtimeProviderCatalog.proxyProviders[name],
              provider.proxies.count < provider.nodeCount, !providerNodesLoading.contains(name)
        else { return }
        providerNodesLoading.insert(name)
        defer { providerNodesLoading.remove(name) }
        guard let list = nodeListIdentity else { return }
        let revision = command.nodeListRevision
        var proxies = provider.proxies
        var offset = proxies.count
        while offset < provider.nodeCount {
            guard let page = try? await source.providerNodes(name, offset: offset, limit: NodePaging.page),
                  !page.proxies.isEmpty, self.command === command, command.isConnected, nodeListIdentity == list
            else { return }
            if let pageRevision = page.revision, let revision, pageRevision != revision { return }
             
             
            guard runtimeProviderCatalog.proxyProviders[name]?.updatedAt == provider.updatedAt else { return }
            proxies += page.proxies.map(Self.providerProxy)
            offset += page.proxies.count
            loadedProviderNodes[name] = LoadedProviderNodes(
                list: list, updatedAt: provider.updatedAt, total: provider.nodeCount, proxies: proxies)
            runtimeProviderCatalog = withLoadedProviderNodes(runtimeProviderCatalog)
        }
    }

     
    nonisolated static func providerProxy(_ row: NodeRow) -> ProxyProviderRuntime.Proxy {
        ProxyProviderRuntime.Proxy(
            name: row.name,
            type: row.type.isEmpty ? nil : row.type,
            alive: row.alive,
            latestDelayMilliseconds: row.latest?.delay.flatMap { $0 > 0 ? $0 : nil },
            measuredAt: ProviderRuntimeCatalogParser.parseDate(row.latest?.time)
        )
    }

     
     
     
    func withLoadedProviderNodes(_ catalog: ProviderRuntimeCatalog) -> ProviderRuntimeCatalog {
        guard !loadedProviderNodes.isEmpty else { return catalog }
        var merged = catalog
        let list = nodeListIdentity
        for (name, loaded) in loadedProviderNodes {
            guard let provider = catalog.proxyProviders[name], loaded.list == list,
                  provider.nodeCount == loaded.total, provider.updatedAt == loaded.updatedAt
            else {
                loadedProviderNodes[name] = nil
                continue
            }
            guard provider.proxies.count < loaded.proxies.count else { continue }
            merged.proxyProviders[name] = ProxyProviderRuntime(
                name: provider.name, vehicleType: provider.vehicleType, updatedAt: provider.updatedAt,
                hasHealthCheck: provider.hasHealthCheck, proxies: loaded.proxies,
                total: provider.total, deadCount: provider.deadCount
            )
        }
        return merged
    }
}

extension NodesModel {
     
     
     
     
     
     
    func setHealthCheckFollowPausedWhileUnseen(_ unseen: Bool) {
        healthCheckFollowPaused = unseen
    }
}

 
 
 
 
 
enum SequenceLines {
     
    static func count(of section: String) -> Int? {
        var copy = section
        return copy.withUTF8 { scan($0) }?.count
    }

     
    static func items(of section: String) -> [String]? {
        var copy = section
        return copy.withUTF8 { bytes -> [String]? in
            guard let starts = scan(bytes) else { return nil }
            return starts.enumerated().map { position, start in
                var end = position + 1 < starts.count ? starts[position + 1] : bytes.count
                 
                while end > start, bytes[end - 1] == UInt8(ascii: "\n") || bytes[end - 1] == UInt8(ascii: " ")
                    || bytes[end - 1] == UInt8(ascii: "\r") { end -= 1 }
                return String(decoding: bytes[start..<end], as: UTF8.self)
            }
        }
    }

     
    static func count(of section: Substring) -> Int? {
        var copy = section
        return copy.withUTF8 { scan($0) }?.count
    }

     
    static func lineSpan(of section: Substring) -> Int {
        var copy = section
        let lines = copy.withUTF8 { bytes -> Int in
            var count = 0
            for byte in bytes where byte == UInt8(ascii: "\n") { count += 1 }
            return count
        }
        return max(0, (section.hasSuffix("\n") ? lines : lines + 1) - 1)
    }

     
     
    static func lineSpan(of section: String) -> Int {
        var copy = section
        let lines = copy.withUTF8 { bytes -> Int in
            var count = 0
            for byte in bytes where byte == UInt8(ascii: "\n") { count += 1 }
            return count
        }
        return max(0, (section.hasSuffix("\n") ? lines : lines + 1) - 1)
    }

     
     
     
    @_optimize(speed)
    private static func scan(_ bytes: UnsafeBufferPointer<UInt8>) -> [Int]? {
        var start = 0
        var end = 0
        while end < bytes.count, bytes[end] != UInt8(ascii: "\n") { end += 1 }
         
        guard let colon = bytes[start..<end].firstIndex(of: UInt8(ascii: ":")) else { return nil }
        var after = colon + 1
        while after < end, bytes[after] == UInt8(ascii: " ") || bytes[after] == UInt8(ascii: "\t") || bytes[after] == UInt8(ascii: "\r") {
            after += 1
        }
        guard after == end || bytes[after] == UInt8(ascii: "#") else { return nil }
        var indent: Int?
        var starts: [Int] = []
        start = end + 1
        while start < bytes.count {
            end = start
            while end < bytes.count, bytes[end] != UInt8(ascii: "\n") { end += 1 }
            var spaces = start
            while spaces < end, bytes[spaces] == UInt8(ascii: " ") { spaces += 1 }
            if spaces < end, bytes[spaces] == UInt8(ascii: "-"),
               spaces + 1 == end || bytes[spaces + 1] == UInt8(ascii: " ") || bytes[spaces + 1] == UInt8(ascii: "\r") {
                let column = spaces - start
                if indent == nil { indent = column }
                if column == indent { starts.append(start) }
            }
            start = end + 1
        }
        return indent == nil ? nil : starts
    }
}
