import Foundation
import NetworkExtension
import os.log

 
 
 
class PacketTunnelProvider: NEPacketTunnelProvider {
    private lazy var provider = ExtensionProvider(tunnelProvider: self)
    private static let launchLog = Logger(
        subsystem: "org.example.hako.demo.extension", category: "launch")

     
     
     
     
     
     
     
     
     
     
     
     
     
    override init() {
        super.init()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        Self.launchLog.notice("tunnel extension launched  version=\(version, privacy: .public) (\(build, privacy: .public))")
        // force：用户关掉「日志录制」时也必须留下——扩展重启次数是排查
        // 「控制通道断开」的关键证据（2026-10-21 日志里这条一行都没有）。
        HakoLogStore.shared.append(
            "tunnel extension launched  version=\(version) (\(build)) pid=\(ProcessInfo.processInfo.processIdentifier)",
            stream: .app, level: .warning, force: true)
    }

    override func startTunnel(options _: [String: NSObject]?) async throws {
        try await provider.start()
        #if os(iOS) || os(macOS)
         
        provider.widgetMailbox.start()
        provider.anchorMailbox.start()
        #endif
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        #if os(iOS) || os(macOS)
         
         
        provider.widgetMailbox.stop()
        provider.anchorMailbox.stop()
        #endif
        await provider.stop(reason: reason)
    }

    override func sleep() async {
        provider.sleep()
    }

    override func wake() {
        provider.wake()
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    override func handleAppMessage(_ messageData: Data, completionHandler: ((Data?) -> Void)?) {
        // 2026-10-21：App 侧日志证明 hello 在 connected 后 68ms 就失败，
        // 但无法区分「系统没把消息送到扩展」和「扩展收到却没回」。
        // 这里在入口和出口各打一行（force 写入，不受录制开关影响）。
        let began = DispatchTime.now().uptimeNanoseconds
        let command = Self.commandName(in: messageData)
        HakoLogStore.shared.append(
            "ipc-in begin cmd=\(command) bytes=\(messageData.count) pid=\(ProcessInfo.processInfo.processIdentifier)",
            stream: .app, level: .info, force: true
        )
        Task {
            let (reply, afterReply) = await provider.handleMessage(messageData)
            let elapsed = (DispatchTime.now().uptimeNanoseconds &- began) / 1_000_000
            HakoLogStore.shared.append(
                "ipc-in reply cmd=\(command) bytes=\(reply.count) took=\(elapsed)ms",
                stream: .app, level: .info, force: true
            )
            completionHandler?(reply)
            afterReply?()
        }
    }

    private static func commandName(in data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let command = object["cmd"] as? String
        else { return "?" }
        return command
    }
}
