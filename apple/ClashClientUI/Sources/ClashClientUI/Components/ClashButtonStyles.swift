import SwiftUI

extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public func clashPrimaryActionButtonStyle() -> AnyView {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            return AnyView(buttonStyle(.glassProminent))
        }
        return AnyView(buttonStyle(.borderedProminent))
    }
}
