import Foundation
import NetworkExtension

 
 
 
 
 
 
 
 
@MainActor
protocol ClashTVSystemProfile: AnyObject {
    var isEnabled: Bool { get set }
    var isOnDemandEnabled: Bool { get set }
    var onDemandRules: [NEOnDemandRule]? { get set }
    var localizedDescription: String? { get set }
    var protocolConfiguration: NEVPNProtocol? { get set }
    var status: NEVPNStatus { get }
    var vpnConnection: NEVPNConnection? { get }
    func saveToPreferences() async throws
    func loadFromPreferences() async throws
     
     
    func removeFromPreferences() async throws
     
     
     
    func startVPNTunnel(userInitiated: Bool) throws
    func stopVPNTunnel()
     
    func lastDisconnectError() async -> Error?
}

extension NETunnelProviderManager: ClashTVSystemProfile {
    var status: NEVPNStatus { connection.status }
    var vpnConnection: NEVPNConnection? { connection }
    func startVPNTunnel(userInitiated: Bool) throws {
        try connection.startVPNTunnel(options: userInitiated ? [ClashTunnelStart.userInitiatedStartOption: NSNumber(value: true)] : nil)
    }
    func stopVPNTunnel() { connection.stopVPNTunnel() }
    func lastDisconnectError() async -> Error? {
        await withCheckedContinuation { continuation in
            connection.fetchLastDisconnectError { continuation.resume(returning: $0) }
        }
    }
}
