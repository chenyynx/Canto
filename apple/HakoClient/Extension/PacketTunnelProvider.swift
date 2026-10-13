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
        HakoLogStore.shared.append(
            "tunnel extension launched  version=\(version) (\(build))",
            stream: .app, level: .warning)
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
        Task {
            let (reply, afterReply) = await provider.handleMessage(messageData)
            completionHandler?(reply)
            afterReply?()
        }
    }
}
