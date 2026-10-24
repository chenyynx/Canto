import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashSheetCloseButton: View {
    private let dismiss: () -> Void
    @Environment(\.clashProductModalDismiss) private var productModalDismiss

    public init(dismiss: @escaping () -> Void) {
        self.dismiss = dismiss
    }

    public var body: some View {
        Button(action: close) {
            Label("Close", systemImage: "xmark")
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel("Close")
        .accessibilityIdentifier("sheet.close")
    }

    private func close() {
        (productModalDismiss ?? dismiss)()
    }
}
