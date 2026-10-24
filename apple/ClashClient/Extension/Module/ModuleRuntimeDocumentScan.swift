#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleRuntimeDocumentScan {
    static let chunkBytes = 64 * 1024
     
     
    static let engineProxyName = ModuleRuntimeNames.current.engineProxy
    static let reinjectListenerName = ModuleRuntimeNames.current.reinjectListener
     
    static let maximumLineBytes = 1024

     
     
    struct Known: Equatable, Sendable {
        var enginePorts: Set<UInt16> = []
        var engineUsernames: Set<String> = []
        var reinjectPorts: Set<UInt16> = []
        var reinjectUsernames: Set<String> = []
        var isEmpty: Bool { enginePorts.isEmpty && engineUsernames.isEmpty && reinjectPorts.isEmpty && reinjectUsernames.isEmpty }

         
        static func read(_ locations: ModuleEngineLocations) -> Known {
            var known = Known()
            if case .index(let plan) = ModuleEnginePlan.read(locations) {
                for record in plan.records {
                    guard case .recorded(let assignment, _, _) = record.state else { continue }
                    known.enginePorts.insert(assignment.ports.engine)
                    known.reinjectPorts.insert(assignment.ports.reinject)
                    if let credentials = assignment.engineProxyCredentials { known.engineUsernames.insert(credentials.username) }
                    if let credentials = assignment.reinjectCredentials { known.reinjectUsernames.insert(credentials.username) }
                }
            }
             
             
             
            struct SignIn: Decodable { let username: String }
            if case .values(let values, _) = ModuleTopLevelJSON.values(
                of: ["ports", "reinjectCredentials", "engineProxyCredentials"], in: locations.globalManifest,
                maximumBytes: ModuleReader.maximumListBytes, maximumValueBytes: 4_096) {
                if let raw = values["ports"], let ports = try? ModuleJSON.decoder().decode(ModulePorts.self, from: raw) {
                    known.enginePorts.insert(ports.engine)
                    known.reinjectPorts.insert(ports.reinject)
                }
                if let raw = values["engineProxyCredentials"], let signIn = try? ModuleJSON.decoder().decode(SignIn.self, from: raw) {
                    known.engineUsernames.insert(signIn.username)
                }
                if let raw = values["reinjectCredentials"], let signIn = try? ModuleJSON.decoder().decode(SignIn.self, from: raw) {
                    known.reinjectUsernames.insert(signIn.username)
                }
            }
            return known
        }
    }

     
     
    static func carriesInjectedEngine(at url: URL, known: Known = Known(),
                                      chunkBytes: Int = ModuleRuntimeDocumentScan.chunkBytes) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        var scanner = Scanner(known: known)
         
        var line = Data()
        _ = ModuleChunkedRead.each(handle, chunkBytes: chunkBytes) { chunk in
            var start = chunk.startIndex
            while let newline = chunk[start...].firstIndex(of: UInt8(ascii: "\n")) {
                let room = max(0, maximumLineBytes - line.count)
                if room > 0 { line.append(chunk[start..<min(newline, start + room)]) }
                scanner.take(line)
                line.removeAll(keepingCapacity: true)
                start = newline + 1
                if scanner.found { return false }
            }
            let room = max(0, maximumLineBytes - line.count)
            if room > 0 { line.append(chunk[start..<min(chunk.endIndex, start + room)]) }
            return true
        }
        if !scanner.found, !line.isEmpty { scanner.take(line) }
        scanner.finish()
        return scanner.found
    }

     
     
    struct Scanner {
        let known: Known
        private(set) var found = false
        private var section = ""
         
        struct Item {
            var fields: [String: String] = [:]
            var usernames: Set<String> = []
        }
        private var item: Item?
         
        private var itemIndent: Int?

        init(known: Known) { self.known = known }

        mutating func take(_ bytes: Data) {
            let text = String(decoding: bytes, as: UTF8.self)
            let indent = text.prefix { $0 == " " }.count
            let body = text.dropFirst(indent).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if body.isEmpty || body.hasPrefix("#") { return }
            if indent == 0, !body.hasPrefix("-") {
                finish()
                section = String(body.prefix { $0 != ":" })
                itemIndent = nil
                return
            }
            guard section == "proxies" || section == "listeners" else { return }
            let isDash = body.hasPrefix("- ") || body == "-"
            if isDash, itemIndent == nil || indent <= itemIndent! {
                finish()
                itemIndent = indent
                let rest = body.dropFirst(1).trimmingCharacters(in: .whitespaces)
                if rest.hasPrefix("{") {
                    judge(Self.flow(rest))
                    return
                }
                item = Item()
                if let (key, value) = Self.pair(rest) { note(key, value, own: true) }
                return
            }
            guard item != nil, let itemIndent else { return }
            if indent <= itemIndent {
                finish()
                return
            }
             
             
            let line = isDash ? body.dropFirst(1).trimmingCharacters(in: .whitespaces) : String(body)
            if line.hasPrefix("{") || line.hasPrefix("[") {
                for (key, value) in Self.fragments(line) where key == "username" { item?.usernames.insert(value) }
            } else if let (key, value) = Self.pair(line) {
                note(key, value, own: !isDash && indent == itemIndent + 2)
            }
        }

        private mutating func note(_ key: String, _ value: String, own: Bool) {
            if own, item?.fields[key] == nil { item?.fields[key] = value }
            if key == "username", !value.isEmpty { item?.usernames.insert(value) }
            if own, key == "users", value.hasPrefix("[") {
                for (key, value) in Self.fragments(value) where key == "username" { item?.usernames.insert(value) }
            }
        }

        mutating func finish() {
            if let item { judge(item) }
            item = nil
        }

        private mutating func judge(_ item: Item) {
            guard !found else { return }
            let fields = item.fields
            guard let port = fields["port"].flatMap({ UInt16($0) }) else { return }
            switch section {
            case "proxies":
                guard let name = fields["name"], ModuleRuntimeNames.engineGeneration(of: name) != nil, fields["type"] == "http",
                      fields["server"] == "127.0.0.1", let username = fields["username"], fields["password"] != nil else { return }
                found = known.isEmpty || known.enginePorts.contains(port) || known.engineUsernames.contains(username)
            case "listeners":
                guard let name = fields["name"], Self.isReinjectListenerName(name), fields["type"] == "mixed",
                      fields["listen"] == "127.0.0.1", !item.usernames.isEmpty else { return }
                found = known.isEmpty || known.reinjectPorts.contains(port) || !known.reinjectUsernames.isDisjoint(with: item.usernames)
            default:
                return
            }
        }

         
         
         
        static func isReinjectListenerName(_ name: String) -> Bool {
            ModuleRuntimeNames.reinjectGeneration(of: name) != nil
        }

         
         
        static func flow(_ text: String) -> Item {
            var out = Item()
            var depth = 0
            var part = ""
            func close() {
                if let (key, value) = pair(part), out.fields[key] == nil { out.fields[key] = value }
                part = ""
            }
            for character in text.dropFirst() {
                switch character {
                case "{", "[": depth += 1; part.append(character)
                case "}", "]":
                    if depth == 0 { close() } else { depth -= 1; part.append(character) }
                case "," where depth == 0: close()
                default: part.append(character)
                }
            }
            close()
            for (key, value) in fragments(text) where key == "username" { out.usernames.insert(value) }
            return out
        }

         
        static func fragments(_ text: some StringProtocol) -> [(String, String)] {
            text.split(whereSeparator: { ",{}[]".contains($0) }).compactMap { pair($0) }
        }

         
        static func pair(_ text: some StringProtocol) -> (String, String)? {
            guard let colon = text.firstIndex(of: ":") else { return nil }
            let key = unquoted(text[..<colon].trimmingCharacters(in: .whitespaces))
            let value = unquoted(text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces))
            return key.isEmpty ? nil : (key, value)
        }

        static func unquoted(_ text: String) -> String {
            guard text.count >= 2, let first = text.first, first == "\"" || first == "'", text.last == first else { return text }
            return String(text.dropFirst().dropLast())
        }
    }
}
#endif
