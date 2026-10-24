import ClashClientUI
import SwiftUI

 
 
 
struct StringListEditor: View {
    @Binding var items: [String]
    let itemTitle: String
    let placeholder: String
    var validate: ((String) -> String?)?
    var identifier: String?
     
     
     
    private let pending: Binding<String>?

    init(
        items: Binding<[String]>,
        itemTitle: String = "Value",
        placeholder: String,
        validate: ((String) -> String?)? = nil,
        identifier: String? = nil,
        pending: Binding<String>? = nil
    ) {
        _items = items
        self.itemTitle = itemTitle
        self.placeholder = placeholder
        self.validate = validate
        self.identifier = identifier
        self.pending = pending
    }

    @State private var localNewItem = ""
    @State private var error = ""

    private var newItem: Binding<String> { pending ?? $localNewItem }

    var body: some View {
         
         
         
        ForEach(Array(items.indices), id: \.self) { index in
            Text(items[index])
                 
                 
                .font(.body.monospaced())
                .optionalAccessibilityIdentifier(identifier.map { "\($0).item.\(index)" })
        }
        .onDelete { items.remove(atOffsets: $0) }
        .onMove { items.move(fromOffsets: $0, toOffset: $1) }
        #if os(macOS)
        ClashFieldRow(
            itemTitle,
            hint: placeholder,
            text: newItem,
            monospaced: true,
            identifier: identifier
        )
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        ClashAddRow(Text(ClashCopy.key("Add")), action: add)
            .disabled(newItem.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
            .optionalAccessibilityIdentifier(identifier.map { "\($0).add" })
        #else
        HStack {
            TextField(ClashCopy.key(placeholder), text: newItem)
                .font(.body.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .optionalAccessibilityIdentifier(identifier)
            Button("Add", action: add)
                .disabled(newItem.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty)
                .optionalAccessibilityIdentifier(identifier.map { "\($0).add" })
        }
        #endif
        if !error.isEmpty {
            ClashStatusMessage(text: .copy(error), kind: .error)
        }
    }

    private func add() {
        let candidate = newItem.wrappedValue.trimmingCharacters(in: .whitespaces)
        guard !candidate.isEmpty else { return }
        if let reason = validate?(candidate) {
            error = reason
            return
        }
        error = ""
        if !items.contains(candidate) { items.append(candidate) }
        newItem.wrappedValue = ""
    }
}

private extension View {
    @ViewBuilder
    func optionalAccessibilityIdentifier(_ identifier: String?) -> some View {
        if let identifier {
            accessibilityIdentifier(identifier)
        } else {
            self
        }
    }
}

 
 
struct KeyValueListEditor: View {
    struct Entry: Identifiable {
        let id = UUID()
        var key: String
        var value: String
        var valueWasArray: Bool = false
    }

    @Binding var entries: [Entry]
    let keyPlaceholder: String
    let valuePlaceholder: String
    var validateValue: ((String) -> String?)?
    var identifier: String?

    @State private var newKey = ""
    @State private var newValue = ""
    @State private var error = ""

    var body: some View {
        ForEach(Array(entries.indices), id: \.self) { index in
            HStack {
                Text(entries[index].key)
                    .font(.caption.monospaced())
                    .optionalAccessibilityIdentifier(identifier.map { "\($0).key.\(index)" })
                Spacer()
                TextField(ClashCopy.key(valuePlaceholder), text: $entries[index].value)
                    .accessibilityIdentifier("override.list.value")
                    .font(.caption.monospaced())
                    .multilineTextAlignment(.trailing)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .optionalAccessibilityIdentifier(identifier.map { "\($0).value.\(index)" })
            }
        }
        .onDelete { entries.remove(atOffsets: $0) }
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
            TextField(ClashCopy.key(keyPlaceholder), text: $newKey)
                .accessibilityIdentifier("override.list.new-key")
                .font(.caption.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .optionalAccessibilityIdentifier(identifier.map { "\($0).new-key" })
            TextField(ClashCopy.key(valuePlaceholder), text: $newValue)
                .accessibilityIdentifier("override.list.new-value")
                .font(.caption.monospaced())
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .optionalAccessibilityIdentifier(identifier.map { "\($0).new-value" })
            ClashAddRow(Text("Add Entry"), action: add) {
                Label("Add Entry", systemImage: ClashSymbol.plus.name)
            }
                .disabled(newKey.trimmingCharacters(in: .whitespaces).isEmpty
                          || newValue.trimmingCharacters(in: .whitespaces).isEmpty)
                .optionalAccessibilityIdentifier(identifier.map { "\($0).add" })
        }
        if !error.isEmpty {
            ClashStatusMessage(text: .copy(error), kind: .error)
        }
    }

    private func add() {
        let key = newKey.trimmingCharacters(in: .whitespaces)
        let value = newValue.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !value.isEmpty else { return }
        if let reason = validateValue?(value) {
            error = reason
            return
        }
        error = ""
        if let index = entries.firstIndex(where: { $0.key == key }) {
            entries[index].value = value
        } else {
            entries.append(Entry(key: key, value: value))
        }
        newKey = ""
        newValue = ""
    }
}
