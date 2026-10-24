import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
public struct ClashMacChainChoice: Identifiable, Sendable, Equatable {
    public let hop: ConfigurationNodeChain.Hop
    public let sourceLabel: String
    public var id: String { hop.source.id + "/" + hop.nodeName }
    public init(hop: ConfigurationNodeChain.Hop, sourceLabel: String) { self.hop = hop; self.sourceLabel = sourceLabel }
}

public struct ClashMacChainSheetActions {
     
    public var loadChoices: @MainActor () async throws -> [ClashMacChainChoice]
     
    public var commit: @MainActor (String, ConfigurationNodeChain.Hop, ConfigurationNodeChain.Hop) async throws -> Void

    public init(
        loadChoices: @escaping @MainActor () async throws -> [ClashMacChainChoice],
        commit: @escaping @MainActor (String, ConfigurationNodeChain.Hop, ConfigurationNodeChain.Hop) async throws -> Void
    ) {
        self.loadChoices = loadChoices; self.commit = commit
    }

    public static var unavailable: Self { Self(loadChoices: { [] }, commit: { _, _, _ in throw ConfigurationLibraryError.unreadable }) }
}

 
 
 
 
 
 
 
public struct ClashMacChainSheet: View {
    private enum Slot { case entry, exit }
    private let existing: ConfigurationSourceRecord?
    private let actions: ClashMacChainSheetActions
    private let close: () -> Void
    @State private var name: String
    @State private var entry: ConfigurationNodeChain.Hop?
    @State private var exit: ConfigurationNodeChain.Hop?
    @State private var choices: [ClashMacChainChoice]?
    @State private var error: String?
    @State private var busy = false
    @Environment(\.locale) private var locale
    @State private var confirmsDiscard = false
     
    @State private var picking: Slot?
    @State private var query = ""

    public init(existing: ConfigurationSourceRecord?, actions: ClashMacChainSheetActions, close: @escaping () -> Void) {
        self.existing = existing; self.actions = actions; self.close = close
        _name = State(initialValue: existing?.label ?? "")
        _entry = State(initialValue: existing?.nodeChain?.entry)
        _exit = State(initialValue: existing?.nodeChain?.exit)
    }

    private var dirty: Bool {
        name != (existing?.label ?? "") || entry != existing?.nodeChain?.entry || exit != existing?.nodeChain?.exit
    }
    private var canCommit: Bool { entry != nil && exit != nil && entry != exit && !busy && choices != nil && picking == nil }

    private var title: ClashDisplayText {
        switch picking {
        case .entry: .copy("Entry Node")
        case .exit: .copy("Exit Node")
        case nil: existing == nil ? .copy("Add Proxy Chain") : .copy("Edit Proxy Chain")
        }
    }

    public var body: some View {
        ClashMacSheetFrame(title: title, width: 560, height: 460) {
            if let picking {
                nodePicker(picking)
            } else {
                form
            }
        } leading: {
            if picking != nil {
                Button { picking = nil } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.chain.back")
            } else if let error {
                Text(verbatim: error).foregroundStyle(.red).font(.subheadline).lineLimit(2)
                    .accessibilityIdentifier("configuration-center.chain.error")
            }
        } trailing: {
            ClashMacSheetButtons(
                closeIdentifier: "configuration-center.chain.cancel",
                primaryTitle: existing == nil ? .copy("Add") : .copy("Done"),
                primaryIdentifier: "configuration-center.chain.done",
                primaryDisabled: !canCommit,
                isBusy: busy,
                onClose: { if dirty { confirmsDiscard = true } else { close() } },
                onPrimary: commit
            )
        }
        .task { if choices == nil { await load() } }
        .alert(Text(clash: .copy("Discard Changes")), isPresented: $confirmsDiscard) {
            Button(role: .destructive) { close() } label: { Text(clash: .copy("Discard Changes")) }
            Button(role: .cancel) {} label: { Text(clash: .copy("Cancel")) }
        } message: {
            Text(clash: .copy("This proxy chain has unsaved changes."))
        }
    }

     
    static func sourceGroups(_ choices: [ClashMacChainChoice]) -> [(label: String, choices: [ClashMacChainChoice])] {
        var order: [String] = []
        var grouped: [String: [ClashMacChainChoice]] = [:]
        for choice in choices {
            if grouped[choice.sourceLabel] == nil { order.append(choice.sourceLabel) }
            grouped[choice.sourceLabel, default: []].append(choice)
        }
        return order.map { (label: $0, choices: grouped[$0] ?? []) }
    }

    private var form: some View {
        ClashMacSheetForm {
            Section {
                TextField(text: $name, prompt: Text(clash: .copy("Entry → Exit"))) { Text(clash: .copy("Name")) }
                    .accessibilityIdentifier("configuration-center.chain.name")
            }
            Section {
                 
                 
                 
                Text(clash: .copy("This Device"))
                hopRow(.copy("Entry Node"), hop: entry, slot: .entry, identifier: "configuration-center.chain.entry")
                hopRow(.copy("Exit Node"), hop: exit, slot: .exit, identifier: "configuration-center.chain.exit")
                Text(clash: .copy("Destination Website"))
            } header: {
                Text(clash: .copy("Connection Order"))
            }
            if let choices, choices.isEmpty {
                Section { Text(clash: .copy("Add nodes to Node Library first.")).foregroundStyle(.secondary) }
            }
        }
    }

     
     
     
    private func hopRow(_ title: ClashDisplayText, hop: ConfigurationNodeChain.Hop?, slot: Slot, identifier: String) -> some View {
         
         
         
        LabeledContent {
            Button { query = ""; picking = slot } label: {
                if let hop {
                    Text(verbatim: hop.nodeName).lineLimit(1).truncationMode(.middle)
                } else {
                    Text(clash: .copy("Choose Node"))
                }
            }
        } label: {
            Label { Text(clash: title) } icon: { Image(systemName: "arrow.down") }
        }
        .disabled(choices == nil || busy)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(Text(verbatim: hop?.nodeName ?? ""))
    }

     
     
    private func nodePicker(_ slot: Slot) -> some View {
        let current = slot == .entry ? entry : exit
        let needle = query.trimmingCharacters(in: .whitespaces)
        let groups = Self.sourceGroups((choices ?? []).filter { choice in
            needle.isEmpty
                || choice.hop.nodeName.localizedCaseInsensitiveContains(needle)
                || choice.sourceLabel.localizedCaseInsensitiveContains(needle)
        })
        return VStack(spacing: 0) {
            TextField(text: $query, prompt: Text(clash: .copy("Search nodes"))) { Text(clash: .copy("Search nodes")) }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityIdentifier("configuration-center.chain.search")
            Divider()
            if groups.isEmpty {
                ClashMacSheetPlaceholder(title: .copy("No results"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("configuration-center.chain.no-results")
            } else {
                List {
                    ForEach(groups, id: \.label) { group in
                        Section {
                            ForEach(group.choices) { choice in
                                Button {
                                    if slot == .entry { entry = choice.hop } else { exit = choice.hop }
                                    picking = nil
                                } label: {
                                    LabeledContent {
                                        if choice.hop == current { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                    } label: {
                                        Text(verbatim: choice.hop.nodeName).lineLimit(1)
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(Text(verbatim: choice.hop.nodeName))
                                .accessibilityIdentifier("configuration-center.chain.pick.\(choice.id)")
                            }
                        } header: {
                            Text(verbatim: group.label)
                        }
                    }
                }
                .clashMacSettingsList(minRowHeight: ClashMacSettingsMetrics.listRowMinHeight)
            }
        }
    }

    private func load() async {
        do { choices = try await actions.loadChoices() } catch { self.error = ClashErrorCopy.message(error, locale: locale); choices = [] }
    }

    private func commit() {
        guard let entry, let exit else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                try await actions.commit(name.trimmingCharacters(in: .whitespacesAndNewlines), entry, exit)
                close()
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }
}
