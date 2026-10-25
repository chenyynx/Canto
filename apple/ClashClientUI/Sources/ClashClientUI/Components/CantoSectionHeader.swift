import SwiftUI

public struct CantoSectionHeader: View {
    private let title: String
    private let actionTitle: String?
    private let action: (() -> Void)?

    public init(
        title: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: CantoTheme.Spacing.compact) {
            Text(title)
                .font(CantoTheme.Typography.sectionTitle)
                .foregroundStyle(CantoTheme.Palette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: CantoTheme.Spacing.compact)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(CantoTheme.Typography.caption.weight(.semibold))
                        .foregroundStyle(CantoTheme.Palette.accent)
                        .padding(.horizontal, CantoTheme.Spacing.row)
                        // 11pt 字号配 4pt 内边距的胶囊只有约 20pt 高，按压区域太小；
                        // 6pt 把高度带到约 24pt，视觉上仍是小胶囊。
                        .padding(.vertical, 6)
                        .background(Capsule().fill(CantoTheme.Palette.accent.opacity(0.1)))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(actionTitle))
            }
        }
    }
}
