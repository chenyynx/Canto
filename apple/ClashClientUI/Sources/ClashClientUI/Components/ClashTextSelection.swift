import SwiftUI

extension View {
     
     
    @ViewBuilder
    func clashTextSelectionEnabled() -> some View {
#if os(tvOS)
        self
#else
        textSelection(.enabled)
#endif
    }
}
