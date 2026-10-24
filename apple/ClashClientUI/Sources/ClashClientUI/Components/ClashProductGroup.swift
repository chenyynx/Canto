import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashProductGroup<Content: View, Trailing: View>: View {
    private let title: ClashDisplayText?
    private let footer: ClashDisplayText?
    private let palette: ClashProductPalette
     
     
     
    private let touchSpacing: CGFloat
     
     
     
     
    private let paintsInSettingsIdiom: Bool
    private let trailing: Trailing
    private let content: Content

     
     
    @Environment(\.clashPageDrawsOwnCards) private var pageDrawsOwnCards

    public init(
        _ title: ClashDisplayText? = nil,
        footer: ClashDisplayText? = nil,
        palette: ClashProductPalette,
        touchSpacing: CGFloat = ClashTheme.Spacing.section,
        paintsInSettingsIdiom: Bool = false,
        @ViewBuilder trailing: () -> Trailing,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.footer = footer
        self.palette = palette
        self.touchSpacing = touchSpacing
        self.paintsInSettingsIdiom = paintsInSettingsIdiom
        self.trailing = trailing()
        self.content = content()
    }

    @ViewBuilder
    public var body: some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom,
           !paintsInSettingsIdiom,
           !pageDrawsOwnCards {
            Section {
                content
            } header: {
                if let title {
                    HStack(alignment: .firstTextBaseline) {
                        Text(clash: title)
                        Spacer(minLength: ClashTheme.Spacing.compact)
                        trailing
                    }
                }
            } footer: {
                if let footer {
                    Text(clash: footer)
                        .clashMacSettingsFootnote()
                }
            }
        } else {
            VStack(
                alignment: .leading,
                 
                 
                 
                 
                 
                 
                 
                spacing: ClashPlatformLayout.pageUsesSystemSettingsIdiom
                    ? ClashTheme.Spacing.cardGap
                    : touchSpacing
            ) {
                if let title {
                    ClashSectionCaption(title) { trailing }
                }
                ClashCardSurface(
                    fill: palette.card,
                    separator: palette.separator,
                    paintsInSettingsIdiom: paintsInSettingsIdiom
                ) {
                     
                     
                     
                     
                     
                     
                     
                     
                    content
                        .padding(ClashTheme.Spacing.standard)
                }
                if let footer {
                    ClashSectionFooter(footer)
                }
            }
        }
    }
}

public extension ClashProductGroup where Trailing == EmptyView {
    init(
        _ title: ClashDisplayText? = nil,
        footer: ClashDisplayText? = nil,
        palette: ClashProductPalette,
        touchSpacing: CGFloat = ClashTheme.Spacing.section,
        paintsInSettingsIdiom: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            title,
            footer: footer,
            palette: palette,
            touchSpacing: touchSpacing,
            paintsInSettingsIdiom: paintsInSettingsIdiom,
            trailing: { EmptyView() },
            content: content
        )
    }
}
