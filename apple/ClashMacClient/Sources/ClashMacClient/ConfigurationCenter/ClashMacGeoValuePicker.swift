import ClashClientUI
import SwiftUI

 
public enum ClashMacGeoResource: String, Sendable {
    case geoIP, geoSite
}

 
 
 
public typealias ClashMacGeoValueLoader = @MainActor (ClashMacGeoResource) async -> [String]

extension ClashStructuredRule.Action {
     
     
     
     
     
     
    var clashMacGeoResource: ClashMacGeoResource? {
        switch self {
        case .geoip, .srcGeoIP: .geoIP
        case .geosite: .geoSite
        default: nil
        }
    }
}

extension ClashMacGeoResource {
     
    var rowTitle: ClashDisplayText {
        switch self {
        case .geoIP: .copy("Country / Region")
        case .geoSite: .copy("Category")
        }
    }

     
    func regionName(_ code: String) -> String? {
        guard self == .geoIP, code.count == 2 else { return nil }
        return Locale.current.localizedString(forRegionCode: code.uppercased())
    }

     
     
    func display(_ value: String) -> String {
        self == .geoIP && value.count == 2 ? value.uppercased() : value
    }

     
    func ruleValue(_ picked: String) -> String {
        self == .geoIP ? picked.uppercased() : picked
    }
}

 
 
 
 
 
struct ClashMacGeoValueRow: View {
    let resource: ClashMacGeoResource
    let value: String
    let identifier: String
    let open: () -> Void

    var body: some View {
        LabeledContent {
            Button(action: open) {
                if value.isEmpty {
                    Text(clash: .copy("Choose…"))
                } else {
                    HStack(spacing: ClashTheme.Spacing.tight) {
                        Text(verbatim: resource.display(value)).font(.body.monospaced())
                        if let name = resource.regionName(value) {
                            Text(verbatim: name).lineLimit(1)
                        }
                    }
                }
            }
            .accessibilityIdentifier(identifier)
            .accessibilityValue(Text(verbatim: resource.display(value)))
        } label: {
            Text(clash: resource.rowTitle)
        }
    }
}

 
 
 
 
struct ClashMacGeoValuePickerPage: View {
    let resource: ClashMacGeoResource
    let current: String
    let load: ClashMacGeoValueLoader
    let identifier: String
    let pick: (String) -> Void
     
     
     
     
    var custom: Binding<String>? = nil
    @State private var query = ""
    @State private var values: [String] = []
    @State private var loaded = false

    private var filtered: [String] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return values }
        let folded = needle.lowercased()
        return values.filter { value in
            value.contains(folded)
                || (resource.regionName(value)?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(text: $query, prompt: Text(clash: .copy("Search code or name"))) {
                Text(clash: .copy("Search code or name"))
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .accessibilityIdentifier("\(identifier).search")
            Divider()
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                ClashMacSheetPlaceholder(title: .copy("No results"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("\(identifier).no-results")
            } else {
                 
                List(filtered, id: \.self) { value in
                    Button { pick(resource.ruleValue(value)) } label: {
                        HStack(spacing: ClashTheme.Spacing.compact) {
                            Text(verbatim: resource.display(value)).font(.body.monospaced())
                            if let name = resource.regionName(value) {
                                Text(verbatim: name).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                             
                             
                             
                            if value.lowercased() == current.trimmingCharacters(in: .whitespaces).lowercased() {
                                ClashSymbolImage(symbol: .checkmark).foregroundStyle(.tint)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("\(identifier).pick.\(value)")
                }
                 
                 
                 
                 
                 
                .clashMacSettingsList(minRowHeight: ClashMacSettingsMetrics.listRowMinHeight)
            }
            if let custom {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    TextField(text: custom, prompt: Text(clash: .copy("Custom"))) { Text(clash: .copy("Custom")) }
                        .textFieldStyle(.roundedBorder)
                        .disableAutocorrection(true)
                        .accessibilityIdentifier("\(identifier).custom")
                    Text(clash: .copy("Only when the list doesn’t have it."))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
        }
        .task {
            guard !loaded else { return }
            values = await load(resource)
            loaded = true
        }
    }
}

extension ClashMacGeoResource {
     
    init(_ set: ConfigurationKnownValueSet) {
        switch set {
        case .geosite: self = .geoSite
        case .geoip: self = .geoIP
        }
    }
}

 
 
 
 
 
 
 
struct ClashMacGeoValuesChecklist: View {
    let resource: ClashMacGeoResource
    @Binding var items: [String]
    let load: ClashMacGeoValueLoader
    @State private var query = ""
    @State private var values: [String] = []
    @State private var loaded = false

    private func contains(_ value: String) -> Bool {
        items.contains { $0.trimmingCharacters(in: .whitespaces).lowercased() == value.lowercased() }
    }

    private var shown: [String] {
        let listed = values.map { resource.ruleValue($0) }
        let written = items.map { $0.trimmingCharacters(in: .whitespaces) }.filter { item in
            !item.isEmpty && !listed.contains { $0.lowercased() == item.lowercased() }
        }
        let all = written + listed
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return all }
        return all.filter { value in
            value.localizedCaseInsensitiveContains(needle)
                || (resource.regionName(value)?.localizedCaseInsensitiveContains(needle) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField(text: $query, prompt: Text(clash: .copy("Search code or name"))) {
                Text(clash: .copy("Search code or name"))
            }
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .accessibilityIdentifier("configuration-center.section.value.known.search")
            Divider()
            if !loaded {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if values.isEmpty, items.isEmpty {
                ClashMacSheetPlaceholder(title: .copy("This device has no list for this yet. Update the geo data in Geo Resources."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(shown, id: \.self) { value in
                    Toggle(isOn: Binding(get: { contains(value) }, set: { on in
                        if on, !contains(value) {
                            items.append(value)
                        } else if !on {
                            items.removeAll { $0.trimmingCharacters(in: .whitespaces).lowercased() == value.lowercased() }
                        }
                    })) {
                        HStack(spacing: ClashTheme.Spacing.compact) {
                            Text(verbatim: resource.display(value)).font(.body.monospaced())
                            if let name = resource.regionName(value) {
                                Text(verbatim: name).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                    }
                    .toggleStyle(.checkbox)
                    .accessibilityIdentifier("configuration-center.section.value.known.item")
                }
                .clashMacSettingsList(minRowHeight: ClashMacSettingsMetrics.listRowMinHeight)
            }
        }
        .task {
            guard !loaded else { return }
            values = await load(resource)
            loaded = true
        }
    }
}
