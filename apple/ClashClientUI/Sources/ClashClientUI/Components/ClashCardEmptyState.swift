import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashCardEmptyState<Icon: View>: View {
    private let title: String
    private let message: String
    private let icon: () -> Icon

    public init(
        title: String,
        message: String,
        @ViewBuilder icon: @escaping () -> Icon
    ) {
        self.title = title
        self.message = message
        self.icon = icon
    }

    public var body: some View {
        ClashEmptyState(
            title: title,
            message: message
        ) {
            icon()
        }
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
    }
}
