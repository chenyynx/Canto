#if os(iOS) || os(macOS)
import CryptoKit
import Foundation

 
 
 
 
 
 
 
 
 
 
final class ModuleScriptStore {
    struct Limits: Equatable, Sendable {
         
        var valueBytes: Int
         
        var totalBytes: Int

         
         
        static var platformDefault: Limits {
            let table = ModuleScriptLimitsTable.current
            return Limits(valueBytes: table.storeValueBytes, totalBytes: table.storeTotalBytes)
        }
    }

     
    struct Owner: Equatable, Sendable {
        var family: ModuleScriptFamily
         
        var scriptPath: String
         
        var name: String

        init(family: ModuleScriptFamily, scriptPath: String, name: String) {
            self.family = family
            self.scriptPath = scriptPath
            self.name = name
        }

        init(_ declaration: ModuleScriptDeclaration) {
            self.init(family: declaration.family, scriptPath: declaration.scriptPath, name: declaration.name)
        }
    }

     
    static let quotaExceeded = #"$persistentStore: quota exceeded"#
     
     
     
    static let directoryName = #"module-scripts/store"#
     
     
    static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    private struct Entry: Codable {
        var scope: String
        var key: String
        var value: String
    }

    let directory: URL
    let limits: Limits
    private let log: (String) -> Void
    private let known = NSLock()
    private var knownTotal: Int?

    init(directory: URL, limits: Limits = .platformDefault, log: @escaping (String) -> Void) {
        self.directory = directory
        self.limits = limits
        self.log = log
    }

     
    var totalBytes: Int { loadSizes().values.reduce(0, +) }

     
     
     
     
    var knownTotalBytes: Int {
        known.lock()
        let cached = knownTotal
        known.unlock()
        if let cached { return cached }
        return note(totalBytes)
    }

    @discardableResult
    private func note(_ total: Int) -> Int {
        known.lock()
        knownTotal = total
        known.unlock()
        return total
    }

    func read(key: String?, by owner: Owner) -> String? {
        read(Self.slot(key: key, owner: owner))
    }

     
     
    @discardableResult
    func write(_ value: String?, key: String?, by owner: Owner) -> Bool {
        write(value, to: Self.slot(key: key, owner: owner))
    }

     
     
     
    func readShared(key: String) -> String? {
        read((Self.sharedScope, key))
    }

    @discardableResult
    func writeShared(_ value: String?, key: String) -> Bool {
        write(value, to: (Self.sharedScope, key))
    }

     
     
    @discardableResult
    func remove() -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var cleared = true
        for url in files where url.pathExtension == "json" {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                cleared = false
                log(#"$persistentStore: \#(url.lastPathComponent) not removed: \#(error.localizedDescription)"#)
            }
        }
        note(cleared ? 0 : totalBytes)
        return cleared
    }

    private func read(_ slot: Slot) -> String? {
        guard let data = try? Data(contentsOf: file(slot)),
              let entry = try? JSONDecoder().decode(Entry.self, from: data),
              entry.scope == slot.scope, entry.key == slot.key else { return nil }
        return entry.value
    }

    private func write(_ value: String?, to slot: Slot) -> Bool {
        let url = file(slot)
        guard let value else {
            try? FileManager.default.removeItem(at: url)
            note(totalBytes)
            return true
        }
        let sizes = loadSizes()
        guard let data = try? JSONEncoder().encode(Entry(scope: slot.scope, key: slot.key, value: value)) else { return false }
        let others = sizes.filter { $0.key != url.lastPathComponent }.values.reduce(0, +)
        guard value.utf8.count <= limits.valueBytes, others + data.count <= limits.totalBytes else {
            note(sizes.values.reduce(0, +))
            log(#"\#(Self.quotaExceeded) (\#(slot.scope) \#(slot.key): \#(value.utf8.count) bytes; the store holds "#
                + #"\#(others) of \#(limits.totalBytes) bytes, one value at most \#(limits.valueBytes))"#)
            return false
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: url, options: Self.writeOptions)
        } catch {
            note(sizes.values.reduce(0, +))
            log(#"$persistentStore: \#(slot.scope) \#(slot.key) not written: \#(error.localizedDescription)"#)
            return false
        }
        note(others + data.count)
        return true
    }

    private typealias Slot = (scope: String, key: String)
    private static let sharedScope = "shared"

     
     
     
     
     
     
    private static func slot(key: String?, owner: Owner) -> Slot {
        if let key { return (sharedScope, key) }
        switch owner.family {
        case .surge, .shadowrocket: return ("script", owner.scriptPath)
         
        case .loon, .stash, .quantumultX: return (sharedScope, owner.name)
        }
    }

     
     
    private func file(_ slot: Slot) -> URL {
        let digest = SHA256.hash(data: Data((slot.scope + "\u{0}" + slot.key).utf8))
            .map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }

     
     
     
    private func loadSizes() -> [String: Int] {
        var found: [String: Int] = [:]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        for url in files where url.pathExtension == "json" {
            found[url.lastPathComponent] = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return found
    }
}
#endif
