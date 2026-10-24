import Foundation
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashTVProviderCatalog: Codable, Equatable {
    struct Entry: Codable, Equatable, Identifiable {
         
        let kind: String
        let name: String
         
         
         
        var url: String? = nil
         
         
         
         
        var updatedAt: Date?
         
         
        var note: ClashTVProviderNote? = nil

        init(kind: String, name: String, url: String? = nil, updatedAt: Date?, note: ClashTVProviderNote? = nil) {
            self.kind = kind
            self.name = name
            self.url = url
            self.updatedAt = updatedAt
            self.note = note
        }

         
        init(kind: String, name: String, updatedAt: Date?, failure: String?, pending: Bool? = nil) {
            self.init(kind: kind, name: name, updatedAt: updatedAt,
                      note: failure.map { ClashTVProviderNote(recorded: $0) } ?? (pending == true ? .tunnelFetches : nil))
        }

         
         
        var failure: String? { note?.isFailure == true ? note?.text : nil }
         
        var pending: Bool { note?.awaitsTunnel ?? false }

         
         
         
         
        var id: String { "\(kind):\(name)" }

         
        private enum Field: String, CodingKey { case kind, name, url, updatedAt, note, failure, pending }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Field.self)
            kind = try c.decode(String.self, forKey: .kind)
            name = try c.decode(String.self, forKey: .name)
            url = try c.decodeIfPresent(String.self, forKey: .url)
            updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
            if let typed = try c.decodeIfPresent(ClashTVProviderNote.self, forKey: .note) {
                note = typed
            } else if let failure = try c.decodeIfPresent(String.self, forKey: .failure) {
                note = ClashTVProviderNote(recorded: failure)
            } else {
                note = try c.decodeIfPresent(Bool.self, forKey: .pending) == true ? .tunnelFetches : nil
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: Field.self)
            try c.encode(kind, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encodeIfPresent(url, forKey: .url)
            try c.encodeIfPresent(updatedAt, forKey: .updatedAt)
            try c.encodeIfPresent(note, forKey: .note)
        }
    }

    var entries: [Entry]
     
     
    var sourceSHA256: String? = nil
     
     
     
    var ruleSetsLeftToTheTunnel: Bool? = nil

    static let fileName = "providers.json"

    var readyCount: Int { entries.filter { $0.failure == nil && !$0.pending }.count }

    func write(to directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

     
     
     
     
    static func read(from directory: URL) -> ClashTVProviderCatalog? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        return try? JSONDecoder().decode(ClashTVProviderCatalog.self, from: data)
    }

     
     
     
    static func isSidecar(_ path: String) -> Bool {
        [fileName, ClashTVRuleRecovery.fileName, ClashTVRuleFacts.fileName].contains((path as NSString).lastPathComponent)
    }

    static func providerFileCount(in paths: [String]) -> Int {
        paths.filter { !isSidecar($0) }.count
    }
}

extension ClashTVProviderCatalog.Entry {
     
     
     
     
     
    static var prototype: [ClashTVProviderCatalog.Entry] {
        let now = Date()
        return [
            .init(kind: "proxy", name: "nodes", url: "https://example.com/nodes.yaml",
                  updatedAt: now.addingTimeInterval(-18 * 60)),
            .init(kind: "proxy", name: "walled", url: "https://example.com/walled.yaml", updatedAt: nil,
                  note: .fetchedByCore(outbound: "Proxy")),
            .init(kind: "proxy", name: "backup", url: "https://example.com/backup.yaml", updatedAt: nil,
                  note: .downloadFailed(.verbatim("The request timed out."))),
            .init(kind: "rule", name: "streaming", url: "https://example.com/streaming.yaml",
                  updatedAt: now.addingTimeInterval(-18 * 60)),
            .init(kind: "rule", name: "ads", url: "https://example.com/ads.yaml", updatedAt: nil, note: .tunnelFetches),
            .init(kind: "rule", name: "mine", updatedAt: nil, note: .inline),
        ]
    }
}

extension AuthoredText {
     
     
    var text: String {
        switch self {
        case .verbatim(let text): return text
        case .app(let key, let arguments):
            let format = key.localizedForTelevision
            return arguments.isEmpty ? format : String(format: format, arguments: arguments.map { $0 as CVarArg })
        }
    }
}

extension ClashTVProviderCatalog.Entry {
     
     
     
    static var prototypeRecord: ProviderRefreshState? {
        let checked = Int64(Date().addingTimeInterval(-5 * 60).timeIntervalSince1970)
        return ProviderRefreshState.decode(Data("""
        {"version":2,"running":{"providers":{"proxy:walled":"k-walled"}},
         "entries":{"k-walled":{"kind":"proxy","url":"https://example.com/walled.yaml","result":"unchanged","lastCheckedAt":\(checked)}}}
        """.utf8))
    }
}

 
 
 
enum ClashTVProviderNote: Hashable, Codable, Sendable {
     
     
    case tunnelFetches
     
     
    case fetchedByCore(outbound: String)
     
    case downloadFailed(AuthoredText)
     
     
    case unreadable(AuthoredText)
     
    case inline

    var isFailure: Bool {
        switch self {
        case .downloadFailed, .unreadable: true
        case .tunnelFetches, .fetchedByCore, .inline: false
        }
    }

     
    var awaitsTunnel: Bool {
        switch self {
        case .tunnelFetches, .fetchedByCore, .downloadFailed: true
        case .unreadable, .inline: false
        }
    }

     
     
    var text: String {
        switch self {
        case .tunnelFetches, .fetchedByCore: String(localized: "Downloads when connected")
        case .downloadFailed(let reason): AuthoredText.app("Download failed: %@", arguments: [reason.text]).text
        case .unreadable(let reason): reason.text
        case .inline: String(localized: "Ready")
        }
    }

     
     
    init(recorded sentence: String) {
        switch sentence {
        case ClashTVProviderMaterializer.unreadablePayload: self = .unreadable(.app(sentence))
        default: self = .unreadable(.verbatim(sentence))
        }
    }
}
