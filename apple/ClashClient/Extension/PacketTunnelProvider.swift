import NetworkExtension
import os.log

 
 
 
class PacketTunnelProvider: NEPacketTunnelProvider {
    private lazy var provider = ExtensionProvider(tunnelProvider: self)
    private static let launchLog = Logger(
        subsystem: "org.example.canto.demo.extension", category: "launch")
    #if os(iOS) || os(macOS)
     
    private static let modulesLog = Logger(subsystem: "org.example.canto.demo.extension", category: "modules")
     
     
     
     
     
    private lazy var modulesHost: ModuleEngineHost? = ModuleEngineLocations.production.map { locations in
        ModuleEngineHost(locations: locations, log: ModuleEngineLog { line in
            PacketTunnelProvider.modulesLog.notice("\(line, privacy: .public)")
            ClashLogStore.shared.append(line, stream: .app)
        }, scripts: ModuleScriptHostWiring.makeRunner(routing: ModuleScriptRouting(
            mode: { [weak self] in self?.provider.scriptRoutingMode() },
            setMode: { [weak self] mode in self?.provider.setScriptRoutingMode(mode) ?? false })), carriesEngineProxy: { revision in
            PacketTunnelProvider.runtimeDocument(in: locations.container, revision)
                .map { ModuleRuntimeDocumentScan.carriesInjectedEngine(at: $0, known: .read(locations)) } ?? false
        }, configure: { engine, inputs, reporter, scripts in
            ModuleEngineAssembly.configure(engine, inputs, reporter, locations: locations, scripts: scripts, thresholds: .current)
        })
    }

     
     
    private static func runtimeDocument(in container: URL, _ revision: ModuleRunningRevision) -> URL? {
        (try? ConfigResourceStore(containerURL: container))?
            .providersDirectory(profileID: revision.profileID, revision: revision.revision)?
            .deletingLastPathComponent().appendingPathComponent("config.resolved.yaml")
    }
    #endif

     
     
     
     
     
     
     
     
     
     
     
     
     
    override init() {
        super.init()
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        Self.launchLog.notice("tunnel extension launched  version=\(version, privacy: .public) (\(build, privacy: .public))")
        ClashLogStore.shared.append(
            "tunnel extension launched  version=\(version) (\(build))",
            stream: .app, level: .warning)
    }

    override func startTunnel(options: [String: NSObject]?) async throws {
         
        let userInitiated = (options?[ClashTunnelStart.userInitiatedStartOption] as? NSNumber)?.boolValue ?? false
        #if os(iOS) || os(macOS)
        provider.modulesHooks = modulesHost
        #endif
        do {
            try await provider.start(userInitiated: userInitiated)
        } catch {
            #if os(iOS) || os(macOS)
             
             
            modulesHost?.tunnelStopped()
            #endif
            throw error
        }
        #if os(iOS) || os(macOS)
         
        provider.widgetMailbox.start()


        #endif
    }

    override func stopTunnel(with reason: NEProviderStopReason) async {
        #if os(iOS) || os(macOS)
         
         
        provider.widgetMailbox.stop()
        #endif
        await provider.stop(reason: reason)
        #if os(iOS) || os(macOS)
         
        modulesHost?.tunnelStopped()
        #endif
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
