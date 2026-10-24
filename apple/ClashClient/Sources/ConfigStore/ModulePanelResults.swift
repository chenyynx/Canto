#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
struct ModulePanelResult: Codable, Equatable, Sendable {
    var title: String?
    var content: String?
    var icon: String?
    var iconColor: String?
    var style: String?
     
    var at: Date
}

enum ModulePanelResults {
    static let fileName = "panels.json"

     
    static func key(module: String, panel: String) -> String { "\(module)/\(panel)" }

    static func load(container: URL) -> [String: ModulePanelResult] {
        guard let data = try? Data(contentsOf: file(container)),
              let read = try? JSONDecoder().decode([String: ModulePanelResult].self, from: data) else { return [:] }
        return read
    }

    static func save(_ results: [String: ModulePanelResult], container: URL) {
        guard let data = try? JSONEncoder().encode(results) else { return }
        let file = file(container)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    static func file(_ container: URL) -> URL {
        ModuleLocations(container: container).stateFile.deletingLastPathComponent().appendingPathComponent(fileName, isDirectory: false)
    }
}
#endif
