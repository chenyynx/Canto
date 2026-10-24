import SwiftUI

 
 
 
 
public struct ClashEmptyState<Icon: View>: View {
    public let title: String
    public let message: String
    public let isLoading: Bool

    private let icon: Icon

    public init(
        title: String,
        message: String,
        isLoading: Bool = false,
        @ViewBuilder icon: () -> Icon
    ) {
        self.title = title
        self.message = message
        self.isLoading = isLoading
        self.icon = icon()
    }

    public var body: some View {
        VStack(spacing: ClashTheme.Spacing.row) {
            if isLoading {
                ProgressView()
                    .controlSize(.large)
            } else {
                icon
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            Text(LocalizedStringKey(title))
                .font(.headline)
                .multilineTextAlignment(.center)

             
             
            if !message.isEmpty {
                Text(LocalizedStringKey(message))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, ClashTheme.Spacing.section)
        .padding(.vertical, 40)
        .accessibilityElement(children: .combine)
    }
}
