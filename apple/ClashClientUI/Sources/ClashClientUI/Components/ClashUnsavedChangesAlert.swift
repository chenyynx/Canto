import SwiftUI

 
extension View {
    public func clashUnsavedChangesAlert(
        isPresented: Binding<Bool>,
        message: ClashDisplayText,
        isBusy: Bool,
        saveTitle: String = "Save",
        saveDisabled: Bool = false,
        save: @escaping () -> Void,
        discard: @escaping () -> Void
    ) -> some View {
        alert("Save your changes?", isPresented: isPresented) {
            Button(ClashCopy.key(saveTitle), action: save)
                .disabled(isBusy || saveDisabled)
            Button("Discard", role: .destructive, action: discard)
                .disabled(isBusy)
            Button("Keep Editing", role: .cancel) {}
        } message: {
            Text(clash: message)
        }
    }
}
