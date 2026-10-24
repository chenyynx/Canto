#if os(iOS)
import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 

 
 
 
struct ConfigurationFieldPresets: View {
    @Binding var draft: ConfigurationDraft
    let presets: [ConfigurationFieldCopy.Preset]
     
     
    var defaultValue: String? = nil

     
    private static let otherTag = "\u{1F}other"

     
     
     
     
    static func selection(for draft: ConfigurationFieldDraft, presets: [String], defaultValue: String?) -> String? {
        if let chosen = draft.choice(in: presets) { return chosen }
        guard draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let defaultValue else { return nil }
        return ConfigurationChoiceMatch.choice(for: defaultValue, in: presets, caseInsensitive: draft.readsWithoutCase)
    }

    var body: some View {
        if case .field(let fieldDraft) = draft, case .text = fieldDraft.control {
            let values = presets.map(\.value)
            let defaultChoice = defaultValue.flatMap {
                ConfigurationChoiceMatch.choice(for: $0, in: values, caseInsensitive: fieldDraft.readsWithoutCase)
            }
            Section {
                Picker(selection: Binding(get: {
                    Self.selection(for: fieldDraft, presets: values, defaultValue: defaultValue) ?? Self.otherTag
                }, set: { value in
                    guard value != Self.otherTag, case .field(var picked) = draft else { return }
                    picked.text = value
                    draft = .field(picked)
                })) {
                    ForEach(presets, id: \.value) { preset in
                        Text(clash: preset.value == defaultChoice ? .format("Default · %@", [preset.label]) : .verbatim(preset.label))
                            .tag(preset.value)
                    }
                } label: {
                    Text(clash: .copy("Common Values"))
                }
                .pickerStyle(.inline)
                .labelsHidden()
                .accessibilityIdentifier("configuration-editor.value.presets")
            }
        }
    }
}

 
 
 
struct ConfigurationFieldAbout: View {
    let summary: String?
    let key: String?

    var body: some View {
        let summary = summary.flatMap { $0.isEmpty ? nil : $0 }
        if summary != nil || key != nil {
            Section {
                EmptyView()
            } footer: {
                VStack(alignment: .leading, spacing: 6) {
                    if let summary { Text(verbatim: summary) }
                    if let key {
                        Text(clash: .format("Written as %@ in the configuration file", [key]))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }
}

extension ConfigurationDraft {
     
    var isList: Bool {
        switch self {
        case .plain(let plain): return plain.kind == .list
        case .field(let field):
            if case .textList = field.control { return true }
            return false
        }
    }
}
#endif
