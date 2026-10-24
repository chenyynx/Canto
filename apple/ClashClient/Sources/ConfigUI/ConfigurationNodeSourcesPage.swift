#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
@MainActor
final class ConfigurationNodeSourcesModel: ObservableObject {
     
    enum Kind: CaseIterable {
        case profileURL, file, customNodes, chain, existingProfile

        var title: String {
            switch self {
            case .profileURL: "From Profile URLs"
            case .file: "From Files"
            case .customNodes: "Custom Nodes"
            case .chain: "Proxy Chains"
            case .existingProfile: "Existing Profiles"
            }
        }

        static func of(_ record: ConfigurationSourceRecord) -> Kind {
            if record.nodeChain != nil { return .chain }
            switch record.origin {
            case .subscription: return .profileURL
            case .file, .bundled: return .file
            case .customNodes: return .customNodes
            }
        }
    }

    struct SourceRow: Identifiable, Equatable {
        let id: String
        let label: String
        var detail: String?
        var isOn: Bool
        var kind: Kind
    }

     
    struct Node: Hashable {
        let name: String
        let type: String
    }

     
    struct NodeGroup: Identifiable, Equatable {
        let id: String
        let label: String
        let nodes: [Node]
        let providers: [Node]
    }

    @Published private(set) var rows: [SourceRow] = []
    @Published private(set) var groups: [NodeGroup] = []
    @Published private(set) var busy = false
    @Published var failure: String?
     
     
    private(set) var library = ConfigurationLibrarySnapshot()
     
     
    private var legacy: [String: ConfigurationSourcePayload] = [:]
    private var scopes: [String: ConfigurationNodeScope] = [:]
    let model: ProfilesViewModel
    let profileID: String
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?

    init(model: ProfilesViewModel, profileID: String, libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)? = nil) {
        self.model = model
        self.profileID = profileID
        self.libraryChanged = libraryChanged
    }

    func load() async {
        do {
            guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
            let snapshot = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
            library = snapshot
            guard let recipe = snapshot.recipes.first(where: { $0.id == profileID }) else {
                rows = []; groups = []; return
            }
            let selected = recipe.sources.map(\.id)
            scopes = recipe.nodeScopes ?? [:]
            let records = snapshot.sources.filter {
                $0.suppliesNodes && ($0.isListedInLibrary || selected.contains($0.id))
            }
            var rows = records.map { record in
                SourceRow(id: record.id, label: record.label,
                          detail: Self.summary(nodes: record.nodeCount, providers: record.providerCount),
                          isOn: selected.contains(record.id), kind: Kind.of(record))
            }
             
             
            let known = Set(snapshot.sources.map(\.id))
            let older = (try? await model.configurationLegacyNodeSources(in: snapshot)) ?? [:]
            legacy = [:]
            for (owner, payload) in older where owner != profileID {
                let id = "legacy-" + owner
                guard !known.contains(id), payload.record.nodeCount > 0 || payload.record.providerCount > 0 else { continue }
                legacy[id] = payload
                let label = model.profiles.first { $0.id == owner }?.label ?? payload.record.label
                rows.append(SourceRow(id: id, label: label,
                                      detail: Self.summary(nodes: payload.record.nodeCount, providers: payload.record.providerCount),
                                      isOn: false, kind: .existingProfile))
            }
            self.rows = rows.sorted { lhs, rhs in
                lhs.kind == rhs.kind ? false : Kind.allCases.firstIndex(of: lhs.kind)! < Kind.allCases.firstIndex(of: rhs.kind)!
            }
            let scopes = self.scopes
            let ordered = selected.compactMap { id in snapshot.sources.first { $0.id == id } }
            groups = try await Task.detached(priority: .userInitiated) {
                try ordered.map { record in try Self.group(of: record, scope: scopes[record.id], in: store) }
            }.value
        } catch {
            failure = error.localizedDescription
        }
    }

     
     
    func canTurnOff(_ id: String) -> Bool {
        guard rows.first(where: { $0.id == id })?.isOn == true else { return true }
        return rows.filter(\.isOn).count > 1
    }

     
    func scope(of id: String) -> ConfigurationNodeScope? { scopes[id] }

    func record(of id: String) -> ConfigurationSourceRecord? { library.sources.first { $0.id == id } }

    func set(_ id: String, on: Bool) async {
        if !on, !canTurnOff(id) { return }
        if on, let payload = legacy[id] {
            await edit { draft in Self.accept(payload, into: &draft) }
            return
        }
        await edit { draft in
            if on { if !draft.selectedSourceIDs.contains(id) { draft.selectedSourceIDs.append(id) } }
            else { draft.selectedSourceIDs.removeAll { $0 == id } }
        }
    }

     
     
    func setScope(_ id: String, _ scope: ConfigurationNodeScope?) async {
        if scope?.isEmpty == true, !canTurnOff(id) {
            failure = ClashCopy.string("At least one node source stays on.", locale: AppPreferences.language().locale)
            return
        }
        await edit { draft in
            var scopes = draft.nodeScopes ?? [:]
            scopes[id] = scope?.isEmpty == true ? nil : scope
            draft.nodeScopes = scopes.isEmpty ? nil : scopes
            if scope?.isEmpty == true { draft.selectedSourceIDs.removeAll { $0 == id } }
            else if !draft.selectedSourceIDs.contains(id) { draft.selectedSourceIDs.append(id) }
        }
    }

     
     
    func add(_ payload: ConfigurationSourcePayload) async throws {
        try await perform { draft in draft.add(payload, rule: nil) }
        await load()
    }

     

    private func edit(_ change: @escaping (inout ConfigurationCreationDraft) -> Void) async {
        do { try await perform(change) } catch {
            failure = error.localizedDescription
            clashLogConfigurationWriteFailure(error)
        }
        await load()
    }

     
     
    private func perform(_ change: @escaping (inout ConfigurationCreationDraft) -> Void) async throws {
        guard !busy else { throw ConfigurationLibraryError.busy }
        busy = true
        failure = nil
        defer { busy = false }
        guard let store = model.configurationLibraryStore else { throw ConfigurationLibraryError.unreadable }
        let snapshot = try await Task.detached(priority: .userInitiated) { try store.snapshot() }.value
        guard let recipe = snapshot.recipes.first(where: { $0.id == profileID }) else { return }
        let label = model.profiles.first { $0.id == profileID }?.label ?? recipe.label
        let before = ConfigurationCreationAdapter.editingDraft(recipe: recipe, label: label)
        var draft = before
        change(&draft)
        guard draft != before else { return }
        try await model.editConfiguration(draft, id: profileID, generation: snapshot.generation)
        if let libraryChanged,
           let saved = try? await Task.detached(priority: .userInitiated, operation: { try store.snapshot() }).value {
            libraryChanged(saved)
        }
    }

     

    nonisolated static func summary(nodes: Int, providers: Int) -> String {
        let locale = AppPreferences.language().locale
        return providers > 0
            ? String(format: ClashCopy.string("%@ nodes · %@ providers", locale: locale), "\(nodes)", "\(providers)")
            : String(format: ClashCopy.string("%@ nodes", locale: locale), "\(nodes)")
    }

     
     
    private static func accept(_ payload: ConfigurationSourcePayload, into draft: inout ConfigurationCreationDraft) {
        let hasRules = payload.record.hasRules && payload.record.registersSuppliedRules != false
        let rule: ConfigurationRuleScheme? = hasRules
            ? .init(id: "rules-" + payload.record.id, label: payload.record.label, kind: .supplied, sourceID: payload.record.id) : nil
        draft.add(payload, rule: rule)
    }

     
     
     
    nonisolated static func group(of record: ConfigurationSourceRecord, scope: ConfigurationNodeScope?,
                                  in store: ConfigurationLibraryStore) throws -> NodeGroup {
        let group = try ConfigurationSourceContents.group(of: record, scope: scope, in: store)
        return NodeGroup(id: group.id, label: group.label,
                         nodes: group.nodes.map { Node(name: $0.name, type: $0.type) },
                         providers: group.providers.map { Node(name: $0.name, type: $0.type) })
    }
}

 
 
 
 
 
 
struct ConfigurationNodeSourcesPage: View {
    @ObservedObject var model: ProfilesViewModel
    let section: ConfigurationOutlineSection
    @StateObject private var sources: ConfigurationNodeSourcesModel
    @State private var adding = false
    @State private var managing = false
    @State private var scoping: ScopeTarget?
     
    @State private var keepsOneSource = false
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

     
    private struct ScopeTarget: Identifiable {
        let record: ConfigurationSourceRecord
        let scope: ConfigurationNodeScope?
        var id: String { record.id }
    }

    init(model: ProfilesViewModel, profileID: String, section: ConfigurationOutlineSection = .proxies,
         libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)? = nil) {
        self.model = model
        self.section = section
        _sources = StateObject(wrappedValue: ConfigurationNodeSourcesModel(model: model, profileID: profileID,
                                                                           libraryChanged: libraryChanged))
    }

    var body: some View {
         
        let nodeTypes = ConfigurationTypeWords.names(.proxies, copy: fieldCopy, locale: locale)
        let providerTypes = ConfigurationTypeWords.names(.proxyProviders, copy: fieldCopy, locale: locale)
        List {
            if let failure = sources.failure {
                Section { Text(verbatim: failure).foregroundStyle(.red) }
            }
            ForEach(ConfigurationNodeSourcesModel.Kind.allCases, id: \.self) { kind in
                let items = sources.rows.filter { $0.kind == kind }
                if !items.isEmpty {
                    Section {
                        ForEach(items) { row in sourceToggle(row) }
                    } header: {
                        Text(clash: .copy(kind.title))
                    }
                }
            }
            Section {
                Button { managing = true } label: { Text(clash: .copy("Manage Node Sources")) }
                    .accessibilityIdentifier("configuration-editor.sources.manage")
            } footer: {
                if sources.rows.filter(\.isOn).count == 1 {
                    Text(clash: .copy("At least one node source stays on."))
                }
            }
            ForEach(sources.groups) { group in
                Section {
                    if section != .proxyProviders {
                        ForEach(group.nodes, id: \.self) { node in
                            ConfigurationRowLabel(title: .verbatim(node.name),
                                                  value: .verbatim(ConfigurationTypeWords.word(node.type, in: nodeTypes)))
                                .accessibilityIdentifier("configuration-editor.sources.node.\(node.name)")
                        }
                    }
                    ForEach(group.providers, id: \.self) { provider in
                        ConfigurationRowLabel(title: .verbatim(provider.name),
                                              value: .verbatim(ConfigurationTypeWords.word(provider.type, in: providerTypes)))
                            .accessibilityIdentifier("configuration-editor.sources.provider.\(provider.name)")
                    }
                    if let record = sources.record(of: group.id) {
                        Button { scoping = ScopeTarget(record: record, scope: sources.scope(of: group.id)) } label: {
                            Text(clash: .copy("Select Nodes"))
                        }
                        .accessibilityIdentifier("configuration-editor.sources.scope.\(group.id)")
                    }
                } header: {
                    Text(verbatim: group.label)
                }
            }
        }
        .disabled(sources.busy)
        .navigationTitle(Text(clash: .copy(ConfigurationEditorCopy.title(of: section))))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ControlGroup {
                    Button { adding = true } label: { Image(systemName: ClashSymbol.plus.name) }
                        .accessibilityLabel(Text(clash: .copy("Add Source")))
                        .accessibilityIdentifier("configuration-editor.sources.add")
                }
                .clashReaderControlGroupStyle()
            }
        }
        .task { await sources.load() }
        .alert(Text(clash: .copy("Keep at least one node source")), isPresented: $keepsOneSource) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(clash: .copy("A configuration needs a source for its nodes. Turn on another source first."))
        }
        .sheet(isPresented: $adding, onDismiss: { Task { await sources.load() } }) {
            ConfigurationSourceImportAdapter(model: model, kind: .subscription, choosesKind: true,
                                             finishImport: { adding = false }) { payload in
                try await sources.add(payload)
            }
            .clashModalPresentation(.page)
        }
        .sheet(isPresented: $managing, onDismiss: { Task { await sources.load() } }) {
            ConfigurationSourceLibraryAdapter(model: model, library: sources.library,
                                              changed: { _ in }, close: { managing = false })
                .clashModalPresentation(.page)
        }
        .sheet(item: $scoping) { target in
            ConfigurationNodeScopeAdapter(model: model, source: target.record, staged: nil, initial: target.scope,
                                          save: { scope in
                                              scoping = nil
                                              Task { await sources.setScope(target.record.id, scope) }
                                          }, close: { scoping = nil })
                .clashModalPresentation(.page)
        }
    }

    private func sourceToggle(_ row: ConfigurationNodeSourcesModel.SourceRow) -> some View {
         
         
         
        Toggle(isOn: Binding(get: { row.isOn }, set: { on in
            if !on, !sources.canTurnOff(row.id) { keepsOneSource = true; return }
            Task { await sources.set(row.id, on: on) }
        })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.label)
                if let detail = row.detail {
                    Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityIdentifier("configuration-editor.sources.source.\(row.id)")
    }
}

 
 
 
struct ConfigurationNodeSourcesSheet: View {
    @ObservedObject var model: ProfilesViewModel
    let profileID: String
    var libraryChanged: ((ConfigurationLibrarySnapshot) -> Void)?
    @State private var dismiss = ClashDismissHandle()

    var body: some View {
        ClashFeatureNavigationContainer {
            ConfigurationNodeSourcesPage(model: model, profileID: profileID, section: .proxies, libraryChanged: libraryChanged)
                .navigationTitle(Text(clash: .copy("Node Sources")))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss.closeModalOrDismiss() } label: { Text(clash: .copy("Done")) }
                            .accessibilityIdentifier("configuration-editor.sources.done")
                    }
                }
        }
        .clashCapturesDismiss(dismiss)
    }
}
#endif
