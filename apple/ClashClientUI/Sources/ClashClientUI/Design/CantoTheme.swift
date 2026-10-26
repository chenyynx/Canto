import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

// Canto 重设计使用独立 token，不复用上游 ClashTheme：两套主题要能并行存在，
// 未迁移的旧页面继续用 ClashTheme 时不至于被新值悄悄改掉外观。
public enum CantoTheme {
    public enum Palette {
        // 暖中性底 + 单一蓝色强调色；语义色只用于状态，不做装饰。
        public static let canvas: Color = cantoDynamicColor(light: 0xF4F4F2, dark: 0x111214)
        public static let card: Color = cantoDynamicColor(light: 0xFFFFFF, dark: 0x1A1C20)
        public static let ink: Color = cantoDynamicColor(light: 0x15171C, dark: 0xF2F3F5)
        public static let secondaryInk: Color = cantoDynamicColor(light: 0x73777F, dark: 0x9298A2)
        public static let separator: Color = cantoDynamicColor(light: 0xE6E7E9, dark: 0x2A2D33)
        public static let accent: Color = cantoDynamicColor(light: 0x2F6BFF, dark: 0x6B8CFF)
        public static let success: Color = cantoDynamicColor(light: 0x2E9E5B, dark: 0x35C26B)
        public static let warning: Color = cantoDynamicColor(light: 0xD98200, dark: 0xF0A030)
        public static let danger: Color = cantoDynamicColor(light: 0xD93A34, dark: 0xF05A54)
    }

    public enum Spacing {
        public static let tight: CGFloat = 4
        public static let compact: CGFloat = 8
        public static let row: CGFloat = 12
        public static let standard: CGFloat = 16
        public static let section: CGFloat = 24
    }

    public enum Radius {
        public static let card: CGFloat = 14
        public static let row: CGFloat = 14
        public static let control: CGFloat = 10
        public static let pill: CGFloat = 999
    }

    public enum Typography {
        // 比初版整体降一级字重/字号：工具类界面靠层级，不靠大黑字。
        public static var pageTitle: Font { .title.weight(.semibold) }
        public static var sectionTitle: Font { .title3.weight(.semibold) }
        public static var rowTitle: Font { .body.weight(.medium) }
        public static var rowSubtitle: Font { .subheadline }
        public static var caption: Font { .caption }
        public static var metric: Font {
            .system(.title3, design: .monospaced).weight(.semibold)
        }
        public static var tabLabel: Font { .caption2.weight(.medium) }
    }
}

// 浅色/深色各自给一个十六进制值，由动态 provider 在运行时解析，
// 这样跟随系统外观时无需视图层再读 colorScheme。
private func cantoDynamicColor(light: UInt32, dark: UInt32) -> Color {
#if canImport(UIKit)
    return Color(uiColor: UIColor { traits in
        let hex = traits.userInterfaceStyle == .dark ? dark : light
        return UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    })
#elseif canImport(AppKit)
    return Color(nsColor: NSColor(name: nil) { appearance in
        let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        return NSColor(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    })
#endif
}
