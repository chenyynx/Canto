import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashLazyView<Content: View>: View {
    private let build: () -> Content

    public init(@ViewBuilder _ build: @escaping () -> Content) {
        self.build = build
    }

    public var body: some View {
        ClashDeferredPageContent {
            build()
        } placeholder: {
            ClashPageLoadingPlaceholder(title: .copy("Loading"))
        }
    }
}
