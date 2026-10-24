import ClashClientKit
import ClashClientUI
import SwiftUI
import UniformTypeIdentifiers

 
 
public struct ClashMacScriptEntry: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
     
    public let canRefresh: Bool
     
     
    public let sourceHost: String?
    public init(id: String, label: String, canRefresh: Bool = false, sourceHost: String? = nil) {
        self.id = id
        self.label = label
        self.canRefresh = canRefresh
        self.sourceHost = sourceHost
    }
}

 
public struct ClashMacScriptsState: Equatable, Sendable {
    public var scripts: [ClashMacScriptEntry]
     
    public var selectedID: String?
     
    public var patchFieldCount: Int
     
    public var exceptions: [String]

    public init(scripts: [ClashMacScriptEntry], selectedID: String?, patchFieldCount: Int, exceptions: [String]) {
        self.scripts = scripts
        self.selectedID = selectedID
        self.patchFieldCount = patchFieldCount
        self.exceptions = exceptions
    }

    public static let empty = ClashMacScriptsState(scripts: [], selectedID: nil, patchFieldCount: 0, exceptions: [])
}

 
 
 
public struct ClashMacScriptsActions {
    public var load: @MainActor () async -> ClashMacScriptsState
     
    public var select: @MainActor (String?) async throws -> ClashMacScriptsState
     
    public var addLink: @MainActor (String) async throws -> ClashMacScriptsState
     
    public var addManual: @MainActor (String, String) async throws -> ClashMacScriptsState
    public var remove: @MainActor (String) async throws -> ClashMacScriptsState
     
    public var edit: (@MainActor (String) -> Void)? = nil
     
     
     
     
     
     
    public var refresh: (@MainActor (String) async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation))? = nil
     
     
     
     
    public var updateAll: (@MainActor () async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation))? = nil
     
     
    public var didChange: Notification.Name? = nil
    public var clearPatch: @MainActor () async throws -> ClashMacScriptsState
    public var removeException: @MainActor (Int) async throws -> ClashMacScriptsState

    public init(
        load: @escaping @MainActor () async -> ClashMacScriptsState,
        select: @escaping @MainActor (String?) async throws -> ClashMacScriptsState,
        addLink: @escaping @MainActor (String) async throws -> ClashMacScriptsState,
        addManual: @escaping @MainActor (String, String) async throws -> ClashMacScriptsState,
        remove: @escaping @MainActor (String) async throws -> ClashMacScriptsState,
        clearPatch: @escaping @MainActor () async throws -> ClashMacScriptsState,
        removeException: @escaping @MainActor (Int) async throws -> ClashMacScriptsState,
        refresh: (@MainActor (String) async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation))? = nil,
        updateAll: (@MainActor () async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation))? = nil
    ) {
        self.load = load
        self.select = select
        self.addLink = addLink
        self.addManual = addManual
        self.remove = remove
        self.clearPatch = clearPatch
        self.removeException = removeException
        self.refresh = refresh
        self.updateAll = updateAll
    }

    public static var unavailable: ClashMacScriptsActions {
        ClashMacScriptsActions(
            load: { .empty },
            select: { _ in throw ConfigurationLibraryError.unreadable },
            addLink: { _ in throw ConfigurationLibraryError.unreadable },
            addManual: { _, _ in throw ConfigurationLibraryError.unreadable },
            remove: { _ in throw ConfigurationLibraryError.unreadable },
            clearPatch: { throw ConfigurationLibraryError.unreadable },
            removeException: { _ in throw ConfigurationLibraryError.unreadable }
        )
    }
}

 
 
 
 
public struct ClashMacScriptsPage: View {
    private let actions: ClashMacScriptsActions
    @State private var state: ClashMacScriptsState
    @State private var loaded = false
    @State private var busy = false
    @State private var error: String?
    @State private var adding = false
     
     
     
    @Environment(\.clashFeedback) private var feedback
    @Environment(\.locale) private var locale

     
     
     
     
     
    private let quickAdd: ((@escaping @MainActor () -> Void) -> AnyView)?

    public init(
        actions: ClashMacScriptsActions,
        initial: ClashMacScriptsState = .empty,
        quickAdd: ((@escaping @MainActor () -> Void) -> AnyView)? = nil
    ) {
        self.quickAdd = quickAdd
        self.actions = actions
        _state = State(initialValue: initial)
    }

     
     
    private func scriptRow(_ script: ClashMacScriptEntry) -> some View {
        LabeledContent {
            EmptyView()
        } label: {
            Text(verbatim: script.label)
             
             
            Text(clash: script.sourceHost.map { .format("From %@", [$0]) } ?? .copy("Manual"))
        }
        .contextMenu {
            if let edit = actions.edit {
                Button { edit(script.id) } label: { Text(clash: .copy("Edit")) }
            }
            if script.canRefresh, let refresh = actions.refresh {
                Button { runUpdate(script.label) { try await refresh(script.id) } } label: { Text(clash: .copy("Update")) }
            }
            if actions.edit != nil || (script.canRefresh && actions.refresh != nil) { Divider() }
             
            Button(role: .destructive) { perform { try await actions.remove(script.id) } } label: { Text(clash: .copy("Delete")) }
        }
        .disabled(busy)
         
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(state.selectedID == script.id ? .isSelected : [])
        .accessibilityIdentifier("configuration-center.scripts.row.\(script.id)")
    }

    public var body: some View {
         
         
         
         
         
         
        let chosen = state.scripts.first { $0.id == state.selectedID }
        let others = state.scripts.filter { $0.id != state.selectedID }
        List {
            if !state.scripts.isEmpty {
                Section {
                     
                    Picker(selection: Binding<String?>(
                        get: { chosen?.id },
                        set: { id in
                            guard id != chosen?.id else { return }
                            perform { try await actions.select(id) }
                        }
                    )) {
                        Text(clash: .copy("None")).tag(String?.none)
                        ForEach(state.scripts) { script in
                            Text(verbatim: script.label).tag(String?.some(script.id))
                        }
                    } label: {
                        Text(clash: .copy("Script"))
                    }
                    .pickerStyle(.menu)
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.scripts.selected")
                    if let chosen { scriptRow(chosen) }
                }
            }
            if !others.isEmpty {
                Section {
                    ForEach(others) { script in
                        scriptRow(script)
                    }
                } header: {
                     
                    Text(clash: chosen == nil ? .copy("Scripts") : .copy("Other Scripts"))
                        .accessibilityIdentifier("configuration-center.scripts.other")
                }
            }
            if state.scripts.isEmpty {
                Section {
                    Text(clash: .copy("None")).foregroundStyle(.secondary)
                } header: {
                    Text(clash: .copy("Scripts"))
                }
            }
            if let quickAdd {
                quickAdd { Task { @MainActor in state = await actions.load() } }
            }
             
             
             
            Section {
                 
                 
                 
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        if let updateAll = actions.updateAll {
                            Button {
                                runUpdate(nil) { try await updateAll() }
                            } label: { Text(clash: .copy("Update All")) }
                            .disabled(busy)
                            .accessibilityIdentifier("configuration-center.scripts.update-all")
                        }
                        Spacer()
                         
                         
                         
                         
                        Button { adding = true } label: { Text(clash: .opens("quick-add.door.create", locale: locale)) }
                            .disabled(busy)
                            .accessibilityIdentifier("configuration-center.scripts.add")
                    }
                    if let feedback {
                        ClashMacFeedbackSlot(center: feedback, operations: [Self.updateOperation])
                    }
                }
                 
                .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            }
             
             
             
            if let error {
                Section {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration-center.scripts.error")
                }
            }
        }
        .listStyle(.inset)
        .task {
            guard !loaded else { return }
            loaded = true
            state = await actions.load()
        }
        .sheet(isPresented: $adding) {
            ClashMacScriptAddSheet(
                addLink: { link in try await apply { try await actions.addLink(link) } },
                addManual: { name, body in try await apply { try await actions.addManual(name, body) } },
                close: { adding = false }
            )
            .clashModalPresentation(.fitted)
        }
         
         
         
        .onReceive(NotificationCenter.default.publisher(for: actions.didChange ?? Notification.Name("clash.scripts.unobserved"))
            .receive(on: DispatchQueue.main)) { _ in
            Task { @MainActor in state = await actions.load() }
        }
        .clashFrameWatch("configuration-scripts")
        .accessibilityIdentifier("configuration-center.scripts")
    }

    private func perform(_ operation: @escaping () async throws -> ClashMacScriptsState) {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do { state = try await operation() } catch { self.error = ClashErrorCopy.message(error, locale: locale) }
        }
    }

    static let updateOperation = "scripts.update"

     
     
     
    private func runUpdate(_ name: String?,
                           _ operation: @escaping () async throws -> (state: ClashMacScriptsState, result: ClashFeedbackPresentation)) {
        guard !busy else { return }
        busy = true
        error = nil
        let running = feedback?.say(.loading(title: ClashFeedbackCopy.updating, accessibilityIdentifier: "feedback.scripts.update.running"),
                                     operation: Self.updateOperation)
        Task { @MainActor in
            defer { busy = false }
            do {
                let outcome = try await operation()
                state = outcome.state
                if let running, feedback?.update(running, to: outcome.result) == true {} else {
                    feedback?.say(outcome.result, operation: Self.updateOperation)
                }
            } catch {
                 
                 
                 
                let reason = ClashErrorCopy.message(error, locale: locale)
                guard let feedback else { self.error = reason; return }
                let failed = name.map { ClashMacFeedbackSentences.couldNotUpdate($0, reason: reason, id: Self.updateOperation) }
                    ?? ClashMacFeedbackSentences.couldNotUpdateScripts(reason: reason, id: Self.updateOperation)
                if let running, feedback.update(running, to: failed) {} else {
                    feedback.say(failed, operation: Self.updateOperation)
                }
            }
        }
    }

     
     
    private func apply(_ operation: @escaping () async throws -> ClashMacScriptsState) async throws {
        state = try await operation()
        adding = false
    }
}

 
 
 
 
struct ClashMacScriptAddSheet: View {
    enum Tab: Int, CaseIterable, Identifiable {
        case link, file, manual
        var id: Int { rawValue }
        var title: String {
            switch self {
            case .link: "URL"
            case .file: "File"
             
            case .manual: "quick-add.door.create"
            }
        }
    }

    let addLink: (String) async throws -> Void
    let addManual: (String, String) async throws -> Void
    let close: () -> Void
    @Environment(\.locale) private var locale
     
     
    @State private var tab: Tab = .manual
    @State private var link = ""
    @State private var name = ""
    @State private var scriptBody = ""
    @State private var choosingFile = false
    @State private var busy = false
    @State private var error: String?

    private var canAdd: Bool {
        switch tab {
        case .link: !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !busy
        case .file, .manual: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !scriptBody.isEmpty && !busy
        }
    }

    var body: some View {
        ClashMacSheetFrame(title: .copy("Add Script"), subtitle: .copy("Scripts"), width: 560, height: 500) {
            VStack(spacing: 0) {
                Picker(selection: $tab) {
                    ForEach(Tab.allCases) { item in Text(clash: .copy(item.title)).tag(item) }
                } label: {
                    Text(clash: .copy("Add Script"))
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .padding(.top, 16)
                .accessibilityIdentifier("configuration-center.script-add.tabs")
                ClashMacSheetForm {
                    switch tab {
                    case .link:
                        Section {
                            TextField(text: $link, prompt: Text(verbatim: "https://")) { Text(clash: .copy("URL")) }
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.script-add.link")
                        }
                    case .file:
                        Section {
                            LabeledContent {
                                Button { choosingFile = true } label: { Text(clash: .copy("Choose File")) }
                                    .disabled(busy)
                                    .accessibilityIdentifier("configuration-center.script-add.choose-file")
                            } label: {
                                Text(clash: name.isEmpty ? .copy("File") : .verbatim(name))
                            }
                            TextField(text: $name, prompt: Text(clash: .copy("Name"))) { Text(clash: .copy("Name")) }
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.script-add.file-name")
                        }
                    case .manual:
                        Section {
                            TextField(text: $name, prompt: Text(clash: .copy("New Script"))) { Text(clash: .copy("Name")) }
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.script-add.name")
                            TextEditor(text: $scriptBody)
                                .font(.body.monospaced())
                                .frame(minHeight: 180)
                                .disabled(busy)
                                .accessibilityLabel(Text(clash: .copy("Script")))
                                .accessibilityIdentifier("configuration-center.script-add.body")
                        }
                    }
                    if let error {
                        Section {
                            Text(verbatim: error).foregroundStyle(.red)
                                .accessibilityIdentifier("configuration-center.script-add.error")
                        }
                    }
                }
                .accessibilityIdentifier("configuration-center.script-add")
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.script-add.cancel",
                primaryTitle: .copy("Add"),
                primaryIdentifier: "configuration-center.script-add.add",
                primaryDisabled: !canAdd,
                isBusy: busy,
                onClose: close,
                onPrimary: add
            )
        }
        .onChange(of: tab) { _ in error = nil }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.plainText, .text, .javaScript].compactMap { $0 }) { result in
            switch result {
            case .success(let picked):
                let scoped = picked.startAccessingSecurityScopedResource()
                defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
                do {
                    scriptBody = try String(contentsOf: picked, encoding: .utf8)
                    if name.isEmpty { name = picked.deletingPathExtension().lastPathComponent }
                    error = nil
                } catch {
                    self.error = ClashErrorCopy.message(error, locale: locale)
                }
            case .failure(let failure):
                error = ClashErrorCopy.message(failure, locale: locale)
            }
        }
    }

    private func add() {
        guard canAdd else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                switch tab {
                case .link: try await addLink(link.trimmingCharacters(in: .whitespacesAndNewlines))
                case .file, .manual: try await addManual(name.trimmingCharacters(in: .whitespacesAndNewlines), scriptBody)
                }
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }
}
