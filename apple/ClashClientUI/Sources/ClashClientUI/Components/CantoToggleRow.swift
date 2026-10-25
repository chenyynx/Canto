import SwiftUI

// 白底开关行。iOS/tvOS 交给原生 Toggle 排版（label + trailing switch / tvOS 按钮式）；
// macOS 的 switch 样式默认贴着 label，才需要自己把开关推到右侧。
public struct CantoToggleRow: View {
    private let title: String
    private let subtitle: String?
    @Binding private var isOn: Bool

    public init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        _isOn = isOn
    }

    public var body: some View {
        row
            .padding(.horizontal, CantoTheme.Spacing.standard)
            .padding(.vertical, CantoTheme.Spacing.row)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CantoTheme.Radius.row, style: .continuous)
                    .fill(CantoTheme.Palette.card)
            )
    }

    @ViewBuilder
    private var row: some View {
#if os(macOS)
        HStack(spacing: CantoTheme.Spacing.row) {
            titleBlock
                .accessibilityHidden(true)
            Spacer(minLength: CantoTheme.Spacing.row)
            // 视觉标题已单独隐藏，这里的 label 只负责让开关被读成“标题 + 副标题”，
            // 同时保留原生开关的“开/关”状态播报。
            Toggle(isOn: $isOn) {
                titleBlock
            }
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(CantoTheme.Palette.success)
        }
#else
        Toggle(isOn: $isOn) {
            titleBlock
        }
        .tint(CantoTheme.Palette.success)
#endif
    }

    private var titleBlock: some View {
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
    }
}
