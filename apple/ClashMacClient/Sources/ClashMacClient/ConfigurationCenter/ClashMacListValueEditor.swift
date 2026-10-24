import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
struct ClashMacListValueEditor: View {
    @Binding var items: [String]
    let format: ConfigurationFieldFormat?
     
    var ordered = false
     
    var suggestions: [String] = []
     
    var field: ConfigurationField? = nil
     
     
    var path: String? = nil
     
     
     
    var pending: Binding<String>? = nil
    @State private var localEntry = ""
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale
    @State private var selection = Set<Int>()

    private var entry: Binding<String> { pending ?? $localEntry }
    private var trimmedEntry: String { entry.wrappedValue.trimmingCharacters(in: .whitespaces) }

     
     
     
    private func problem(_ item: String, siblings: [String]) -> ConfigurationFieldProblem? {
        ClashMacFieldDraft.itemProblem(item, format: format, path: path ?? field?.path ?? "",
                                      allowed: suggestions + (field?.values ?? []), siblings: siblings)
    }

     
    private var entries: [String] { items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }

     
    private var entryProblem: ConfigurationFieldProblem? {
        trimmedEntry.isEmpty ? nil : problem(trimmedEntry, siblings: entries)
    }

     
     
    private var commonServers: [ConfigurationFormatPreset] {
        guard format == .dnsServer else { return [] }
        return ConfigurationFormatPresets.dnsServers(path: path ?? field?.path ?? "").filter { !items.contains($0.value ?? "") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            rows
            buttons
             
            if let entryProblem { ClashMacProblemLine(problem: entryProblem) }
             
            if !misshapen.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    if let example = ConfigurationFieldExamples.example(for: format) {
                        Text(clash: .format("Doesn’t look right. For example: %@", [example]))
                    }
                    Text(verbatim: misshapen.joined(separator: ", ")).lineLimit(2)
                }
                .foregroundStyle(.orange)
                .accessibilityIdentifier("configuration-center.section.list.misshapen")
            }
             
             
            Text(clash: ConfigurationFieldExamples.listFooter(for: field, format: format, copy: copy, locale: locale))
                .font(.footnote)
                .foregroundStyle(.secondary)
            if ordered {
                Text(clash: ConfigurationFieldExamples.listOrderNote(for: field) ?? .copy("Earlier items come first."))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var rows: some View {
        List(selection: $selection) {
            ForEach(items.indices, id: \.self) { index in
                itemRow(index)
            }
            .onMove(perform: mover)
            addRow
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .onDeleteCommand { remove(selection) }
        .frame(minHeight: 160)
    }

    private func itemRow(_ index: Int) -> some View {
        TextField(text: item(at: index)) { EmptyView() }
            .labelsHidden()
            .tag(index)
            .contextMenu {
                Button(role: .destructive) { remove([index]) } label: { Text(clash: .copy("Delete")) }
            }
            .accessibilityIdentifier("configuration-center.section.list.item")
    }

    private var addRow: some View {
        return TextField(text: entry, prompt: Text(clash: ConfigurationFieldExamples.prompt(for: field, format: format,
                                                                                          copy: copy, locale: locale))) {
            Text(clash: .copy("Add…"))
        }
            .labelsHidden()
            .onSubmit(add)
            .accessibilityIdentifier("configuration-center.section.list.add")
    }

    private var buttons: some View {
        HStack(spacing: 2) {
            Button(action: add) { Image(systemName: "plus") }
                .disabled(trimmedEntry.isEmpty || entryProblem != nil)
                .help(Text(clash: .copy("Add")))
                .accessibilityIdentifier("configuration-center.section.list.plus")
            Button { remove(selection) } label: { Image(systemName: "minus") }
                .disabled(selection.isEmpty)
                .help(Text(clash: .copy("Delete")))
                .accessibilityIdentifier("configuration-center.section.list.minus")
            if !suggestions.isEmpty {
                Menu {
                    ForEach(suggestions, id: \.self) { suggestion in
                        Button { append(suggestion) } label: { Text(verbatim: suggestion) }
                    }
                } label: { Text(clash: .copy("Add Common Entry")) }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("configuration-center.section.list.suggestions")
            }
            if !commonServers.isEmpty {
                Menu {
                    ForEach(commonServers) { preset in
                        Button { append(preset.value ?? "") } label: {
                            Text(clash: preset.label) + Text(verbatim: "  " + (preset.value ?? ""))
                        }
                    }
                } label: { Text(clash: .copy("Add a Common Server")) }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("configuration-center.section.list.common")
            }
            Spacer()
        }
        .buttonStyle(.borderless)
    }

     
    private var mover: ((IndexSet, Int) -> Void)? {
        guard ordered else { return nil }
        return { source, destination in move(source, destination) }
    }

     
     
    private var misshapen: [String] {
        let current = entries
        return current.enumerated().compactMap { index, item in
            problem(item, siblings: ClashMacFieldDraft.others(current, but: index)) != nil ? item : nil
        }
    }

    private func item(at index: Int) -> Binding<String> {
        Binding(get: { items.indices.contains(index) ? items[index] : "" },
                set: { if items.indices.contains(index) { items[index] = $0 } })
    }

    private func add() {
         
        guard !trimmedEntry.isEmpty, entryProblem == nil else { return }
        append(trimmedEntry)
        entry.wrappedValue = ""
    }

    private func append(_ value: String) {
        items.append(value)
    }

    private func move(_ source: IndexSet, _ destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        selection = []
    }

    private func remove(_ indices: Set<Int>) {
        guard !indices.isEmpty else { return }
        items.remove(atOffsets: IndexSet(indices.filter(items.indices.contains)))
        selection = []
    }
}
