import SwiftUI

// 仪表 2 列快捷方式卡：扁平白卡，单色小图标，不再用整块彩色图标。
public struct CantoShortcutCard: View {
    @ScaledMetric(relativeTo: .body) private var minimumHeight: CGFloat = 96

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
            VStack(alignment: .leading, spacing: CantoTheme.Spacing.compact) {
                HStack(alignment: .top, spacing: CantoTheme.Spacing.compact) {
                    VStack(alignment: .leading, spacing: CantoTheme.Spacing.tight) {
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

                    Spacer(minLength: CantoTheme.Spacing.tight)

                    Image(systemName: systemImage)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }

                Spacer(minLength: 0)

                HStack(spacing: CantoTheme.Spacing.tight) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(CantoTheme.Palette.secondaryInk)
                    if showsDot {
                        Circle()
                            .fill(CantoTheme.Palette.success)
                            .frame(width: 6, height: 6)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityHidden(true)
            }
            .padding(CantoTheme.Spacing.standard)
            .frame(maxWidth: .infinity, minHeight: minimumHeight, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: CantoTheme.Radius.card, style: .continuous)
                    .fill(CantoTheme.Palette.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CantoTheme.Radius.card, style: .continuous)
                    .stroke(CantoTheme.Palette.separator, lineWidth: 1)
            )
            .contentShape(
                RoundedRectangle(cornerRadius: CantoTheme.Radius.card, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(subtitle ?? ""))
    }
}
