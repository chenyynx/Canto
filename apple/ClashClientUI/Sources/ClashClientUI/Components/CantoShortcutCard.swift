import SwiftUI

// 仪表 2 列快捷方式卡：整卡是按钮，右下放大图标负责辨识，左下小圆提示可进入。
public struct CantoShortcutCard: View {
    // 118 是默认字号的视觉基线；大字号下文字会先把卡片撑高，再把最小高度一起放大，
    // 避免文字已经换行、卡片还停留在固定高度造成挤压。
    @ScaledMetric(relativeTo: .body) private var minimumHeight: CGFloat = 118

    private let title: String
    private let subtitle: String?
    private let systemImage: String
    private let tint: Color
    private let showsDot: Bool
    private let action: () -> Void

    public init(
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        showsDot: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.showsDot = showsDot
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            // 间距压到 tight：标题块 + 图标行的固有高度约 86pt，正好装进 118 最小高度
            // 减去上下 16pt 内边距后的空间；多余空间全部交给 Spacer，图标行保持贴底。
            VStack(alignment: .leading, spacing: CantoTheme.Spacing.tight) {
                header
                Spacer(minLength: 0)
                footer
            }
            .padding(CantoTheme.Spacing.standard)
            // 最小高度含内边距；文字换行撑高后 Spacer 会把图标行继续压到卡片底部。
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
            .background(shape.fill(CantoTheme.Palette.card))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 2)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        // 整卡合并朗读：标题作 label，副标题作 value，装饰性图标与绿点不再单独播报。
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(subtitle ?? ""))
    }

    private var header: some View {
        HStack(alignment: .top, spacing: CantoTheme.Spacing.compact) {
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
            Spacer(minLength: CantoTheme.Spacing.tight)
            if showsDot {
                Circle()
                    .fill(CantoTheme.Palette.success)
                    .frame(width: 8, height: 8)
                    .padding(.top, CantoTheme.Spacing.tight)
                    .accessibilityHidden(true)
            }
        }
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: CantoTheme.Spacing.compact) {
            Circle()
                .fill(CantoTheme.Palette.canvas)
                .frame(width: 22, height: 22)
                .overlay(
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CantoTheme.Palette.secondaryInk)
                )
                .accessibilityHidden(true)
            Spacer(minLength: CantoTheme.Spacing.compact)
            Image(systemName: systemImage)
                .font(.system(size: 32, weight: .regular))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CantoTheme.Radius.card, style: .continuous)
    }
}
