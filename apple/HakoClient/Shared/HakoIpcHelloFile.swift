import Foundation

/// App↔隧道扩展 provider-message 通道的兜底文件。
///
/// 为什么需要它：全能签重签环境里 `sendProviderMessage` 会被系统当场拒绝
/// （2026-10-21 日志：connected 后 68ms 就失败），而隧道数据面与 Unix socket
/// 都是好的。扩展启动时把 hello 写进共享容器、之后每 60s 刷新一次；
/// App 在消息通道拿不到 hello 时读这个文件，直接去连 `clash.sock`。
/// `writtenAtUnix` 同时充当扩展存活证明（心跳停了就过期）。
///
/// 该文件写在共享 App Group 容器里；没有真实共享容器时不写、也不读——
/// 那种情况下 socket 本来就通不了，兜底没有意义。
enum HakoIpcHelloFile {
    static let relativePath = "ipc/hello.json"

    struct Payload: Codable, Equatable {
        let schemaVersion: Int32
        let minSchemaVersion: Int32
        let coreVersion: String
        let capabilities: [String]
        let processIdentifier: Int32
        let startedAtUnix: Int64
        let writtenAtUnix: Int64
    }

    /// 心跳间隔；App 侧按 3 倍容忍（180s）判活。
    static let heartbeatNanoseconds: UInt64 = 60 * 1_000_000_000
    static let maximumAgeSeconds: TimeInterval = 180

    static func url(in container: URL) -> URL {
        container.appendingPathComponent(relativePath, isDirectory: false)
    }

    static func write(_ payload: Payload, in container: URL) {
        let target = url(in: container)
        do {
            try FileManager.default.createDirectory(
                at: target.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(payload)
            try data.write(to: target, options: .atomic)
        } catch {
            // 兜底路径本身失败必须可见，而且不能受日志录制开关影响。
            HakoLogStore.shared.append(
                "ipc hello file write failed: \(error.localizedDescription)",
                stream: .app,
                level: .error,
                force: true
            )
        }
    }

    static func read(in container: URL) -> Payload? {
        guard let data = try? Data(contentsOf: url(in: container)) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}
