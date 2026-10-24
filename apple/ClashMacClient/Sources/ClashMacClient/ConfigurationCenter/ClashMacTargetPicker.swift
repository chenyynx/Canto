import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
struct ClashMacTargetRow: View {
    let title: ClashDisplayText
    let value: String
    let identifier: String
    let open: () -> Void
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    var body: some View {
        LabeledContent {
            Button(action: open) {
                 
                Text(clash: value.isEmpty ? .copy("Choose…")
                     : .verbatim(ConfigurationRuleWords.targetName(value, locale: locale, copy: copy))).lineLimit(1)
            }
            .accessibilityIdentifier(identifier)
            .accessibilityValue(Text(verbatim: value))
        } label: {
            Text(clash: title)
        }
    }
}

 
 
 
 
 
struct ClashMacTargetPickerPage: View {
    let candidates: ConfigurationRuleTargetCandidates
    let current: String
    let identifier: String
     
     
     
     
    var addGroup: (() -> Void)?
    let pick: (String) -> Void
    @State private var query = ""
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale
    @Environment(\.clashRuleTargetSearch) private var targetSearch
     
     
     
     
    @State private var searched: [ConfigurationRuleTargetCandidates.Section] = []
    @State private var searching = false

    private var shown: ConfigurationRuleTargetCandidates {
        ClashMacTargetSearch.merge(candidates.filtered(by: query), searched)
    }

    private func title(_ section: ConfigurationRuleTargetCandidates.Section) -> ClashDisplayText {
        switch section.kind {
        case .builtin: return .copy("Built-in")
        case .groups: return .copy("Policy Groups")
        case .source, .providers: return .verbatim(section.sourceLabel ?? section.id)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(text: $query, prompt: Text(clash: .copy("Search"))) { Text(clash: .copy("Search")) }
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .accessibilityIdentifier("\(identifier).search")
            Divider()
            if shown.sections.isEmpty, searching {
                ProgressView().controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if shown.sections.isEmpty {
                ClashMacSheetPlaceholder(title: .copy("No results"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("\(identifier).no-results")
            } else {
                List {
                    ForEach(shown.sections) { section in
                        Section {
                             
                            ForEach(section.names, id: \.self) { name in
                                Button { targetSearch?.recordUse(name); pick(name) } label: {
                                    HStack(spacing: ClashTheme.Spacing.compact) {
                                        Text(verbatim: ConfigurationRuleWords.targetName(name, locale: locale, copy: copy))
                                        Spacer()
                                        if name == current {
                                            ClashSymbolImage(symbol: .checkmark).foregroundStyle(.tint)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("\(identifier).pick.\(name)")
                            }
                        } header: {
                            Text(clash: title(section))
                        }
                    }
                }
                .clashMacSettingsList(minRowHeight: ClashMacSettingsMetrics.listRowMinHeight)
            }
             
             
             
             
             
            if let addGroup {
                Divider()
                Button(action: addGroup) { Text(clash: .copy("Add Policy Group")) }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .accessibilityIdentifier("\(identifier).add-group")
            }
        }
        .task(id: query) {
            await ClashMacTargetSearch.run(targetSearch, query: query, current: [current],
                                           searching: $searching, into: $searched)
        }
    }
}

 
 
enum ClashMacTargetSearch {
    static func merge(
        _ local: ConfigurationRuleTargetCandidates, _ searched: [ConfigurationRuleTargetCandidates.Section]
    ) -> ConfigurationRuleTargetCandidates {
        guard !searched.isEmpty else { return local }
        var seen = Set(local.sections.flatMap(\.names))
        let more = searched.compactMap { section -> ConfigurationRuleTargetCandidates.Section? in
            let names = section.names.filter { seen.insert($0).inserted }
            return names.isEmpty ? nil
                : .init(id: section.id, kind: section.kind, sourceLabel: section.sourceLabel, names: names)
        }
        return ConfigurationRuleTargetCandidates(sections: local.sections + more)
    }

     
     
    @MainActor
    static func run(
        _ hook: ClashRuleTargetSearchHook?, query: String, current: [String],
        searching: Binding<Bool>, into searched: Binding<[ConfigurationRuleTargetCandidates.Section]>
    ) async {
        guard let hook else { searched.wrappedValue = []; return }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searching.wrappedValue = !needle.isEmpty
        defer { if !Task.isCancelled { searching.wrappedValue = false } }
        if !needle.isEmpty {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
        }
        let found = await hook.sections(needle, current)
        if !Task.isCancelled { searched.wrappedValue = found }
    }
}
