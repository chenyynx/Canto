import SwiftUI

 
 
 

extension View {
     
     
     
     
     
    @ViewBuilder
    public func clashMacCancelKey() -> some View {
        #if os(macOS)
        keyboardShortcut(.cancelAction)
        #else
        self
        #endif
    }

     
     
     
     
    @ViewBuilder
    public func clashMacProductModalDismiss(
        _ dismiss: @escaping @Sendable @MainActor () -> Void
    ) -> some View {
        #if os(macOS)
        environment(\.clashProductModalDismiss, dismiss)
        #else
        self
        #endif
    }
}
