import SwiftUI

 
 
 
 
 
public enum ClashActivityBadgeStyle {
     
    public static func hex(
        _ badge: ClashActivityTableColumn.Badge,
        dark: Bool
    ) -> (text: UInt32, fill: UInt32) {
        func style(light: (fill: UInt32, text: UInt32), dark night: (fill: UInt32, text: UInt32)) -> (text: UInt32, fill: UInt32) {
            let pair = dark ? night : light
            return (pair.text, pair.fill)
        }
        switch badge {
        case .tcp: return style(light: (0xD6F4F1, 0x00857A), dark: (0x214B48, 0x2ED8C8))
        case .https: return style(light: (0xF8EED0, 0x9A7400), dark: (0x655123, 0xFFBC00))
        case .http: return style(light: (0xE5F7E8, 0x1E8844), dark: (0x2E4933, 0x23C060))
        case .quic: return style(light: (0xFCEBD9, 0xB25A00), dark: (0x634227, 0xFF9F3D))
        case .udp: return style(light: (0xF0E4F9, 0x7E3DB0), dark: (0x4B3862, 0xC88BFF))
        case .otherTransport, .ruleKind: return style(light: (0xEFEEEF, 0x89898C), dark: (0x434344, 0x9A9A9E))
        case .refused: return style(light: (0xFADDE0, 0xCC3752), dark: (0x633C42, 0xFF5271))
        }
    }

     
     
     
     
    static let detailInk = Color.primary.opacity(0.62)

     
     
     
    static func readableRuleKindText(dark: Bool) -> UInt32 {
        dark ? 0xAEAEB2 : 0x636366
    }

    static func color(_ hex: UInt32) -> Color {
        Color(
            .sRGB,
            red: Double(hex >> 16 & 0xFF) / 255,
            green: Double(hex >> 8 & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

 
 
 
 
struct ClashActivityBadge: View {
    let text: String
    let badge: ClashActivityTableColumn.Badge
     
     
    var isReadable = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        let hex = ClashActivityBadgeStyle.hex(badge, dark: dark)
        let textHex = isReadable && badge == .ruleKind
            ? ClashActivityBadgeStyle.readableRuleKindText(dark: dark)
            : hex.text
        Text(verbatim: text)
            .font(.system(.caption2, design: .monospaced).weight(.semibold))
            .lineLimit(1)
            .foregroundColor(ClashActivityBadgeStyle.color(textHex))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(ClashActivityBadgeStyle.color(hex.fill))
            )
    }
}
