import Foundation
#if os(iOS)
import UIKit
#endif

 
 
 
 
 
 
 
enum ModuleRouteHiding {
    private final class Names: @unchecked Sendable {
        let lock = NSLock()
        var value: Set<String>?
         
         
        var unreadable = false
        var unreadableStamp: Date?
        var retrying = false
         
         
         
        var lockedAway = false
        var observer: NSObjectProtocol?
    }

    private static let names = Names()

     
    nonisolated(unsafe) static var recordLocations: ModuleLocations? = ModuleLocations.production



     
     
    #if os(iOS)
    static let protectedDataNotification: Notification.Name? = UIApplication.protectedDataDidBecomeAvailableNotification
    #else
    static let protectedDataNotification: Notification.Name? = nil
    #endif

     
     
     
     
     
     
    static func hiddenNames() -> Set<String> {
        names.lock.lock()
        if let value = names.value {
            names.lock.unlock()
            return value
        }
        let file = recordLocations?.activationRecord
        if names.lockedAway {
            names.lock.unlock()
            return []
        }
        if names.unreadable {
            let stamp = file.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
            if stamp == names.unreadableStamp || names.retrying {
                names.lock.unlock()
                return []
            }
            if Thread.isMainThread {
                names.retrying = true
                names.lock.unlock()
                DispatchQueue.global(qos: .utility).async {
                    names.lock.lock()
                    names.retrying = false
                    names.lock.unlock()
                    _ = hiddenNames()
                }
                return []
            }
        }
        names.lock.unlock()
        return read(file)
    }

    private static func read(_ file: URL?) -> Set<String> {


        let stamp = file.flatMap { try? FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date }
        var data: Data?
        var lockedAway = false
        if let file, FileManager.default.fileExists(atPath: file.path) {
            do { data = try Data(contentsOf: file) } catch { lockedAway = true }
        }
         
         
        let record = data.flatMap { try? ModuleJSON.decoder().decode(ModulePublicationRecord.self, from: $0) }
        names.lock.lock()
        defer { names.lock.unlock() }
        if let value = names.value { return value }
        if lockedAway, let name = protectedDataNotification {
            names.lockedAway = true
            if names.observer == nil {
                names.observer = NotificationCenter.default.addObserver(forName: name, object: nil, queue: nil) { _ in
                    protectedDataBecameAvailable()
                }
            }
            return []
        }
        if lockedAway || (data != nil && record == nil) {
            names.unreadable = true
            names.unreadableStamp = stamp
            return []
        }
        names.unreadable = false
        let loaded = Set(record?.hiddenEngineName.map { [$0] } ?? [])
        names.value = loaded
        return loaded
    }

     
     
    static func protectedDataBecameAvailable() {
        names.lock.lock()
        let due = names.lockedAway || names.unreadable
        names.lockedAway = false
        names.unreadable = false
        names.lock.unlock()
        guard due else { return }
        DispatchQueue.global(qos: .utility).async { _ = hiddenNames() }
    }

     
    static func forget() {
        names.lock.lock()
        names.value = nil
        names.unreadable = false
        names.unreadableStamp = nil
        names.retrying = false
        names.lockedAway = false
        names.lock.unlock()
    }

     
     
    static func note(_ record: ModuleActivationRecord?) {
        note(engineName: record?.engineProxyName)
    }

     
     
    static func note(engineName: String?) {
        names.lock.lock()
        names.unreadable = false
        names.lockedAway = false
        names.value = Set(engineName.map { [$0] } ?? [])
        names.lock.unlock()
    }

     
     
     
    static let hiddenMembersKey = "x-clash-hidden-members"

     
     
     
    static func stripping(_ proxies: [String: Any], hiding names: Set<String>) -> [String: Any] {
        guard !names.isEmpty else { return proxies }
        var out: [String: Any] = [:]
        out.reserveCapacity(proxies.count)
        for (name, value) in proxies where !names.contains(name) {
            if var entry = value as? [String: Any], let all = entry["all"] as? [String], all.contains(where: names.contains) {
                entry["all"] = all.filter { !names.contains($0) }
                entry[hiddenMembersKey] = all.filter(names.contains)
                out[name] = entry
            } else {
                out[name] = value
            }
        }
        return out
    }

     
     
     
     
     
    static func enginesAmongNodes(of publication: ActiveConfigurationPointer?,
                                  locations: ModuleLocations? = ModuleLocations.production) -> Int {
         
        guard let publication, let record = ModulePublicationRecord.load(locations: locations), record.pointer == publication else {
            return 0
        }
        return record.hiddenEngineName == nil ? 0 : 1
    }

     
     
    static func nodeCount(_ count: Int?, of publication: ActiveConfigurationPointer?,
                          locations: ModuleLocations? = ModuleLocations.production) -> Int? {
        count.map { max(0, $0 - enginesAmongNodes(of: publication, locations: locations)) }
    }

     
     
     
    static func publishedNodeCount(profileID: String, store: ConfigResourceStore?,
                                   containerURL: URL? = ClashAppIdentifiers.appGroupContainer) -> Int? {
        nodeCount(OfflineProxyCatalogLoader.publishedNodeCount(profileID: profileID, containerURL: containerURL),
                  of: try? store?.activeIdentity(), locations: containerURL.map(ModuleLocations.init(container:)))
    }

    static func visible<Item>(_ items: [Item], name: (Item) -> String, hiding names: Set<String>) -> [Item] {
        guard !names.isEmpty else { return items }
        return items.filter { !names.contains(name($0)) }
    }
}
