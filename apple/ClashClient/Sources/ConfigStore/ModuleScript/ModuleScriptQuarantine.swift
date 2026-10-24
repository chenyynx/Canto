#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
final class ModuleScriptQuarantine: @unchecked Sendable {
    struct Entry: Codable, Equatable, Sendable {
        var sha256: String
        var scriptName: String
        var scriptPath: String
        var at: Date
        var timeoutSeconds: Double
         
        var reason: String
    }

    private struct Contents: Codable {
        var schemaVersion: Int
        var entries: [Entry]
    }

     
     
    static let fileName = #"module-scripts/quarantine.json"#
    static let currentSchemaVersion = 1

    let file: URL

    init(file: URL) {
        self.file = file
    }

    func entry(for sha256: String) -> Entry? {
        Self.read(file)[sha256.lowercased()]
    }

    var all: [Entry] {
        Self.read(file).values.sorted { $0.at < $1.at }
    }

     
     
     
    func add(_ entry: Entry, log: (String) -> Void) {
        var entries = Self.read(file)
        entries[entry.sha256.lowercased()] = entry
        let contents = Contents(schemaVersion: Self.currentSchemaVersion, entries: entries.values.sorted { $0.at < $1.at })
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        do {
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(contents).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            log(#"[script] the quarantine of \#(entry.scriptName) was not written: \#(error.localizedDescription)"#)
        }
    }

    private static func read(_ file: URL) -> [String: Entry] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let data = try? Data(contentsOf: file),
              let contents = try? decoder.decode(Contents.self, from: data) else { return [:] }
        var entries: [String: Entry] = [:]
        for entry in contents.entries { entries[entry.sha256.lowercased()] = entry }
        return entries
    }
}
#endif
