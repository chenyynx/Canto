import CryptoKit
import Foundation
import Clash
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
enum ClashTVPendingSeeds {
     
    struct Entry: Decodable, Equatable {
        let kind: String
        let name: String
         
        let payloadPath: String?
        let seed: String?
        let expectedConfigSHA256: String?
         
        let result: String?
         
        let error: String?

         
        var handOver: (path: String, seed: String, expected: String)? {
            guard let payloadPath, !payloadPath.isEmpty, let seed, let expectedConfigSHA256 else { return nil }
            return (payloadPath, seed, expectedConfigSHA256)
        }
    }

    static func decode(_ json: String) throws -> [Entry] {
        try JSONDecoder().decode([Entry].self, from: Data(json.utf8))
    }

     
    static let extensionRuntimeProfile = ClashRuntimeProfileTVOSPacketTunnel

     
     
     
     
    static func prepare(container: URL, publishedConfig: String) throws -> String {
        try AppCoreSetup.ensure(container: container)
        var error: NSError?
        let answer = AppCore.preparePendingProviderSeeds(publishedConfig, extensionRuntimeProfile, &error)
         
        if answer.trimmingCharacters(in: .whitespacesAndNewlines) != "[]" { AppCore.returnFreeMemory() }
        if let error { throw error }
        return answer
    }

     
     
     
     
     
     
     
    static func runningConfiguration(container: URL, sha256: String) -> String? {
        func matches(_ data: Data) -> Bool {
            SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == sha256.lowercased()
        }
        if let current = (try? ConfigResourceStore(containerURL: container).loadCurrent())?.text,
           matches(Data(current.utf8)) { return current }
        var found: String?
        ClashTVConfigPipeline.eachStoredConfiguration(container: container) { data in
            guard matches(data) else { return true }
            found = String(data: data, encoding: .utf8)
            return false
        }
        return found
    }

     
     
     
    static func waitsForTheApp(_ state: ProviderRefreshState?) -> Bool {
        guard let state, let running = state.running else { return false }
        return running.providers.values.contains { state.entries[$0]?.result == .pendingApp }
    }
}
