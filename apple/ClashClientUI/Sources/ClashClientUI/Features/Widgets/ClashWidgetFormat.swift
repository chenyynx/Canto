import Foundation

 
 
public enum ClashWidgetFormat {
    public static let unknown = "—"

     
     
    public static func bytes(_ value: Int64?) -> String {
        guard let value else { return unknown }
        return ClashThroughputFormatter.usage(value)
    }

     
     
    public static func rate(_ bytesPerSecond: Int64?, unit: ClashThroughputUnit) -> String {
        guard let bytesPerSecond else { return unknown }
        return ClashThroughputFormatter.rate(bytesPerSecond, unit: unit)
    }

    public static func count(_ value: Int?, locale: Locale) -> String {
        guard let value else { return unknown }
        return ClashCopy.count(value, locale: locale)
    }

     
     
    public static func modeKey(_ mode: ClashWidgetMode) -> String {
        switch mode {
        case .rule: return "Rule"
        case .global: return "Global"
        case .direct: return "Direct"
        }
    }
}
