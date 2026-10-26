import SwiftUI

/// 策略页一行的展示数据。`id` 只是原样回传给调用方，视图不解释它的含义。
public struct CantoPolicyItem: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let subtitle: String
    public let systemImage: String
    public let tint: Color
    public let isSelected: Bool
    public let latency: String?

    public init(
        id: String,
        title: String,
        subtitle: String,
        systemImage: String,
        tint: Color,
        isSelected: Bool = false,
        latency: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.tint = tint
        self.isSelected = isSelected
        self.latency = latency
    }
}

/// Canto 策略页：大标题 + 右上装饰圆钮 + 策略组白卡列表。
///
/// 只负责布局、选中态与无障碍；数据与点击行为由调用方提供，
/// 页面背景延伸与外层安全区由壳负责。
public struct CantoPolicyView: View {
    // 74 是默认字号下的视觉基线；大字号下文字换行撑高时，
    // 最小高度跟着放大，避免固定高度把文字挤在一起。
    @ScaledMetric(relativeTo: .body) private var minimumRowHeight: CGFloat = 74

    private let title: String
    private let items: [CantoPolicyItem]
    private let onSelect: (String) -> Void

    public init(
        title: String,
        items: [CantoPolicyItem],
        onSelect: @escaping (String) -> Void
    ) {
        self.title = title
        self.items = items
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CantoTheme.Spacing.section) {
                header
                LazyVStack(spacing: 9) {
                    ForEach(items) { item in
                        row(for: item)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, CantoTheme.Spacing.compact)
            .padding(.bottom, CantoTheme.Spacing.section)
        }
        .background(CantoTheme.Palette.canvas)
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: CantoTheme.Spacing.standard) {
            Text(clash: .copy(title))
                .font(.largeTitle.weight(.black))
                .foregroundStyle(CantoTheme.Palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 0)

            // init 没有更多菜单回调：圆钮只保留视觉占位，不参与交互与朗读。
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(CantoTheme.Palette.ink)
                .frame(width: 36, height: 36)
                .background(Circle().fill(CantoTheme.Palette.card))
                .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 2)
                .accessibilityHidden(true)
        }
    }

    // MARK: - 列表

    private func row(for item: CantoPolicyItem) -> some View {
        Button {
            onSelect(item.id)
        } label: {
            HStack(spacing: CantoTheme.Spacing.row) {
                iconWell(for: item)

                VStack(alignment: .leading, spacing: CantoTheme.Spacing.tight) {
                    Text(verbatim: item.title)
                        .font(CantoTheme.Typography.rowTitle)
                        .foregroundStyle(CantoTheme.Palette.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if !item.subtitle.isEmpty || !(item.latency ?? "").isEmpty {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            if !item.subtitle.isEmpty {
                                Text(verbatim: item.subtitle)
                                    .font(CantoTheme.Typography.rowSubtitle)
                                    .foregroundStyle(CantoTheme.Palette.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if let latency = item.latency, !latency.isEmpty {
                                // 延迟是数字，用等宽数字避免数值变化时行内抖动。
                                Text(verbatim: latency)
                                    .font(CantoTheme.Typography.rowSubtitle.monospacedDigit())
                                    .foregroundStyle(CantoTheme.Palette.secondaryInk)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                        }
                    }
                }
                .multilineTextAlignment(.leading)

                Spacer(minLength: CantoTheme.Spacing.compact)

                Text(clash: .copy("select"))
                    .font(CantoTheme.Typography.rowSubtitle)
                    .foregroundStyle(
                        item.isSelected
                            ? CantoTheme.Palette.accent
                            : CantoTheme.Palette.secondaryInk
                    )
                    .fixedSize(horizontal: true, vertical: false)

                chevron
            }
            .padding(.horizontal, CantoTheme.Spacing.standard)
            .padding(.vertical, CantoTheme.Spacing.row)
            .frame(maxWidth: .infinity, minHeight: minimumRowHeight, alignment: .leading)
            .background(shape.fill(CantoTheme.Palette.card))
            .clipShape(shape)
            .shadow(color: .black.opacity(0.035), radius: 10, x: 0, y: 2)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(item.isSelected ? [.isSelected] : [])
    }

    private func iconWell(for item: CantoPolicyItem) -> some View {
        Image(systemName: item.systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(item.tint)
            .frame(width: 36, height: 36)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(item.tint.opacity(0.12))
            )
            .accessibilityHidden(true)
    }

    private var chevron: some View {
        Circle()
            .fill(CantoTheme.Palette.canvas)
            .frame(width: 22, height: 22)
            .overlay(
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(CantoTheme.Palette.secondaryInk)
            )
            .accessibilityHidden(true)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CantoTheme.Radius.row, style: .continuous)
    }
}
