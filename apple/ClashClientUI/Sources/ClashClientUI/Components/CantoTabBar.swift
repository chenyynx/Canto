import SwiftUI

public struct CantoTabItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let systemImage: String

    public init(id: String, title: String, systemImage: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

// 浮动胶囊 Tab 栏：4 个等宽项，选中项用强调色 10% 胶囊兜底，图标与文字同色。
public struct CantoTabBar: View {
    private let items: [CantoTabItem]
    @Binding private var selection: String

    public init(items: [CantoTabItem], selection: Binding<String>) {
        self.items = items
        _selection = selection
    }

    public var body: some View {
        HStack(spacing: CantoTheme.Spacing.tight) {
            ForEach(items) { item in
                tab(item)
            }
        }
        .padding(CantoTheme.Spacing.compact)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(CantoTheme.Palette.card.opacity(0.94))
        )
        .shadow(color: .black.opacity(0.06), radius: 12, x: 0, y: 4)
    }

    private func tab(_ item: CantoTabItem) -> some View {
        let isSelected = item.id == selection
        return Button {
            selection = item.id
        } label: {
            VStack(spacing: CantoTheme.Spacing.tight) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 21, weight: .regular))
                    .accessibilityHidden(true)
                Text(item.title)
                    .font(CantoTheme.Typography.tabLabel)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    // 大字号下优先换行，两行仍放不下时整体缩小，避免出现省略号。
                    .minimumScaleFactor(0.7)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(isSelected ? CantoTheme.Palette.accent : CantoTheme.Palette.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, CantoTheme.Spacing.tight)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? CantoTheme.Palette.accent.opacity(0.1) : Color.clear)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(item.title))
        .accessibilityIdentifier("canto.tab.\(item.id)")
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : [])
    }
}
