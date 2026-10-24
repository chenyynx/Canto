import SwiftUI
import ClashClientKit
import ClashClientUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ProxyTypeMacRow: View {
    @ObservedObject var draft: ProxyNodeEditorDraft
    let hidesNonServerTypes: Bool
     
    var catalog: ConfigurationFieldCatalog? = nil
     
    var pendingType: Binding<String?>? = nil
    @Environment(\.configurationFieldCopy) private var fieldCopy
    @Environment(\.locale) private var locale

    var body: some View {
        Menu {
            Picker("Common", selection: selection) {
                ForEach(commonSpecifications, id: \.typeID) { item in
                    Text(item.displayName)
                        .tag(item.typeID)
                        .accessibilityIdentifier("proxy-type.\(item.typeID)")
                }
            }
            .pickerStyle(.inline)

            Picker("All Protocols", selection: selection) {
                ForEach(remainingSpecifications, id: \.typeID) { item in
                    Text(item.displayName)
                        .tag(item.typeID)
                        .accessibilityIdentifier("proxy-type.\(item.typeID)")
                }
            }
            .pickerStyle(.inline)
        } label: {
             
             
             
             
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(displayName)
                    .foregroundStyle(.secondary)
                Image(systemName: ClashSymbol.chevronUpChevronDown.name)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(clash: .copy("Proxy Type")))
            .accessibilityValue(displayName)
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityIdentifier("proxies.nodeEditor.type")
        .id("proxies.nodeEditor.type")
        .clashSettingsMenuRow("Proxy Type", subtitle: unavailableLine)
    }

    private var selection: Binding<String> {
        Binding(
            get: { draft.typeID },
            set: { choose($0) }
        )
    }

     
     
    private func choose(_ typeID: String) {
        guard typeID != draft.typeID else { return }
        guard let catalog else { return draft.changeType(to: typeID) }
        if ProxyNodeCatalog.droppedKeys(from: draft.mapping, changingTo: typeID, in: catalog).isEmpty || pendingType == nil {
            draft.changeType(to: typeID, catalog: catalog)
        } else {
            pendingType?.wrappedValue = typeID
        }
    }

     
    private var unavailability: ConfigurationUnavailableValue? {
        catalog.flatMap { ProxyNodeCatalog.typeUnavailability(draft.typeID, in: $0) }
    }

     
     
    private var unavailableLine: ClashDisplayText? {
        unavailability.map { marked in
            fieldCopy.unavailableWords(marked.value, locale: locale).map(ClashDisplayText.verbatim)
                ?? .format("%@ can’t run on this device.", [marked.value])
        }
    }

     
    private var offered: [String]? {
        catalog.map { ProxyNodeCatalog.typeIDs(in: $0, creating: hidesNonServerTypes, current: draft.typeID) }
    }

     
    private func specification(_ typeID: String) -> ProxyProtocolSpecification? {
        ProxyProtocolCatalog.specification(for: typeID)
    }

    private var displayName: String {
        ProxyProtocolCatalog.specification(for: draft.typeID)?.displayName
            ?? draft.typeID
    }

    private var commonSpecifications: [ProxyTypeMacItem] {
        if let offered {
             
            return ProxyTypeGrouping.commonTypeIDs.compactMap { id in offered.first { $0.lowercased() == id.lowercased() } }
                .map(item)
        }
        return ProxyTypeGrouping.commonTypeIDs.compactMap { id in
            ProxyProtocolCatalog.specifications.first { $0.typeID == id }.map { ProxyTypeMacItem(typeID: $0.typeID, displayName: $0.displayName) }
        }
    }

    private var remainingSpecifications: [ProxyTypeMacItem] {
        if let offered {
            let common = Set(ProxyTypeGrouping.commonTypeIDs.map { $0.lowercased() })
            return offered.filter { !common.contains($0.lowercased()) }.map(item)
        }
        return ProxyProtocolCatalog.specifications.filter {
            !ProxyTypeGrouping.commonTypeIDs.contains($0.typeID)
                && !(hidesNonServerTypes
                    && ProxyTypeGrouping.nonServerTypeIDs.contains($0.typeID))
        }
        .map { ProxyTypeMacItem(typeID: $0.typeID, displayName: $0.displayName) }
    }

    private func item(_ typeID: String) -> ProxyTypeMacItem {
        ProxyTypeMacItem(typeID: typeID, displayName: specification(typeID)?.displayName ?? typeID)
    }
}

 
struct ProxyTypeMacItem: Equatable {
    let typeID: String
    let displayName: String
}
