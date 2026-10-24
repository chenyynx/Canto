import SwiftUI

public extension View {
     
     
     
     
     
    func clashOnProminentForeground(_ isOnProminent: Bool) -> some View {
        modifier(ClashOnProminentForeground(isOnProminent: isOnProminent))
    }
}

private struct ClashOnProminentForeground: ViewModifier {
    let isOnProminent: Bool
#if os(macOS)
    @Environment(\.controlActiveState) private var controlActiveState
#endif

    private var isFilled: Bool {
#if os(macOS)
        isOnProminent && controlActiveState == .key
#else
        isOnProminent
#endif
    }

    func body(content: Content) -> some View {
        content.foregroundStyle(
            isFilled ? AnyShapeStyle(.white) : AnyShapeStyle(.primary)
        )
    }
}
