#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
struct ModuleScriptNotificationRecord: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    var schemaVersion: Int
    var id: String
    var at: Date
    var scriptName: String
    var title: String
    var subtitle: String
    var body: String
     
    var openURL: String?
     
     
    var clipboardText: String?
    var sound: Bool
     
     
    var mediaURL: String?
     
    var delaySeconds: Double?

    init(
        scriptName: String, title: String, subtitle: String, body: String,
        openURL: String? = nil, clipboardText: String? = nil, sound: Bool = false,
        mediaURL: String? = nil, delaySeconds: Double? = nil,
        id: String = UUID().uuidString, at: Date = Date()
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.id = id
        self.at = at
        self.scriptName = scriptName
        self.title = title
        self.subtitle = subtitle
        self.body = body
        self.openURL = openURL
        self.clipboardText = clipboardText
        self.sound = sound
        self.mediaURL = mediaURL
        self.delaySeconds = delaySeconds
    }
}

struct ModuleScriptNotificationMailbox: Sendable {
     
     
    static let directoryName = "module-scripts/notifications"
     
     
    static let darwinNotification = "clash.module.notification"
     
    static let pendingLimit = 32

    let directory: URL
    let notificationName: String

    init(container: URL, notificationName: String = ModuleScriptNotificationMailbox.darwinNotification) {
        directory = container.appendingPathComponent(Self.directoryName, isDirectory: true)
        self.notificationName = notificationName
    }

     
    static var production: ModuleScriptNotificationMailbox? {
        ClashAppIdentifiers.appGroupContainer.map { ModuleScriptNotificationMailbox(container: $0) }
    }

     
     
    @discardableResult
    func post(_ record: ModuleScriptNotificationRecord) throws -> Int {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let pending = pendingFiles()
        var dropped = 0
        if pending.count >= Self.pendingLimit {
            for stale in pending.prefix(pending.count - Self.pendingLimit + 1) {
                try? manager.removeItem(at: stale)
                dropped += 1
            }
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(record).write(
            to: directory.appendingPathComponent(Self.fileName(for: record)),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(notificationName as CFString), nil, nil, true)
        return dropped
    }

     
     
    func takeAll() -> (records: [ModuleScriptNotificationRecord], unreadable: Int) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var records: [ModuleScriptNotificationRecord] = []
        var unreadable = 0
        for url in pendingFiles() {
            defer { try? FileManager.default.removeItem(at: url) }
            guard let data = try? Data(contentsOf: url),
                  let record = try? decoder.decode(ModuleScriptNotificationRecord.self, from: data) else {
                unreadable += 1
                continue
            }
            records.append(record)
        }
        return (records, unreadable)
    }

     
    static func fileName(for record: ModuleScriptNotificationRecord) -> String {
        String(format: "%015lld", Int64(record.at.timeIntervalSince1970 * 1000)) + "-" + record.id + ".json"
    }

    private func pendingFiles() -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted().map { directory.appendingPathComponent($0) }
    }
}
#endif
