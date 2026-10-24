import SwiftUI

public extension View {
     
     
     
    func clashPointerHelp(_ text: Text) -> some View {
        modifier(ClashPointerHelp(text: text))
    }
}

private struct ClashPointerHelp: ViewModifier {
    let text: Text

    func body(content: Content) -> some View {
#if os(macOS)
        content.help(text)
#else
        content
#endif
    }
}
