import SwiftUI

 
 
 
 
public struct ClashFeatureCard<Content: View>: View {
    public let palette: ClashProductPalette

    private let content: Content

    public init(
        palette: ClashProductPalette,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.content = content()
    }

    @ViewBuilder
    public var body: some View {
         
         
         
         
         
         
         
         
         
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            Section {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ClashCardSurface(
                fill: palette.card,
                separator: palette.separator
            ) {
                content
                    .padding(ClashTheme.Spacing.standard)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}
