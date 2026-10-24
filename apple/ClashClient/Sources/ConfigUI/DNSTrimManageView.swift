import SwiftUI
import ClashClientUI

 
 
 
 
 
 
 
struct DNSTrimManageView: View {
     
     
     
    let policyKeys: [(String, Int64?)]
    let filterEntries: [(String, Int64?)]
    @State var droppedKeys: Set<String>
    @State var droppedEntries: Set<String>
    let onSave: (Set<String>, Set<String>) -> Void

     
     
     
     
     
     
    @State private var dismiss = ClashDismissHandle()
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            if !policyKeys.isEmpty {
                Section {
                    ForEach(policyKeys, id: \.0) { key, bytes in
                        Toggle(isOn: binding(key, in: $droppedKeys)) {
                            row(key, bytes)
                        }
                        .accessibilityIdentifier("dns.trim.policy.\(key)")
                    }
                } header: {
                     
                    Text(clash: .verbatim("nameserver-policy"))
                        .textCase(nil)
                }
            }
            if !filterEntries.isEmpty {
                Section {
                    ForEach(filterEntries, id: \.0) { entry, bytes in
                        Toggle(isOn: binding(entry, in: $droppedEntries)) {
                            row(entry, bytes)
                        }
                        .accessibilityIdentifier("dns.trim.filter.\(entry)")
                    }
                } header: {
                    Text(clash: .verbatim("fake-ip-filter"))
                        .textCase(nil)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button {
                onSave(droppedKeys, droppedEntries)
                dismiss()
            } label: {
                Text(clash: .copy("Save and Retry"))
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .clashPrimaryActionButtonStyle()
            .clashCapsuleButtonBorderShape()
            .controlSize(.large)
            .shadow(color: .black.opacity(0.18), radius: 10, x: 0, y: 4)
            .padding(.horizontal, ClashTheme.Spacing.section)
            .padding(.bottom, ClashTheme.Spacing.compact)
            .accessibilityIdentifier("dns.trim.save")
        }
        .navigationTitle(
            ClashCopy.string(for: .copy("Manage DNS Routing"), locale: locale)
        )
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                ClashSheetCloseButton { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    droppedKeys = []
                    droppedEntries = []
                } label: {
                    Text(clash: .copy("Restore All"))
                        .font(.subheadline)
                }
                .disabled(droppedKeys.isEmpty && droppedEntries.isEmpty)
            }
        }
        .clashCapturesDismiss(dismiss)
    }

    @ViewBuilder
    private func row(_ name: String, _ bytes: Int64?) -> some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            Text(clash: .verbatim(name))
                .font(.subheadline.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
            if let bytes {
                Text(clash: .verbatim(
                    ClashStartupExplanation.megabytes(bytes)
                ))
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
            set: { keeps in
                if keeps { set.wrappedValue.remove(name) }
                else { set.wrappedValue.insert(name) }
            }
        )
    }
}

 
 
 
 
 
 
 
 
struct ProviderLoadDetailView: View {
    struct Row: Equatable, Identifiable {
        let name: String
         
        let bytes: Int64?
         
         
        var isEstimate: Bool = false
         
        var isSubscription: Bool = false
        var id: String { name }
    }

    let rows: [Row]
     
    @State private var dismiss = ClashDismissHandle()
    @Environment(\.locale) private var locale

    @ViewBuilder
    private func rowView(_ row: Row) -> some View {
        HStack {
            Text(clash: .verbatim(row.name))
                .font(.subheadline)
            Spacer(minLength: 0)
            if let bytes = row.bytes {
                Text(clash: .verbatim(
                    (row.isEstimate ? "≈ " : "")
                        + ClashStartupExplanation.megabytes(bytes)
                ))
                .font(.footnote)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        List {
            let subscriptions = rows.filter(\.isSubscription)
            let groups = rows.filter { !$0.isSubscription }
            if !subscriptions.isEmpty {
                Section {
                    ForEach(subscriptions) { row in rowView(row) }
                } header: {
                     
                    Text(clash: .verbatim("proxy-providers"))
                        .textCase(nil)
                }
            }
            if !groups.isEmpty {
                Section {
                    ForEach(groups) { row in rowView(row) }
                } header: {
                    Text(clash: .verbatim("proxy-groups"))
                        .textCase(nil)
                }
            }
            Section {
            } footer: {
                Text(clash: .copy("What each source cost to load this start. Temporary parse memory is returned by the system after startup."))
            }
        }
        .navigationTitle(
            ClashCopy.string(for: .copy("Provider Load"), locale: locale)
        )
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                ClashSheetCloseButton { dismiss() }
            }
        }
        .clashCapturesDismiss(dismiss)
    }
}
