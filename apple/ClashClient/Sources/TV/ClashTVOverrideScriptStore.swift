import Foundation

 
 
 
 
 
 
 
enum ClashTVOverrideScriptStore {
    static func directory(container: URL) -> URL {
        container.appendingPathComponent("working", isDirectory: true)
            .appendingPathComponent("scripts", isDirectory: true)
    }

    static func url(container: URL, profileID: String) -> URL {
        directory(container: container).appendingPathComponent("\(profileID).js")
    }

    static func write(_ body: String, container: URL, profileID: String) throws {
        try FileManager.default.createDirectory(at: directory(container: container), withIntermediateDirectories: true)
        try Data(body.utf8).write(to: url(container: container, profileID: profileID), options: .atomic)
    }

     
     
    static func read(container: URL, profileID: String) -> String? {
        guard let body = try? String(contentsOf: url(container: container, profileID: profileID), encoding: .utf8),
              !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return body
    }

    static func remove(container: URL, profileID: String) {
        try? FileManager.default.removeItem(at: url(container: container, profileID: profileID))
    }
}
