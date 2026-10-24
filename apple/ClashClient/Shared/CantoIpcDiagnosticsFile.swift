import Foundation

/// 运行时诊断快照的中转文件。
///
/// 为什么需要：连接列表的「运行时身份确认」（core pid / 启动时间 / profile）
/// 依赖 `runtimeDiagnostics`，而它只走 provider message 通道——重签环境里这条
/// 通道被系统静默拒绝，于是整页永远停在「正在加载连接」。
/// 这里让扩展在收到 App 的请求标记后把同一份 JSON 写进共享容器，App 读文件。
/// 用「请求标记 mtime」按需写，避免常驻每秒写闪存。
enum CantoIpcDiagnosticsFile {
    static let relativePath = "ipc/diagnostics.json"
    static let requestRelativePath = "ipc/diagnostics.request"
    /// 请求标记的有效期；扩展只在标记新鲜时写文件。
    static let requestLifetimeSeconds: TimeInterval = 10
    /// App 只接受这么新的快照（扩展的写延迟是 1s 轮询）。
    static let maximumAgeSeconds: TimeInterval = 5

    static func url(in container: URL) -> URL {
        container.appendingPathComponent(relativePath, isDirectory: false)
    }

    static func requestURL(in container: URL) -> URL {
        container.appendingPathComponent(requestRelativePath, isDirectory: false)
    }

    static func request(in container: URL) {
        let target = requestURL(in: container)
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let stamp = "\(Int(Date().timeIntervalSince1970))\n"
            try Data(stamp.utf8).write(to: target, options: .atomic)
        } catch {
            ClashLogStore.shared.append(
                "ipc diagnostics request failed: \(error.localizedDescription)",
                stream: .app,
                level: .error,
                force: true
            )
        }
    }

    static func requestAge(in container: URL, now: Date = Date()) -> TimeInterval? {
        let target = requestURL(in: container)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: target.path),
              let modified = attributes[.modificationDate] as? Date
        else { return nil }
        return now.timeIntervalSince(modified)
    }

    static func write(_ data: Data, in container: URL) {
        let target = url(in: container)
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: target, options: .atomic)
        } catch {
            ClashLogStore.shared.append(
                "ipc diagnostics write failed: \(error.localizedDescription)",
                stream: .app,
                level: .error,
                force: true
            )
        }
    }

    static func read(in container: URL, now: Date = Date()) -> (data: Data, age: TimeInterval)? {
        let target = url(in: container)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: target.path),
              let modified = attributes[.modificationDate] as? Date,
              let data = try? Data(contentsOf: target)
        else { return nil }
        return (data, now.timeIntervalSince(modified))
    }
}
