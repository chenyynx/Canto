import SwiftUI

 
 
 
 
 
 
public struct ClashProxiesBrowserHost<Modern: View, Legacy: View>: View {
    private let modern: () -> Modern
    private let legacy: () -> Legacy

    public init(
        @ViewBuilder modern: @escaping () -> Modern,
        @ViewBuilder legacy: @escaping () -> Legacy
    ) {
        self.modern = modern
        self.legacy = legacy
    }

    public var body: some View {
        #if os(iOS)
        modern()
            .listStyle(.insetGrouped)
            .modifier(ClashProxiesHomeCardRhythm())
        #else
        legacy()
        #endif
    }
}

 
 
 
enum ClashProxiesBrowserPlatform {
    #if os(iOS)
    static let drawsTabs = false
    #else
    static let drawsTabs = true
    #endif
}

#if os(iOS)
 
 
 
 
 
 
private struct ClashProxiesHomeCardRhythm: ViewModifier {
     
     
     
     
     
     
    private static let toolbarSafeAreaPadding: CGFloat = 12

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .listSectionSpacing(ClashTheme.Spacing.section)
                .contentMargins(
                    .top,
                    ClashTheme.Spacing.section - Self.toolbarSafeAreaPadding,
                    for: .scrollContent
                )
        } else if #available(iOS 17.0, *) {
             
             
             
             
            content.listSectionSpacing(ClashTheme.Spacing.section)
        } else {
            content
        }
    }
}
#endif
