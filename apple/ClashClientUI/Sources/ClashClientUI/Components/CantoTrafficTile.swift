import SwiftUI

public enum CantoTrafficDirection {
    case upload
    case download
}

// 仪表双流量卡：上传绿、下载紫，白字压在渐变上，右下角箭头只是装饰性水印。
public struct CantoTrafficTile: View {
    @ScaledMetric(relativeTo: .body) private var tileHeight: CGFloat = 88

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
            Text(label)
                .font(CantoTheme.Typography.caption)
                .foregroundStyle(.white.opacity(0.9))
            Text(value)
                .font(CantoTheme.Typography.metric)
                .foregroundStyle(.white)
                .lineLimit(1)
                // 数值是等宽字体，列宽被网格二次压缩时宁可整体缩小也不截断数字。
                .minimumScaleFactor(0.6)
            Spacer(minLength: CantoTheme.Spacing.tight)
            Text(caption)
                .font(CantoTheme.Typography.caption)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, CantoTheme.Spacing.standard)
        .padding(.vertical, CantoTheme.Spacing.row)
        .frame(maxWidth: .infinity, minHeight: tileHeight, alignment: .leading)
        .background(
            LinearGradient(
                gradient: Gradient(colors: direction.gradientColors),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: CantoTheme.Radius.card, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: direction.symbolName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
                .frame(width: 44, height: 44)
                .padding(.trailing, CantoTheme.Spacing.compact)
                .padding(.bottom, CantoTheme.Spacing.tight)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
    }
}

private extension CantoTrafficDirection {
    var symbolName: String {
        switch self {
        case .upload:
            return "arrow.up"
        case .download:
            return "arrow.down"
        }
    }

    // 任务单指定色值，不跟随深浅色主题变化：两块卡在两种外观下都要保持同一识别度。
    var gradientColors: [Color] {
        switch self {
        case .upload:
            return [
                Color(red: 0x63 / 255.0, green: 0xD6 / 255.0, blue: 0xA0 / 255.0),
                Color(red: 0x45 / 255.0, green: 0xC0 / 255.0, blue: 0x8A / 255.0)
            ]
        case .download:
            return [
                Color(red: 0x8A / 255.0, green: 0x7B / 255.0, blue: 0xF7 / 255.0),
                Color(red: 0x6A / 255.0, green: 0x5A / 255.0, blue: 0xE8 / 255.0)
            ]
        }
    }
}
