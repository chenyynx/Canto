import SwiftUI

public extension View {
     
     
     
     
     
     
    @ViewBuilder
    func clashGroupedList() -> some View {
#if os(iOS)
        listStyle(.insetGrouped)
#else
        self
#endif
    }
}
