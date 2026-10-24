import SwiftUI

public extension View {
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashMacProductModalBar<Bar: View>(@ViewBuilder _ bar: () -> Bar) -> some View {
#if os(macOS)
        safeAreaInset(edge: .bottom, spacing: 0) { bar() }
#else
        self
#endif
    }
}
