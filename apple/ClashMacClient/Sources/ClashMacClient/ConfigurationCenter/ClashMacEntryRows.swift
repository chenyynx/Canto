import ClashClientKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
public struct ClashMacEntryRows: View {
    let value: OrderedJSON?
     
     
     
    let field: ConfigurationField?
    let catalog: ConfigurationFieldCatalog?
    let save: (OrderedJSON?) -> Void
    @State private var entries: [(key: String, value: OrderedJSON)] = []
    @State private var items: [OrderedJSON] = []
    @State private var loaded = false
    @State private var editing: ClashMacEntryEdit?
    @State private var adding = false
    @Environment(\.configurationFieldCopy) private var copy
    @Environment(\.locale) private var locale

    public init(value: OrderedJSON?, field: ConfigurationField?, catalog: ConfigurationFieldCatalog?,
                save: @escaping (OrderedJSON?) -> Void) {
        self.value = value; self.field = field; self.catalog = catalog; self.save = save
    }

     
     
    enum Shape: Equatable { case map, list, object }

    nonisolated static func shape(of field: ConfigurationField?, value: OrderedJSON?) -> Shape {
        switch field?.kind {
        case .objectList?: return .list
        case .object?: return .object
        case .map?: return .map
        default:
            if case .array? = value { return .list }
            return .map
        }
    }

    private var shape: Shape { Self.shape(of: field, value: value) }

    public var body: some View {
        Group {
            switch shape {
            case .map: mapRows
            case .list: listRows
            case .object: objectRows
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            switch value {
            case .object(let written)?: entries = written
            case .array(let written)?: items = written
            default: break
            }
        }
        .sheet(item: $editing) { edit in
            ClashMacValueEditSheet(edit: edit.edit, save: { edit.set($0) },
                                  useDefault: edit.edit.removable ? { edit.set(nil) } : nil,
                                  removeTitle: edit.deletes ? .copy("Delete") : .copy("Use Default"))
        }
        .sheet(isPresented: $adding) {
            if shape == .list {
                ClashMacNewItemSheet(list: "", types: [], taken: [], form: { _ in newItem }, requiresAValue: true) { item in
                    items.append(item)
                    save(.array(items))
                }
            } else if let field {
                ClashMacNewEntrySheet(entry: ClashMacMapEntryKind(map: field, entry: Self.entryField(of: field, catalog: catalog),
                                                                control: { control($0) }),
                                     taken: Set(entries.map(\.key))) { key, entryValue in
                    entries = Self.writing(entries, key: key, value: entryValue)
                    save(.object(entries))
                }
            }
        }
    }

     

     
    nonisolated static func entryField(of map: ConfigurationField?, catalog: ConfigurationFieldCatalog?) -> ConfigurationField? {
        map.flatMap { catalog?.entryField(ofMapAt: $0.path) }
    }

    @ViewBuilder
    private var mapRows: some View {
        let entryField = Self.entryField(of: field, catalog: catalog)
        Section {
            if entries.isEmpty {
                Text(clash: .copy("None")).foregroundStyle(.secondary)
            }
            ForEach(entries.map(\.key), id: \.self) { name in
                 
                 
                valueRow(title: name, key: name, field: entryField, value: entries.first { $0.key == name }?.value,
                         deletes: true, set: { next in
                             entries = Self.writing(entries, key: name, value: next)
                             save(entries.isEmpty ? nil : .object(entries))
                         })
                .contextMenu {
                    Button(role: .destructive) {
                        entries = Self.writing(entries, key: name, value: nil)
                        save(entries.isEmpty ? nil : .object(entries))
                    } label: { Text(clash: .copy("Delete")) }
                }
            }
            addButton
        }
    }

     
    nonisolated static func writing(_ entries: [(key: String, value: OrderedJSON)], key: String,
                        value: OrderedJSON?) -> [(key: String, value: OrderedJSON)] {
        var next = entries.filter { $0.key != key }
        if let value {
            let index = entries.firstIndex { $0.key == key } ?? next.count
            next.insert((key, value), at: min(index, next.count))
        }
        return next
    }

     

     
     
    nonisolated static func itemFields(of list: ConfigurationField?, catalog: ConfigurationFieldCatalog?) -> [ConfigurationField] {
        guard let list, let catalog else { return [] }
        return ConfigurationNewItem.fields(under: list.path + "[]", catalog: catalog)
    }

    @ViewBuilder
    private var listRows: some View {
        let fields = Self.itemFields(of: field, catalog: catalog)
        if items.isEmpty {
            Section {
                Text(clash: .copy("Nothing added yet.")).foregroundStyle(.secondary)
                    .accessibilityIdentifier("configuration-center.entry.empty")
            }
        }
        ForEach(items.indices, id: \.self) { index in
            let rows = Self.rows(fields, writing: items[index])
             
             
            let off = offSummary(rows, in: items[index])
            Section {
                ForEach(rows, id: \.key) { row in
                    valueRow(title: copy.title(for: row.field, key: row.key, locale: locale), key: row.key, field: row.field,
                             value: items[index].topLevelValue(row.key), deletes: false,
                             set: { next in setItem(index, row.key, next) })
                    .disabled(offSwitch(key: row.key, field: row.field, in: items[index]) != nil)
                }
                Button(role: .destructive) {
                    items.remove(at: index)
                    save(items.isEmpty ? nil : .array(items))
                } label: { Text(clash: .copy("Delete")) }
                .accessibilityIdentifier("configuration-center.entry.item.delete")
            } header: {
                Text(verbatim: Self.title(of: items[index], at: index))
            } footer: {
                ClashMacGroupFooter(words: nil, off: off)
            }
        }
        Section { addButton }
    }

    private func setItem(_ index: Int, _ key: String, _ next: OrderedJSON?) {
        guard items.indices.contains(index) else { return }
        items[index] = next.map { items[index].settingTopLevel(key, to: $0) } ?? items[index].removingTopLevel(key)
        save(.array(items))
    }

     
     
     
    private var newItem: ConfigurationNewItem {
        ConfigurationNewItem(type: nil, asked: Self.itemFields(of: field, catalog: catalog)
            .filter { $0.kind != .object && $0.kind != .map && $0.kind != .objectList }
            .map { ConfigurationNewItem.Asked(key: ConfigurationNewItem.key(of: $0), field: $0, isRequired: $0.isRequired, children: []) })
    }

     
    nonisolated static func title(of item: OrderedJSON, at index: Int) -> String {
        for key in ["name", "server"] {
            if case .string(let text)? = item.topLevelValue(key), !text.isEmpty { return text }
        }
        return "#\(index + 1)"
    }

     

    @ViewBuilder
    private var objectRows: some View {
        let fields = field.flatMap { field in catalog.map { ConfigurationNewItem.fields(under: field.path, catalog: $0) } } ?? []
        let object = OrderedJSON.object(entries)
        let rows = Self.rows(fields, writing: object)
        let off = offSummary(rows, in: object)
        Section {
            ForEach(rows, id: \.key) { row in
                valueRow(title: copy.title(for: row.field, key: row.key, locale: locale), key: row.key, field: row.field,
                         value: object.topLevelValue(row.key), deletes: false, set: { next in
                             entries = Self.writing(entries, key: row.key, value: next)
                             save(entries.isEmpty ? nil : .object(entries))
                         })
                .disabled(offSwitch(key: row.key, field: row.field, in: object) != nil)
            }
        } footer: {
            ClashMacGroupFooter(words: nil, off: off)
        }
    }

     

     
     
    private func offSummary(_ rows: [(key: String, field: ConfigurationField?)], in mapping: OrderedJSON) -> ConfigurationOffSwitchSummary? {
        guard let catalog else { return nil }
        return catalog.offSwitchSummary(over: rows.compactMap { row in row.field.map { (field: $0, steps: [ConfigurationDocumentStep.key(row.key)]) } },
                                        in: mapping)
    }

     
     
    private func offSwitch(key: String, field: ConfigurationField?, in mapping: OrderedJSON) -> ConfigurationGoverningSwitch? {
        guard let field, let catalog else { return nil }
        return catalog.offSwitch(for: field, at: [.key(key)], in: mapping)
    }

     
     
    nonisolated static func rows(_ fields: [ConfigurationField], writing mapping: OrderedJSON) -> [(key: String, field: ConfigurationField?)] {
        var rows: [(key: String, field: ConfigurationField?)] = fields.map { (ConfigurationNewItem.key(of: $0), Optional($0)) }
        var seen = Set(rows.map(\.key))
        if case .object(let written) = mapping {
            for entry in written where seen.insert(entry.key).inserted { rows.append((entry.key, nil)) }
        }
        return rows
    }

     
     
    nonisolated static func opensAPage(_ field: ConfigurationField?) -> Bool {
        switch field?.kind {
        case .map?, .objectList?, .object?: return true
        default: return false
        }
    }

     
     
    @ViewBuilder
    private func valueRow(title: String, key: String, field: ConfigurationField?, value: OrderedJSON?, deletes: Bool,
                          set: @escaping (OrderedJSON?) -> Void) -> some View {
        let words = ConfigurationValueWords.summary(value, field: field, locale: locale, copy: copy)
        if Self.opensAPage(field) {
            ClashRoutedViewLink {
                ClashMacSettingsFormContainer {
                    ClashMacEntryRows(value: value, field: field, catalog: catalog, save: set)
                }
                .navigationTitle(Text(verbatim: title))
            } label: {
                LabeledContent { Text(clash: words) } label: { Text(verbatim: title) }
            }
            .accessibilityIdentifier("configuration-center.entry.page")
        } else if let field, case .toggle? = control(field, value: value) {
            Toggle(isOn: Binding(
                get: { Self.token(value).map { $0 == "true" } ?? field.defaultFlag },
                set: { set(.scalar($0 ? "true" : "false")) }
            )) { Text(verbatim: title) }
            .toggleStyle(.switch)
            .accessibilityIdentifier("configuration-center.entry.item.toggle")
        } else {
            LabeledContent {
                Button {
                    editing = ClashMacEntryEdit(id: title + "/" + key, deletes: deletes,
                                               edit: ClashMacKeyEdit(path: [key], value: value, platformReason: nil, choices: nil,
                                                                    control: field.flatMap { control($0, value: value) },
                                                                    removable: value != nil, isDefault: value == nil, field: field),
                                               set: set)
                } label: {
                    Text(clash: words)
                }
                .accessibilityIdentifier("configuration-center.entry.edit")
            } label: {
                Text(verbatim: title)
            }
        }
    }

    private var addButton: some View {
        Button { adding = true } label: {
            Label { Text(clash: .opens("Add", locale: locale)) } icon: { Image(systemName: "plus") }
        }
        .accessibilityIdentifier("configuration-center.entry.add")
    }

    private func control(_ field: ConfigurationField) -> ClashMacFieldControl? { control(field, value: nil) }

    private func control(_ field: ConfigurationField, value: OrderedJSON?) -> ClashMacFieldControl? {
        ClashMacFieldControl.make(field, value: value) { _ in [] }
    }

    private static func token(_ value: OrderedJSON?) -> String? {
        switch value {
        case .string(let text)?: return text
        case .scalar(let token)?: return token
        default: return nil
        }
    }
}

 
struct ClashMacEntryEdit: Identifiable {
    let id: String
     
     
    let deletes: Bool
    let edit: ClashMacKeyEdit
    let set: (OrderedJSON?) -> Void
}
