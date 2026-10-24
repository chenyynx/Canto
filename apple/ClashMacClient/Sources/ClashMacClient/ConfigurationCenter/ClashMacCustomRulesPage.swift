import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
public struct ClashMacCustomRule: Identifiable, Equatable, Sendable {
    public var text: String
    public var isEnabled: Bool
    public var comment: String?
    public var id: String { text }

    public init(text: String, isEnabled: Bool = true, comment: String? = nil) {
        self.text = text; self.isEnabled = isEnabled; self.comment = comment
    }
}

public struct ClashMacCustomRulesState: Equatable, Sendable {
    public var rules: [ClashMacCustomRule]
     
     
    public var prepends: Bool

    public init(rules: [ClashMacCustomRule], prepends: Bool) { self.rules = rules; self.prepends = prepends }
    public static let empty = ClashMacCustomRulesState(rules: [], prepends: true)
}

 
 
 
public struct ClashMacCustomRulesActions {
    public var load: @MainActor () async -> ClashMacCustomRulesState
     
    public var save: @MainActor ([ClashMacCustomRule]) async throws -> ClashMacCustomRulesState
    public var setPrepends: @MainActor (Bool) async throws -> ClashMacCustomRulesState
     
     
     
     
    public var targets: @MainActor () async throws -> ConfigurationRuleTargetCandidates
     
     
    public var geoValues: ClashMacGeoValueLoader
     
     
     
    public var targetSearch: ClashRuleTargetSearchHook?

    public init(
        load: @escaping @MainActor () async -> ClashMacCustomRulesState,
        save: @escaping @MainActor ([ClashMacCustomRule]) async throws -> ClashMacCustomRulesState,
        setPrepends: @escaping @MainActor (Bool) async throws -> ClashMacCustomRulesState,
        targets: @escaping @MainActor () async throws -> ConfigurationRuleTargetCandidates,
        geoValues: @escaping ClashMacGeoValueLoader = { _ in [] },
        targetSearch: ClashRuleTargetSearchHook? = nil
    ) {
        self.load = load; self.save = save; self.setPrepends = setPrepends; self.targets = targets; self.geoValues = geoValues
        self.targetSearch = targetSearch
    }
}

 
 
 
 
 
public struct ClashMacCustomRulesPage: View {
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale
    let actions: ClashMacCustomRulesActions
    @State private var state: ClashMacCustomRulesState
    @State private var adding = false
    @State private var busy = false
    @State private var error: String?

    public init(actions: ClashMacCustomRulesActions, initial: ClashMacCustomRulesState = .empty) {
        self.actions = actions
        _state = State(initialValue: initial)
    }

    public var body: some View {
        List {
            Section {
                ForEach(state.rules) { rule in
                    Toggle(isOn: Binding(get: { rule.isEnabled }, set: { on in setEnabled(rule, on) })) {
                        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                             
                             
                            ConfigurationRuleRow(rule.text, showsChevron: false)
                            if let comment = rule.comment, !comment.isEmpty {
                                Text(verbatim: comment).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .disabled(busy)
                    .contextMenu {
                        Button(role: .destructive) { remove(rule) } label: { Text(clash: .copy("Delete")) }
                            .accessibilityIdentifier("configuration-center.custom-rules.delete")
                    }
                    .accessibilityIdentifier("configuration-center.custom-rules.rule.\(rule.text)")
                }
                .onMove { offsets, destination in
                    var rules = state.rules
                    rules.move(fromOffsets: offsets, toOffset: destination)
                    perform { try await actions.save(rules) }
                }
                Button { adding = true } label: { Label { Text(clash: .copy("Add Rule")) } icon: { Image(systemName: "plus") } }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.custom-rules.add")
            } footer: {
                Text(clash: state.prepends
                    ? .copy("These rules are added in front of the configuration's own rules when it is used.")
                    : .copy("These rules are added after the configuration's own rules when it is used."))
            }
            Section {
                Toggle(isOn: Binding(get: { state.prepends }, set: { on in perform { try await actions.setPrepends(on) } })) {
                    Text(clash: .copy("Insert before profile URL rules"))
                }
                .toggleStyle(.switch)
                .disabled(busy)
                .accessibilityIdentifier("configuration-center.custom-rules.prepend")
            }
            if let error {
                Section {
                    Text(verbatim: error).foregroundStyle(.red)
                        .accessibilityIdentifier("configuration-center.custom-rules.error")
                }
            }
        }
         
         
        .listStyle(.inset)
        .accessibilityIdentifier("configuration-center.custom-rules")
        .task { state = await actions.load() }
        .sheet(isPresented: $adding) {
            ClashMacAddRuleSheet(
                targets: actions.targets,
                geoValues: actions.geoValues,
                add: { rule in
                    let next = try await actions.save(state.rules + [rule])
                    state = next
                },
                close: { adding = false }
            )
            .environment(\.clashRuleTargetSearch, actions.targetSearch)
            .clashModalPresentation(.fitted)
        }
    }

    private func setEnabled(_ rule: ClashMacCustomRule, _ on: Bool) {
        var rules = state.rules
        guard let index = rules.firstIndex(of: rule) else { return }
        rules[index].isEnabled = on
        perform { try await actions.save(rules) }
    }

    private func remove(_ rule: ClashMacCustomRule) {
        perform { try await actions.save(state.rules.filter { $0 != rule }) }
    }

    private func perform(_ operation: @escaping () async throws -> ClashMacCustomRulesState) {
        guard !busy else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do { state = try await operation() } catch { self.error = ClashErrorCopy.message(error, locale: locale) }
        }
    }
}

 
 
 
struct ClashMacAddRuleSheet: View {
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale
    let targets: @MainActor () async throws -> ConfigurationRuleTargetCandidates
    let geoValues: ClashMacGeoValueLoader
    let add: @MainActor (ClashMacCustomRule) async throws -> Void
    let close: () -> Void
    @State private var action: ClashStructuredRule.Action = .domainSuffix
    @Environment(\.clashMacEditorSyntax) private var syntax
    @State private var content = ""
     
    @State private var pickingGeo = false
     
     
    @State private var pickedFrom: ClashMacGeoResource?
    @State private var target = "DIRECT"
    @State private var candidates = ConfigurationRuleTargetCandidates.make(groups: [], sources: [])
    @State private var pickingTarget = false
    @State private var enabled = true
    @State private var comment = ""
    @State private var busy = false
    @State private var error: String?

    private var assembled: String {
        var parts = [action.rawValue]
        if action.needsContent { parts.append(content.trimmingCharacters(in: .whitespacesAndNewlines)) }
        parts.append(target)
        return parts.joined(separator: ",")
    }

    private var canAdd: Bool {
        (!action.needsContent || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) && !busy && !pickingGeo && !pickingTarget
    }

    private var title: ClashDisplayText {
        if pickingGeo, let resource = action.clashMacGeoResource { return resource.rowTitle }
        if pickingTarget { return .copy("Target") }
        return .copy("Add Rule")
    }

    var body: some View {
        ClashMacSheetFrame(title: title, width: 520, height: 440) {
            if pickingGeo, let resource = action.clashMacGeoResource {
                ClashMacGeoValuePickerPage(
                    resource: resource, current: content, load: geoValues,
                    identifier: "configuration-center.custom-rules.form.geo"
                ) { picked in
                    content = picked
                    pickedFrom = resource
                    pickingGeo = false
                }
            } else if pickingTarget {
                ClashMacTargetPickerPage(
                    candidates: candidates, current: target,
                    identifier: "configuration-center.custom-rules.form.target"
                ) { picked in
                    target = picked
                    pickingTarget = false
                }
            } else {
                form
            }
        } leading: {
            if pickingGeo {
                Button { pickingGeo = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.custom-rules.form.geo.back")
            } else if pickingTarget {
                Button { pickingTarget = false } label: { Text(clash: .copy("Back")) }
                    .accessibilityIdentifier("configuration-center.custom-rules.form.target.back")
            }
        } trailing: {
            ClashMacSheetButtons(
                closeTitle: .copy("Cancel"),
                closeIdentifier: "configuration-center.custom-rules.form.cancel",
                primaryTitle: .copy("Add"),
                primaryIdentifier: "configuration-center.custom-rules.form.add",
                primaryDisabled: !canAdd,
                isBusy: busy,
                onClose: close,
                onPrimary: submit
            )
        }
        .onChange(of: action) { changed in
             
             
            if changed.clashMacGeoResource != pickedFrom { content = ""; pickedFrom = nil }
        }
    }

    private var form: some View {
            ClashMacSheetForm {
                Section {
                    Picker(selection: $action) {
                        ForEach(ClashMacRuleRowEditor.offeredActions(syntax, keeping: action), id: \.self) { item in
                            Text(verbatim: ConfigurationRuleWords.kindName(item.rawValue, locale: locale, copy: copy)).tag(item)
                        }
                    } label: {
                        Text(clash: .copy("Rule Type"))
                    }
                    .disabled(busy)
                    .accessibilityIdentifier("configuration-center.custom-rules.form.action")
                    if let resource = action.clashMacGeoResource {
                         
                        ClashMacGeoValueRow(resource: resource, value: content, identifier: "configuration-center.custom-rules.form.geo") {
                            pickingGeo = true
                        }
                        .disabled(busy)
                    } else if action.needsContent {
                        LabeledContent {
                            TextField(text: $content, prompt: Text(verbatim: action.contentPlaceholder)) { Text(clash: .copy(action.contentLabel)) }
                                .labelsHidden()
                                .font(.body.monospaced())
                                .multilineTextAlignment(.trailing)
                                .disabled(busy)
                                .accessibilityIdentifier("configuration-center.custom-rules.form.content")
                        } label: {
                            Text(clash: .copy(action.contentLabel))
                        }
                    }
                     
                     
                    ClashMacTargetRow(title: .copy("Target"), value: target, identifier: "configuration-center.custom-rules.form.target") {
                        pickingTarget = true
                    }
                    .disabled(busy)
                    Toggle(isOn: $enabled) { Text(clash: .copy("Enabled")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.custom-rules.form.enabled")
                    TextField(text: $comment) { Text(clash: .copy("Comment")) }
                        .disabled(busy)
                        .accessibilityIdentifier("configuration-center.custom-rules.form.comment")
                     
                    Text(clash: .format("Written as %@ in the configuration file", [assembled]))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let error {
                    Section {
                        Text(verbatim: error).foregroundStyle(.red)
                            .accessibilityIdentifier("configuration-center.custom-rules.form.error")
                    }
                }
            }
            .task {
                if let loaded = try? await targets(), !loaded.names.isEmpty {
                    candidates = loaded
                    if !loaded.contains(target) { target = loaded.names[0] }
                }
            }
    }

    private func submit() {
        guard canAdd else { return }
        busy = true
        error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                try await add(ClashMacCustomRule(text: assembled, isEnabled: enabled, comment: trimmed.isEmpty ? nil : trimmed))
                close()
            } catch {
                self.error = ClashErrorCopy.message(error, locale: locale)
            }
        }
    }
}
