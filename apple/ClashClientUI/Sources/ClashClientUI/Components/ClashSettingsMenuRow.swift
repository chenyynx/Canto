import SwiftUI

public extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashSettingsMenuRow(
        _ title: String,
        subtitle: ClashDisplayText? = nil,
        adopt: ClashInlineRowAction? = nil
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(clash: .copy(title))
                    .foregroundStyle(.primary)
                if let subtitle {
                     
                     
                     
                    HStack(spacing: ClashTheme.Spacing.compact) {
                        Text(clash: subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let adopt {
                            ClashInlineRowActionLink(action: adopt)
                        }
                    }
                }
            }
            Spacer(minLength: ClashTheme.Spacing.compact)
             
             
             
            self.modifier(ClashMenuHoverHighlight())
        }
        .frame(maxWidth: .infinity)
    }
}


 
 
 
 
 
 
 
 
 
 
public struct ClashInlineRowAction {
    public let title: ClashDisplayText
    public let identifier: String
    public let perform: () -> Void

    public init(title: ClashDisplayText, identifier: String, perform: @escaping () -> Void) {
        self.title = title
        self.identifier = identifier
        self.perform = perform
    }
}

public struct ClashInlineRowActionLink: View {
    let action: ClashInlineRowAction

    public init(action: ClashInlineRowAction) {
        self.action = action
    }

    public var body: some View {
        Button(action: action.perform) {
            Text(clash: action.title)
                .font(.footnote)
        }
         
         
         
        #if os(macOS)
        .buttonStyle(.link)
        #else
        .buttonStyle(.borderless)
        #endif
        .accessibilityIdentifier(action.identifier)
    }
}
