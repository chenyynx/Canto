import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashDialogActionBar: View {
    private let resetTitle: String?
    private let resetDisabled: Bool
    private let onReset: (() -> Void)?
    private let cancelTitle: String
    private let onCancel: () -> Void
    private let confirmTitle: String
    private let confirmDisabled: Bool
    private let onConfirm: () -> Void

    public init(
        resetTitle: String? = nil,
        resetDisabled: Bool = false,
        onReset: (() -> Void)? = nil,
        cancelTitle: String = "Cancel",
        onCancel: @escaping () -> Void,
        confirmTitle: String = "Done",
        confirmDisabled: Bool = false,
        onConfirm: @escaping () -> Void
    ) {
        self.resetTitle = resetTitle
        self.resetDisabled = resetDisabled
        self.onReset = onReset
        self.cancelTitle = cancelTitle
        self.onCancel = onCancel
        self.confirmTitle = confirmTitle
        self.confirmDisabled = confirmDisabled
        self.onConfirm = onConfirm
    }

    public var body: some View {
        HStack(spacing: ClashTheme.Spacing.row) {
            if let resetTitle, let onReset {
                Button(role: .destructive, action: onReset) {
                    Text(ClashCopy.key(resetTitle))
                }
                .disabled(resetDisabled)
                .accessibilityIdentifier("clash.dialog.reset")
            }
            Spacer(minLength: 0)
            Button(role: .cancel, action: onCancel) {
                Text(ClashCopy.key(cancelTitle))
            }
            .accessibilityIdentifier("clash.dialog.cancel")
            Button(action: onConfirm) {
                Text(ClashCopy.key(confirmTitle))
            }
            .disabled(confirmDisabled)
             
             
             
             
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("clash.dialog.confirm")
        }
        .modifier(ClashDialogActionBarSurface())
    }
}

 
 
 
private struct ClashDialogActionBarSurface: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.automatic)
            .padding(.horizontal, ClashTheme.Spacing.standard)
            .padding(.vertical, ClashTheme.Spacing.row)
            .frame(maxWidth: .infinity)
            .background(alignment: .top) {
                ZStack(alignment: .top) {
                    Rectangle().fill(.bar)
                    Divider()
                }
                .ignoresSafeArea(edges: .bottom)
            }
    }
}
