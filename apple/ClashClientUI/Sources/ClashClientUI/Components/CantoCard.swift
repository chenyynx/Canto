import SwiftUI

public struct CantoCard<Content: View>: View {
    private let padding: CGFloat
    private let content: Content

    public init(
        padding: CGFloat = CantoTheme.Spacing.standard,
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            // 先撑满容器再上背景，卡片宽度才不会随内容长短忽宽忽窄。
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(CantoTheme.Palette.card))
            .clipShape(shape)
            .overlay(shape.stroke(CantoTheme.Palette.separator, lineWidth: 1))
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: CantoTheme.Radius.card, style: .continuous)
    }
}
