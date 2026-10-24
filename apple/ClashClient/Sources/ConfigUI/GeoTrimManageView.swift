import SwiftUI
import ClashClientUI

 
 
 
 
 
 
struct GeoTrimManageView: View {
    let siteItems: [(String, Int64?)]
    let ipItems: [(String, Int64?)]
    @State var droppedSites: Set<String>
    @State var droppedIPs: Set<String>
    let onSave: (Set<String>, Set<String>) -> Void

     
     
     
     
     
     
    @State private var dismiss = ClashDismissHandle()
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            if !siteItems.isEmpty {
                Section {
                    ForEach(siteItems, id: \.0) { name, bytes in
                        Toggle(isOn: binding(name, in: $droppedSites)) {
                            row(name, bytes)
                        }
                        .accessibilityIdentifier("geo.trim.site.\(name)")
                    }
                } header: {
                    Text(verbatim: "GEOSITE").textCase(nil)
                }
            }
            if !ipItems.isEmpty {
                Section {
                    ForEach(ipItems, id: \.0) { name, bytes in
                        Toggle(isOn: binding(name, in: $droppedIPs)) {
                            row(name, bytes)
                        }
                        .accessibilityIdentifier("geo.trim.ip.\(name)")
                    }
                } header: {
                    Text(verbatim: "GEOIP").textCase(nil)
                } footer: {
                    Text(clash: .copy("Switched-off GEO rules are not loaded on the next start."))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                onSave(droppedSites, droppedIPs)
                dismiss()
            } label: {
                Text(clash: saveTitle)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .clashPrimaryActionButtonStyle()
            .clashCapsuleButtonBorderShape()
            .controlSize(.large)
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
            .padding(.horizontal, ClashTheme.Spacing.section)
            .padding(.bottom, ClashTheme.Spacing.compact)
            .accessibilityIdentifier("geo.trim.save")
        }
        .navigationTitle(
            ClashCopy.string(for: .copy("Manage GEO Rules"), locale: locale)
        )
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                ClashSheetCloseButton { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    droppedSites = []
                    droppedIPs = []
                } label: {
                    Text(clash: .copy("Restore All")).font(.subheadline)
                }
                .disabled(droppedSites.isEmpty && droppedIPs.isEmpty)
                .accessibilityIdentifier("geo.trim.restore")
            }
        }
        .clashCapturesDismiss(dismiss)
    }

    private var saveTitle: ClashDisplayText {
        let estimate = siteItems.filter { droppedSites.contains($0.0) }
            .compactMap(\.1).reduce(0, +)
            + ipItems.filter { droppedIPs.contains($0.0) }
            .compactMap(\.1).reduce(0, +)
        guard estimate > 0 else { return .copy("Save and Retry") }
        return .format(
            "Save and Retry · frees about %@",
            [ClashStartupExplanation.megabytes(estimate)]
        )
    }

    @ViewBuilder
    private func row(_ name: String, _ bytes: Int64?) -> some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            Text(clash: .verbatim(name))
                .font(.subheadline.monospaced())
                .lineLimit(1)
            Spacer(minLength: 0)
            if let bytes {
                Text(clash: .verbatim(ClashStartupExplanation.megabytes(bytes)))
                    .font(.footnote)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func binding(
        _ name: String, in set: Binding<Set<String>>
    ) -> Binding<Bool> {
        Binding(
            get: { !set.wrappedValue.contains(name) },
            set: { loads in
                if loads { set.wrappedValue.remove(name) }
                else { set.wrappedValue.insert(name) }
            }
        )
    }
}
