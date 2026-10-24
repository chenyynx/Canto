import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashEntryRow: View {
    private let title: String
    private let value: String?
    private let action: () -> Void

    public init(
        _ title: String,
        value: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.value = value
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(ClashCopy.key(title))
                    .foregroundStyle(.primary)
                Spacer(minLength: ClashTheme.Spacing.standard)
                if let value, !value.isEmpty {
                    Text(ClashCopy.key(value))
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, minHeight: ClashTheme.Control.fullWidthRowMinHeightOnItsOwnPlatform)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
