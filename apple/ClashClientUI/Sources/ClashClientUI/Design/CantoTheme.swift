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
        public static let canvas: Color = cantoDynamicColor(light: 0xF2F4F7, dark: 0x0E1013)
        public static let card: Color = cantoDynamicColor(light: 0xFFFFFF, dark: 0x171A1F)
        public static let ink: Color = cantoDynamicColor(light: 0x101217, dark: 0xF5F7FA)
        public static let secondaryInk: Color = cantoDynamicColor(light: 0x8A8F98, dark: 0x9AA1AC)
        public static let separator: Color = cantoDynamicColor(light: 0xEDEFF2, dark: 0x262B33)
        public static let accent: Color = cantoDynamicColor(light: 0x2F6BFF, dark: 0x6B8CFF)
        public static let success: Color = cantoDynamicColor(light: 0x34C759, dark: 0x30D158)
        public static let warning: Color = cantoDynamicColor(light: 0xFF9F0A, dark: 0xFFB340)
        public static let danger: Color = cantoDynamicColor(light: 0xFF3B30, dark: 0xFF453A)
    }

    public enum Spacing {
        public static let tight: CGFloat = 4
        public static let compact: CGFloat = 8
        public static let row: CGFloat = 12
        public static let standard: CGFloat = 16
        public static let section: CGFloat = 24
    }

    public enum Radius {
        public static let card: CGFloat = 18
        public static let row: CGFloat = 18
        public static let control: CGFloat = 14
        public static let pill: CGFloat = 999
    }

    public enum Typography {
        public static var pageTitle: Font { .largeTitle.weight(.bold) }
        public static var sectionTitle: Font { .title2.weight(.bold) }
        public static var rowTitle: Font { .body.weight(.semibold) }
        public static var rowSubtitle: Font { .footnote }
        public static var caption: Font { .caption2 }
        public static var metric: Font {
            .system(.title3, design: .monospaced).weight(.semibold)
        }
        public static var tabLabel: Font { .caption2.weight(.semibold) }
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
