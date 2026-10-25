import SwiftUI

// 列表行右侧的默认披露指示；单独成类型，方便容器把它替换成开关、徽标等尾部内容。
public struct CantoChevron: View {
    public init() {}

    public var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(CantoTheme.Palette.secondaryInk)
            .accessibilityHidden(true)
    }
}

// 白底圆角列表行：左侧彩色图标井 + 标题/副标题 + 自定义尾部。
// 行本身不做点击，交互由外层 NavigationLink / Button 提供。
public struct CantoListRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String
    private let iconTint: Color
    private let trailing: Trailing

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        iconTint: Color,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconTint = iconTint
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: CantoTheme.Spacing.row) {
            iconWell
            VStack(alignment: .leading, spacing: CantoTheme.Spacing.tight) {
                Text(title)
                    .font(CantoTheme.Typography.rowTitle)
                    .foregroundStyle(CantoTheme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(CantoTheme.Typography.rowSubtitle)
                        .foregroundStyle(CantoTheme.Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            // 只合并标题与副标题；尾部可能是开关等可交互控件，不能一起吞掉。
            .accessibilityElement(children: .combine)
            Spacer(minLength: CantoTheme.Spacing.compact)
            trailing
        }
        .padding(.horizontal, CantoTheme.Spacing.standard)
        .padding(.vertical, CantoTheme.Spacing.row)
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CantoTheme.Radius.row, style: .continuous)
                .fill(CantoTheme.Palette.card)
        )
    }

    private var iconWell: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(iconTint)
            .frame(width: 32, height: 32)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(iconTint.opacity(0.12))
            )
            .accessibilityHidden(true)
    }
}

extension CantoListRow where Trailing == CantoChevron {
    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        iconTint: Color
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            iconTint: iconTint
        ) {
            CantoChevron()
        }
    }
}
