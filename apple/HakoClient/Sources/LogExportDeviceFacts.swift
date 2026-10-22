import Foundation
#if os(iOS)
import CoreTelephony
#endif

 
 
 
 
 
 
 
 
 
struct LogExportDeviceFacts: Equatable {
     
    var app: String
     
     
    var system: String
     
    var model: String
     
     
    var cellular: String?
    var exportedAt: Date
    /// CI 注入的 git 短哈希（`HAKO_BUILD_REVISION`）。版本号恒定 1.0.9 (1)，
    /// 没有它就是「装的是哪个包」只能靠猜（2026-10-21 排查控制通道时踩到）。
    var buildRevision: String?

    static func current(now: Date = Date()) -> LogExportDeviceFacts {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "?"
        let build = (info["CFBundleVersion"] as? String) ?? "?"
        let revision = info["HakoBuildRevision"] as? String
        #if os(iOS)
        let cellular: String? = radioName(CTTelephonyNetworkInfo().serviceCurrentRadioAccessTechnology)
        #else
        let cellular: String? = nil
        #endif
        return LogExportDeviceFacts(
            app: "\(version) (\(build))",
            system: "\(HakoDeviceModel.platformFallback) \(ProcessInfo.processInfo.operatingSystemVersionString)",
            model: HakoDeviceModel.identifier,
            cellular: cellular,
            exportedAt: now,
            buildRevision: revision
        )
    }

     
     
    static func radioName(_ radios: [String: String]?) -> String {
        let prefix = "CTRadioAccessTechnology"
        let names = (radios ?? [:])
            .sorted { $0.key < $1.key }
            .map { $0.value.hasPrefix(prefix) ? String($0.value.dropFirst(prefix.count)) : $0.value }
        return names.isEmpty ? "none" : names.joined(separator: ", ")
    }

    func render() -> String {
        var lines = [
            "app: \(app)",
            "system: \(system)",
            "model: \(model)",
        ]
        if let cellular {
            lines.append("cellular: \(cellular)")
        }
        if let buildRevision, !buildRevision.isEmpty {
            lines.append("build: \(buildRevision)")
        }
         
         
        lines.append("exported: \(Self.timestamp.string(from: exportedAt))")
        return lines.joined(separator: "\n") + "\n"
    }

    private static let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()
}
