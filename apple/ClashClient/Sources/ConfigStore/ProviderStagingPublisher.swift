import Foundation
import Clash

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ProviderStagingPublisher {
     
     
     
     
     
     
     
     
     
     
#if os(macOS)
    static let extensionRuntimeProfile = ClashRuntimeProfileMacOSPacketTunnel
#elseif os(tvOS)
    static let extensionRuntimeProfile = ClashRuntimeProfileTVOSPacketTunnel
#else
    static let extensionRuntimeProfile = ClashRuntimeProfileIOSPacketTunnel
#endif

     
     
     
     
     
     
     
     
     
     
    static func publish(
        finalYAML: String,
        providerCount: Int,
        compileRuleSets: Bool
    ) {
        guard providerCount > 0 else { return }
        let started = DispatchTime.now().uptimeNanoseconds
        var error: NSError?
        let staged = AppCore.stageProvidersForPublish(
            finalYAML,
            Self.extensionRuntimeProfile,
            compileRuleSets,
            &error
        )
        let elapsed = (DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        guard staged, error == nil else {
             
             
             
             
            ClashLogStore.shared.append(
                "provider staging not published  reason=\(error?.localizedDescription ?? "unknown")",
                stream: .app,
                level: .warning
            )
            return
        }
        ClashLogStore.shared.append(
            "provider staging published  providers=\(providerCount)"
                + " compile=\(compileRuleSets) in=\(elapsed)ms",
            stream: .app
        )
    }
}
