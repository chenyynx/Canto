import SwiftUI

 
 
 
 
public struct ClashProfileContextHeader<Icon: View>: View {
    public let profileName: String
    public let message: ClashDisplayText
    public let iconTint: Color

    private let icon: Icon

    public init(
        profileName: String,
        message: ClashDisplayText,
        iconTint: Color = .blue,
        @ViewBuilder icon: () -> Icon
    ) {
        self.profileName = profileName
        self.message = message
        self.iconTint = iconTint
        self.icon = icon()
    }

    public var body: some View {
        HStack(
            alignment: .top,
            spacing: ClashTheme.Spacing.row
        ) {
            icon
                .font(.body.weight(.semibold))
                .foregroundStyle(iconTint)
                .frame(width: 24, height: 24)

            VStack(
                alignment: .leading,
                spacing: ClashTheme.Spacing.tight
            ) {
                Text(profileName)
                    .font(.headline)
                    .lineLimit(2)
                 
                 
                if !message.isBlank {
                    Text(clash: message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
