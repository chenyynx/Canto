import Foundation
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct StorageMaintenance {
    enum Area: String, CaseIterable, Hashable, Sendable {
        case configurations, library, geodata, providerCaches, compiledGeodata, logs, temporary
    }

    struct Measurement: Equatable, Sendable {
        let area: Area
         
        let bytes: Int64
         
        let reclaimable: Int64
    }

    struct Outcome: Equatable, Sendable {
        var reclaimedBytes: Int64 = 0
        var areas: [Area] = []
    }

    let containerURL: URL
     
     
    let tunnelIsRunning: () -> Bool

    init(containerURL: URL, tunnelIsRunning: @escaping () -> Bool) {
        self.containerURL = containerURL
        self.tunnelIsRunning = tunnelIsRunning
    }

     
     
     
     
     
    private let storedReferencesOnce = StoredReferencesOnce()
    private func storedReferences() -> Result<NodeLibraries.StoredReferences, Error> {
        storedReferencesOnce.value { Result { try NodeLibraries.storedReferences(container: containerURL) } }
    }

    static let namedGeodataFiles = GeodataManager.namedGeodataFiles

    private var working: URL { containerURL.appendingPathComponent("working", isDirectory: true) }
    private var fileManager: FileManager { .default }

     

    func measure() -> [Measurement] { Area.allCases.map(measure) }

    func measure(_ area: Area) -> Measurement {
         
         
        let elsewhere = area == .configurations
            ? temporaryItems().filter { $0.lastPathComponent.hasPrefix(".tmp-") }
            : []
        let bytes = StorageMeasurement.allocatedBytes(at: paths(area), excluding: elsewhere)
         
         
         
        let remaining = StorageMeasurement.allocatedBytes(
            at: paths(area), excluding: elsewhere + reclaimableItems(area)
        )
        return Measurement(area: area, bytes: bytes, reclaimable: max(0, bytes - remaining))
    }

     
    func paths(_ area: Area) -> [URL] {
        switch area {
        case .configurations:
            return [working.appendingPathComponent("store", isDirectory: true),
                    working.appendingPathComponent("payloads", isDirectory: true),
                     
                    NodeLibraries.directory(container: containerURL)]
        case .library:
            return [working.appendingPathComponent("configuration-library", isDirectory: true)]
        case .geodata:
            return [working.appendingPathComponent("geodata", isDirectory: true)]
                + Self.namedGeodataFiles.map { working.appendingPathComponent($0) }
        case .providerCaches:
            return [working.appendingPathComponent("provider-runtime", isDirectory: true)]
        case .compiledGeodata:
            return [working.appendingPathComponent("compiled-geoip", isDirectory: true),
                    working.appendingPathComponent("compiled-geosite", isDirectory: true)]
        case .logs:
            return [containerURL.appendingPathComponent("logs", isDirectory: true)]
        case .temporary:
            return temporaryItems()
        }
    }

     
    func reclaimableItems(_ area: Area) -> [URL] {
        switch area {
        case .configurations:
            guard let store = try? ConfigResourceStore(containerURL: containerURL) else { return [] }
            return ((try? store.orphanedProfileDirectories(registered: registeredProfileIDs())) ?? [])
                + ((try? store.supersededRevisionDirectories()) ?? [])
                + store.payloadStore.unreferencedBlobs()
                + NodeLibraries.prunable(container: containerURL, references: storedReferences())
        case .logs:
            return staleLogFiles()
        case .library, .providerCaches:
            return []
        case .geodata:
            return GeodataManager.staleGeodataBlobs(homeDir: working)
        case .compiledGeodata:
            return tunnelIsRunning() ? [] : paths(.compiledGeodata).filter { fileManager.fileExists(atPath: $0.path) }
        case .temporary:
            return temporaryItems()
        }
    }

     

     
     
    @discardableResult
    func reclaim() throws -> Outcome { try reclaim(Set(Area.allCases)) }

     
     
    @discardableResult
    func reclaim(_ areas: Set<Area>) throws -> Outcome {
        var outcome = Outcome()
        for area in Area.allCases where areas.contains(area) {
            let before = measure(area).reclaimable
            guard before > 0 else { continue }
            switch area {
            case .configurations:
                let store = try ConfigResourceStore(containerURL: containerURL)
                try store.removeOrphanedProfileDirectories(registered: registeredProfileIDs())
                try store.removeSupersededRevisionDirectories()
                 
                 
                 
                try store.removeUnreferencedPayloadBlobs()
                 
                 
                 
                NodeLibraries.prune(container: containerURL, references: storedReferences())
            case .logs:
                for url in staleLogFiles() { try? fileManager.removeItem(at: url) }
            case .geodata:
                GeodataManager.removeStaleGeodataBlobs(homeDir: working)
            case .compiledGeodata:
                guard !tunnelIsRunning() else { continue }
                for url in paths(.compiledGeodata) { try? fileManager.removeItem(at: url) }
            case .temporary:
                for url in temporaryItems() { try? fileManager.removeItem(at: url) }
            case .library, .providerCaches:
                continue
            }
            let freed = before - measure(area).reclaimable
            if freed > 0 {
                outcome.reclaimedBytes += freed
                outcome.areas.append(area)
            }
        }
        return outcome
    }

     

     
     
    func registeredProfileIDs() -> Set<String> {
        let store = ProfileStore(fileURL: working.appendingPathComponent("store/profiles.json"))
        var ids = Set(store.load().map(\.id))
        let library = ConfigurationLibraryStore(directory: working.appendingPathComponent("configuration-library"))
        if let pending = try? library.snapshot().pendingPublications {
            ids.formUnion(pending.map(\.profileID))
        }
        return ids
    }

     
     
     
     
     
     
     
    func retiredDashboardDirectories() -> [URL] {
        let own: Set<String> = [
            "store", "configuration-library", "geodata", "payloads", "provider-runtime",
            "compiled-geoip", "compiled-geosite", "active", "proxies",
        ]
        let entries = (try? fileManager.contentsOfDirectory(
            at: working, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .filter { !own.contains($0.lastPathComponent) }
            .filter { directory in
                if fileManager.fileExists(atPath: directory.appendingPathComponent("index.html").path) { return true }
                let children = (try? fileManager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
                )) ?? []
                return children.contains {
                    fileManager.fileExists(atPath: $0.appendingPathComponent("index.html").path)
                }
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

     
     
     
     
     
    func staleLogFiles(now: Date = Date()) -> [URL] {
        let directory = paths(.logs)[0]
        let live = Set(ClashLogStore.mirrorableFileNames(now: now))
        let entries = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]
        )) ?? []
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .filter { ClashLogStore.isDayFileName($0.lastPathComponent) && !live.contains($0.lastPathComponent) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

     
     
    private func temporaryItems() -> [URL] {
        var items: [URL] = []
        let temp = containerURL.appendingPathComponent("temp", isDirectory: true)
        if fileManager.fileExists(atPath: temp.path) { items.append(temp) }
        items += retiredDashboardDirectories()
        let store = working.appendingPathComponent("store", isDirectory: true)
        if let enumerator = fileManager.enumerator(at: store, includingPropertiesForKeys: [.isDirectoryKey], options: []) {
            for case let url as URL in enumerator where url.lastPathComponent.hasPrefix(".tmp-") {
                items.append(url)
                enumerator.skipDescendants()
            }
        }
        return items
    }
}

 
 
 
 
 
enum StorageMeasurement {
    static func allocatedBytes(at url: URL, fileManager: FileManager = .default) -> Int64 {
        allocatedBytes(at: [url], excluding: [], fileManager: fileManager)
    }

     
     
    static func allocatedBytes(
        at urls: [URL], excluding: [URL] = [], fileManager: FileManager = .default
    ) -> Int64 {
        let excluded = excluding.map { $0.standardizedFileURL.path }
        func isExcluded(_ url: URL) -> Bool {
            let path = url.standardizedFileURL.path
            return excluded.contains { path == $0 || path.hasPrefix($0 + "/") }
        }
        let keys: Set<URLResourceKey> = [
            .isDirectoryKey, .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey,
            .fileResourceIdentifierKey,
        ]
        var seen = Set<NSObject>()
        var total: Int64 = 0
        func count(_ file: URL, _ values: URLResourceValues) {
            guard values.isRegularFile == true else { return }
            if let identifier = values.fileResourceIdentifier as? NSObject {
                guard seen.insert(identifier).inserted else { return }
            }
            total += Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
        }
        for url in urls where !isExcluded(url) {
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            if values.isDirectory != true {
                count(url, values)
                continue
            }
            guard let enumerator = fileManager.enumerator(
                at: url, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles]
            ) else { continue }
            for case let child as URL in enumerator {
                if isExcluded(child) {
                    if (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                        enumerator.skipDescendants()
                    }
                    continue
                }
                guard let childValues = try? child.resourceValues(forKeys: keys) else { continue }
                count(child, childValues)
            }
        }
        return total
    }
}

 
 
final class StoredReferencesOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var read: Result<NodeLibraries.StoredReferences, Error>?
    func value(_ make: () -> Result<NodeLibraries.StoredReferences, Error>) -> Result<NodeLibraries.StoredReferences, Error> {
        lock.lock(); defer { lock.unlock() }
        if let read { return read }
        let made = make()
        read = made
        return made
    }
}
