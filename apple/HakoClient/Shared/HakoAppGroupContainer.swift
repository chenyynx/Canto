import Foundation

 
 
extension HakoAppIdentifiers {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let appGroupContainer: URL? = {
        let root = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroup)
#if os(tvOS)
        let resolved = root?
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Caches", isDirectory: true)
#else
        let resolved = root
#endif
        // Sideload 降级（2026-10-14）：全能签/企业签等重签名描述文件不含 App Group
        // entitlement → containerURL 返回 nil → 全部配置存储失败，首页报
        // "无法准备本地 Direct 配置"。此时回落到 App 自己沙盒的 Documents/HakoAppGroup
        // 目录：主 App 功能完整可用（Widget/扩展与主 App 的共享失效，属预期降级——
        // 没有 networkextension entitlement 隧道本就无法运行）。
        if let resolved { return resolved }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let fallback = docs.appendingPathComponent("HakoAppGroup", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }()
}
