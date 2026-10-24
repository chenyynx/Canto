import SwiftUI
import ClashClientUI

 
 
 
 
 
 
 
 
struct MemoryTrimManageView: View {
    struct Item: Equatable, Identifiable {
         
         
         
         
         
         
         
         
        enum Origin: Equatable {
             
            case profile
             
            case override
        }

        let name: String
         
         
        let measuredBytes: Int64?
         
         
        var fromEarlierRun: Bool = false
         
         
        var isEstimate: Bool = false
         
         
        var origin: Origin = .profile
        var id: String { name }
    }

    let items: [Item]
    @State var dropped: Set<String>
    let onSave: (Set<String>) -> Void

     
     
     
     
     
     
    @State private var dismiss = ClashDismissHandle()
    @Environment(\.locale) private var locale

    var body: some View {
        List {
            Section {
                ForEach(items) { item in
                     
                     
                    Toggle(isOn: loadsBinding(item.name)) {
                        HStack(spacing: ClashTheme.Spacing.compact) {
                            Text(clash: .verbatim(item.name))
                                .font(.subheadline)
                             
                             
                             
                             
                             
                             
                            if item.origin == .override {
                                Text(clash: .copy("from override"))
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(.tertiary)
                                    )
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                            if item.fromEarlierRun {
                                Text(clash: .copy("earlier run"))
                                    .font(.caption2)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 4)
                                            .strokeBorder(.tertiary)
                                    )
                                    .foregroundStyle(.secondary)
                            }
                            if let bytes = item.measuredBytes {
                                Text(clash: .verbatim(
                                    (item.isEstimate ? "≈ " : "")
                                        + ClashStartupExplanation.megabytes(bytes)
                                ))
                                .font(.footnote)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                        .accessibilityIdentifier("memory.trim.loads.\(item.name)")
                    .accessibilityIdentifier("memory.trim.row.\(item.name)")
                }
            } header: {
                 
                 
                 
                Text(clash: .copy("Switched-off rule sets are not loaded on the next start."))
                    .textCase(nil)
            } footer: {
                Text(clash: .copy("≈ figures are estimates: entry count × a measured slope, or the staged file's size on disk."))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
             
             
             
             
             
             
            Button {
                onSave(dropped)
                dismiss()
            } label: {
                Text(clash: saveTitle)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .clashPrimaryActionButtonStyle()
            .clashCapsuleButtonBorderShape()
            .controlSize(.large)
            .shadow(
                color: .black.opacity(0.18), radius: 10, x: 0, y: 4
            )
            .padding(.horizontal, ClashTheme.Spacing.section)
            .padding(.bottom, ClashTheme.Spacing.compact)
            .accessibilityIdentifier("memory.trim.save")
        }
        .navigationTitle(
            ClashCopy.string(for: .copy("Manage Rule Sets"), locale: locale)
        )
        .clashToolbarUnlessInPanel {
            ToolbarItem(placement: .cancellationAction) {
                ClashSheetCloseButton { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    dropped = []
                } label: {
                    Text(clash: .copy("Restore All"))
                        .font(.subheadline)
                }
                .disabled(dropped.isEmpty)
                .accessibilityIdentifier("memory.trim.restore")
            }
        }
        .clashCapturesDismiss(dismiss)
    }

     
    private var saveTitle: ClashDisplayText {
        let estimate = items
            .filter { dropped.contains($0.name) }
            .compactMap(\.measuredBytes)
            .reduce(0, +)
        guard estimate > 0 else { return .copy("Save and Retry") }
        return .format(
            "Save and Retry · frees about %@",
            [ClashStartupExplanation.megabytes(estimate)]
        )
    }

     
    private func loadsBinding(_ name: String) -> Binding<Bool> {
        Binding(
            get: { !dropped.contains(name) },
            set: { loads in
                if loads { dropped.remove(name) } else { dropped.insert(name) }
            }
        )
    }
}
