import SwiftUI

/// 白底圆角分组容器：配置/更多这类长列表用，行之间只画分隔线，不再每行一张卡。
public struct CantoGroup<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            content
        }
        .background(shape.fill(CantoTheme.Palette.card))
        .clipShape(shape)
        .overlay(shape.stroke(CantoTheme.Palette.separator, lineWidth: 1))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CantoTheme.Radius.row, style: .continuous)
    }
}

/// 分组内的一行：图标井 + 标题/副标题 + 自定义尾部；背景由 `CantoGroup` 提供。
public struct CantoGroupRow<Trailing: View>: View {
    private let title: String
    private let subtitle: String?
    private let systemImage: String
    private let iconTint: Color
    private let showsDivider: Bool
    private let trailing: Trailing

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        iconTint: Color,
        showsDivider: Bool = true,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.iconTint = iconTint
        self.showsDivider = showsDivider
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: CantoTheme.Spacing.row) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(iconTint)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(CantoTheme.Typography.rowTitle)
                    .foregroundStyle(CantoTheme.Palette.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(CantoTheme.Typography.caption)
                        .foregroundStyle(CantoTheme.Palette.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .multilineTextAlignment(.leading)
            .accessibilityElement(children: .combine)

            Spacer(minLength: CantoTheme.Spacing.compact)
            trailing
        }
        .padding(.horizontal, CantoTheme.Spacing.standard)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .overlay(alignment: .bottom) {
            if showsDivider {
                Rectangle()
                    .fill(CantoTheme.Palette.separator)
                    .frame(height: 1)
                    .padding(.leading, 22 + CantoTheme.Spacing.row + CantoTheme.Spacing.standard)
            }
        }
    }
}

extension CantoGroupRow where Trailing == CantoChevron {
    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        iconTint: Color,
        showsDivider: Bool = true
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            systemImage: systemImage,
            iconTint: iconTint,
            showsDivider: showsDivider
        ) {
            CantoChevron()
        }
    }
}
