import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

 
 
 
 
 
 
 
public enum ClashThroughputUnit: String, CaseIterable, Sendable {
    case bits
    case bytes

    public static let defaultsKey = "display.throughputUnit"
     
     
    public static let didChangeNotification = Notification.Name("ClashThroughputUnitDidChange")

     
    public static func stored(in defaults: UserDefaults?) -> ClashThroughputUnit {
        defaults?.string(forKey: defaultsKey).flatMap(ClashThroughputUnit.init(rawValue:)) ?? .bits
    }

     
     
    @MainActor
    public static func store(_ unit: ClashThroughputUnit, in defaults: UserDefaults?) {
        defaults?.set(unit.rawValue, forKey: defaultsKey)
        NotificationCenter.default.post(name: didChangeNotification, object: nil)
    }
}

#if canImport(SwiftUI)
private struct ClashThroughputUnitKey: EnvironmentKey {
    static let defaultValue: ClashThroughputUnit = .bits
}

extension EnvironmentValues {
     
     
    public var clashThroughputUnit: ClashThroughputUnit {
        get { self[ClashThroughputUnitKey.self] }
        set { self[ClashThroughputUnitKey.self] = newValue }
    }
}
#endif

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashThroughputFormatter {
    private static let bitsPerByte: Double = 8
    private static let bitsPerKilobit: Double = 1_000
    private static let bitsPerMegabit: Double = 1_000_000

     
     
     
     
     
     
     
     
     
    public static func rate(_ bytesPerSecond: Int64, unit: ClashThroughputUnit) -> String {
        switch unit {
        case .bits:
            let bitsPerSecond = Double(max(bytesPerSecond, 0)) * bitsPerByte
            if bitsPerSecond < bitsPerMegabit {
                return String(format: "%.0f Kbps", bitsPerSecond / bitsPerKilobit)
            }
            return String(format: "%.1f Mbps", bitsPerSecond / bitsPerMegabit)
        case .bytes:
            let kilobytes = Double(max(bytesPerSecond, 0)) / 1_024
            if kilobytes < 999.5 {
                return String(format: "%.0f KB/s", kilobytes)
            }
            return String(format: "%.1f MB/s", kilobytes / 1_024)
        }
    }

     
     
     
     
     
     
     
    public static func usage(_ bytes: Int64) -> String {
        let absolute = Double(max(bytes, 0))
        if absolute < 1_024 { return String(format: "%.0f B", absolute) }
        if absolute < 1_048_576 { return String(format: "%.1f KB", absolute / 1_024) }
        if absolute < 1_073_741_824 { return String(format: "%.1f MB", absolute / 1_048_576) }
        return String(format: "%.2f GB", absolute / 1_073_741_824)
    }
}
