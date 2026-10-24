import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
public struct ClashMacSettingsKeyRows: View {
    let keys: [String]
    let actions: ClashMacSettingsSectionActions
    @State private var document: ClashMacSettingsSectionDocument?
     
    @State private var loadFailure: String?
     
     
     
    @State private var writeFailures: [String: String] = [:]
    @State private var saving = false
    @State private var editing: ClashMacKeyEdit?
    @State private var pending: [ConfigurationPageEdit]?
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    public init(keys: [String], actions: ClashMacSettingsSectionActions) {
        self.keys = keys
        self.actions = actions
    }

     
    static let customTag = "\u{1F}custom"

    public var body: some View {
        Group {
            if let document {
                ForEach(keys, id: \.self) { key in
                    row(key, in: document)
                    if let reason = writeFailures[key] { ClashMacRowFailure(message: reason) }
                }
            } else if loadFailure == nil {
                ProgressView().controlSize(.small)
            }
            if let loadFailure {
                Text(verbatim: loadFailure).foregroundStyle(.red)
            }
        }
        .task { await reload() }
        .sheet(item: $editing) { edit in
            ClashMacValueEditSheet(edit: edit, save: { value in
                request([.set(path: edit.path, to: value)])
            }, useDefault: edit.removable ? { request([.remove(path: edit.path)]) } : nil, geoValues: actions.geoValues)
        }
        .alert(Text(clash: .copy("Save as your own rule scheme?")), isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button(role: .cancel) { pending = nil } label: { Text(clash: .copy("Cancel")) }
            Button {
                let edits = pending ?? []
                pending = nil
                Task { await save(edits) }
            } label: { Text(clash: .copy("Save")) }
        } message: {
            if let copies = document?.copies {
                Text(clash: .format("Only “%@” will use it; rule scheme “%@” stays as it is.", [copies.configuration, copies.scheme]))
            }
        }
    }

    @ViewBuilder
    private func row(_ key: String, in document: ClashMacSettingsSectionDocument) -> some View {
        let field = document.field(at: [key])
        let value = document.running.topLevelValue(key)
        let title = copy.title(for: field, key: key, locale: locale)
        let presets = copy.entry(for: field, locale: locale)?.presets ?? []
        let edit = ClashMacKeyEdit(path: [key], value: value, platformReason: nil, choices: document.choices[key],
                                  control: field.flatMap { document.control(for: $0) },
                                  removable: value != nil && document.removes([key]), isDefault: value == nil, field: field)
        if key == "bind-address", !presets.isEmpty {
             
             
            let written = Self.token(value)
            let shown = Self.choice(for: written ?? field?.defaultText, in: presets.map(\.value))
            Picker(selection: Binding(get: { shown == Self.customTag ? (written ?? Self.customTag) : shown }, set: { picked in
                if picked == Self.customTag { editing = edit; return }
                guard picked != written, presets.contains(where: { $0.value == picked }) else { return }
                request([.set(path: [key], to: .string(picked))])
            })) {
                ForEach(presets, id: \.value) { Text(verbatim: $0.label).tag($0.value) }
                 
                if shown == Self.customTag, let written { Text(verbatim: written).tag(written) }
                Divider()
                Text(clash: .copy("Custom…")).tag(Self.customTag)
            } label: {
                Text(verbatim: title)
            }
            .pickerStyle(.menu)
            .disabled(saving)
            .accessibilityIdentifier("configuration-center.lan-share.bind-address")
        } else {
            LabeledContent {
                Button { editing = edit } label: {
                    Text(clash: ConfigurationValueWords.summary(value, field: field, locale: locale, copy: copy))
                }
                .disabled(saving)
                .accessibilityIdentifier("configuration-center.lan-share.key")
            } label: {
                Text(verbatim: title)
            }
        }
    }

     
     
    static func choice(for value: String?, in choices: [String]) -> String {
        guard let value = value?.trimmingCharacters(in: .whitespaces), !value.isEmpty else { return choices.first ?? customTag }
        return choices.first { $0.lowercased() == value.lowercased() } ?? customTag
    }

    private static func token(_ value: OrderedJSON?) -> String? {
        switch value {
        case .string(let text)?: return text
        case .scalar(let token)?: return token == "null" ? nil : token
        default: return nil
        }
    }

    private func request(_ edits: [ConfigurationPageEdit]) {
        guard !edits.isEmpty, !saving else { return }
        if document?.copies != nil {
            pending = edits
            return
        }
        Task { await save(edits) }
    }

    private func save(_ edits: [ConfigurationPageEdit]) async {
        saving = true
        defer { saving = false }
         
        let keys = edits.compactMap(\.writtenPath.first)
        do {
            try await actions.save(edits, document?.scheme)
            for key in keys { writeFailures[key] = nil }
        } catch is CancellationError {
        } catch {
            for key in keys { writeFailures[key] = ClashErrorCopy.message(error, locale: locale) }
        }
        await reload()
    }

    private func reload() async {
        do {
            document = try await actions.load(.general)
            loadFailure = nil
        } catch is CancellationError {
        } catch {
            loadFailure = ClashErrorCopy.message(error, locale: locale)
        }
    }
}
