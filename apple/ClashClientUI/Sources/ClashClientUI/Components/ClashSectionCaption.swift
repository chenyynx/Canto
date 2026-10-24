import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
public struct ClashSectionCaption<Trailing: View>: View {
     
     
     
    private let title: ClashDisplayText
    private let trailing: Trailing

    public init(
        _ title: ClashDisplayText,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(clash: title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Spacer(minLength: 8)
            trailing
        }
        .padding(.horizontal, ClashTheme.Spacing.compact)
        .accessibilityAddTraits(.isHeader)
    }
}

public extension ClashSectionCaption where Trailing == EmptyView {
    init(_ title: ClashDisplayText) {
        self.init(title) { EmptyView() }
    }
}

 
 
 
 
public struct ClashSectionFooter: View {
    private let text: ClashDisplayText

    public init(_ text: ClashDisplayText) {
        self.text = text
    }

    public var body: some View {
        Text(clash: text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, ClashTheme.Spacing.compact)
    }
}
