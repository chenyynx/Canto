import SwiftUI

public enum CantoTrafficDirection {
    case upload
    case download
}

// 仪表双流量卡：扁平白卡，数字为主，方向只用一个语义色小箭头。
public struct CantoTrafficTile: View {
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 78

    private let direction: CantoTrafficDirection
    private let label: String
    private let value: String
    private let caption: String

    public init(
        direction: CantoTrafficDirection,
        label: String,
        value: String,
        caption: String
    ) {
        self.direction = direction
        self.label = label
        self.value = value
        self.caption = caption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: CantoTheme.Spacing.tight) {
            HStack(spacing: CantoTheme.Spacing.tight) {
                Image(systemName: direction.symbolName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(direction.tint)
                    .accessibilityHidden(true)
                Text(label)
                    .font(CantoTheme.Typography.caption)
                    .foregroundStyle(CantoTheme.Palette.secondaryInk)
            }

            Text(value)
                .font(CantoTheme.Typography.metric)
                .foregroundStyle(CantoTheme.Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            Text(caption)
                .font(CantoTheme.Typography.caption)
                .foregroundStyle(CantoTheme.Palette.secondaryInk)
                .lineLimit(1)
        }
        .padding(CantoTheme.Spacing.standard)
        .frame(maxWidth: .infinity, minHeight: tileHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: CantoTheme.Radius.card, style: .continuous)
                .fill(CantoTheme.Palette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CantoTheme.Radius.card, style: .continuous)
                .stroke(CantoTheme.Palette.separator, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private extension CantoTrafficDirection {
    var symbolName: String {
        switch self {
        case .upload: return "arrow.up"
        case .download: return "arrow.down"
        }
    }

    var tint: Color {
        switch self {
        case .upload: return CantoTheme.Palette.success
        case .download: return CantoTheme.Palette.accent
        }
    }
}
