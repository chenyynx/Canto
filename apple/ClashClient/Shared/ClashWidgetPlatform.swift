import Foundation

 
 
 
 
 
 
 
 
 
 
enum ClashWidgetPlatform {
    static var countsWired: Bool {
        #if os(macOS)
        return true
        #else
        return false
        #endif
    }
}

 
 
 
extension ClashAppIdentifiers {
     
     
     
     
     
     
    static let packetTunnelProviderBundleIDs: Set<String> = [
        packetTunnelExtensionBundleID,
        macPacketTunnelExtensionBundleID,
    ]
}
