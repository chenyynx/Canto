import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashToolbarDivider: View {
    public init() {}

    public var body: some View {
#if os(iOS)
         
         
         
         
        Rectangle()
            .fill(Color.primary.opacity(0.28))
            .frame(width: 1, height: 18)
            .accessibilityHidden(true)
#else
        EmptyView()
#endif
    }
}

public extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
    func clashToolbarGlyph() -> some View {
        font(.body).imageScale(.medium)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashToolbarCapsuleEnd(_ edge: Edge.Set) -> some View {
#if os(iOS)
        padding(edge, edge == .trailing ? 9 : ClashTheme.Spacing.tight)
#else
        self
#endif
    }
}
