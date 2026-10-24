import Foundation

 
 
 
 
 
 
 
 
 
 
 
extension ModuleHostList {
    static let mitmStandardPort: UInt16 = 443
    static let forceHTTPStandardPort: UInt16 = 80

     
    init(_ spellings: [String], standardPort: UInt16 = ModuleHostList.mitmStandardPort, moduleID: String = "") {
        self.init(items: spellings.compactMap { ModuleHostList.entry($0) }.map { Item(entry: $0, moduleID: moduleID) },
                  standardPort: standardPort)
    }

    private static let nameCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_*?")

     
     
     
    static func isHostName(_ name: String) -> Bool {
        !name.isEmpty && (name.unicodeScalars.allSatisfy { nameCharacters.contains($0) } || ModuleIPLiteral(name) != nil)
    }

     
     
     
     
     
     
     
     
    static func entry(_ spelling: String) -> ModuleHostEntry? {
        var text = spelling.trimmingCharacters(in: .whitespaces)
        var excluded = false
        if text.hasPrefix("-") {
            excluded = true
            text.removeFirst()
        }
        func port(_ digits: Substring) -> ModuleHostPort? {
            guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = UInt32(digits), value <= 65_535 else { return nil }
            return value == 0 ? .all : .port(UInt16(value))
        }
        if text.hasPrefix("["), let close = text.firstIndex(of: "]") {
            let address = String(text[text.index(after: text.startIndex)..<close])
            let rest = text[text.index(after: close)...]
            guard ModuleIPLiteral(address)?.isIPv6 == true else { return nil }
            var written = ModuleHostPort.standard
            if !rest.isEmpty {
                guard rest.hasPrefix(":"), let given = port(rest.dropFirst()) else { return nil }
                written = given
            }
            return ModuleHostEntry(excluded: excluded, pattern: .name(address.lowercased()), port: written)
        }
        if text.filter({ $0 == ":" }).count > 1 {
            guard ModuleIPLiteral(text)?.isIPv6 == true else { return nil }
            return ModuleHostEntry(excluded: excluded, pattern: .name(text.lowercased()), port: .standard)
        }
        var written = ModuleHostPort.standard
        if let colon = text.lastIndex(of: ":") {
             
            let digits = text[text.index(after: colon)...]
            guard let given = digits == "*" ? .all : port(digits) else { return nil }
            written = given
            text = String(text[..<colon])
        }
        let lowered = text.lowercased()
        let pattern: ModuleHostPattern
        switch lowered {
        case "<ip-address>": pattern = .ipAddress
        case "<ipv4-address>": pattern = .ipv4Address
        case "<ipv6-address>": pattern = .ipv6Address
        case "<simple-hostname>": pattern = .simpleHostname
        default:
            guard !lowered.isEmpty, lowered.unicodeScalars.allSatisfy({ nameCharacters.contains($0) }) else { return nil }
            var collapsed = lowered
            while collapsed.contains("**") { collapsed = collapsed.replacingOccurrences(of: "**", with: "*") }
            if collapsed.hasSuffix("."), collapsed.dropLast().contains(where: { $0.isLetter || $0.isNumber }) {
                collapsed.removeLast()
                 
                 
                 
                guard !collapsed.hasSuffix(".") else { return nil }
            }
            pattern = .name(collapsed)
        }
        return ModuleHostEntry(excluded: excluded, pattern: pattern, port: written)
    }

     
     
    static func line(_ value: String, origin: ModuleLineOrigin) -> (line: ModuleHostListLine, ignored: [ModuleIgnoredEntry]) {
        var text = value.trimmingCharacters(in: .whitespaces)
        var directive = ModuleHostListDirective.replace
        if text.uppercased().hasPrefix("%APPEND%") {
            directive = .append
            text = String(text.dropFirst(8))
        } else if text.uppercased().hasPrefix("%INSERT%") {
            directive = .insert
            text = String(text.dropFirst(8))
        }
        var entries: [ModuleHostEntry] = []
        var ignored: [ModuleIgnoredEntry] = []
        for item in text.split(separator: ",") {
            let spelling = item.trimmingCharacters(in: .whitespaces)
            guard !spelling.isEmpty else { continue }
            if let entry = entry(spelling) {
                entries.append(entry)
            } else {
                ignored.append(ModuleIgnoredEntry(text: spelling, reason: .invalidHost(spelling), origin: origin))
            }
        }
        return (ModuleHostListLine(directive: directive, entries: entries, origin: origin), ignored)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func merged(_ modules: [(moduleID: String, lines: [ModuleHostListLine])], standardPort: UInt16,
                       preferring: Set<String> = []) -> ModuleHostList {
        var items: [Item] = []
        var leading: [Item] = []
        var settings: [Item] = []
        for module in modules {
            for line in module.lines {
                let added = line.entries.map { Item(entry: $0, moduleID: module.moduleID) }
                switch line.directive {
                case .insert:
                    items.insert(contentsOf: added, at: 0)
                case .append:
                    items.append(contentsOf: added)
                case .replace:
                    items = added
                    leading = []
                case .merge:
                    leading += added.filter(\.entry.excluded)
                    items.append(contentsOf: added.filter { !$0.entry.excluded })
                case .setting:
                    settings += added
                }
            }
        }
        let all = settings + leading + items
        var preferred: [ModuleHostEntry: String] = [:]
        if !preferring.isEmpty {
            for item in all where preferring.contains(item.moduleID) && preferred[item.entry] == nil { preferred[item.entry] = item.moduleID }
        }
        var seen = Set<ModuleHostEntry>()
        let kept = all.filter { seen.insert($0.entry).inserted }.map { item -> Item in
            guard let moduleID = preferred[item.entry] else { return item }
            return Item(entry: item.entry, moduleID: moduleID)
        }
        return ModuleHostList(items: kept, standardPort: standardPort)
    }

     
     
     
    struct Connection: Equatable, Sendable {
        var host: String?
        var addressIsIPv6: Bool = false
         
        var address: String? = nil
        var port: UInt16
    }

     
     
     
     
     
     
     
     
    func decision(for connection: Connection) -> ModuleHostEntry? {
        index.firstMatch(connection, standardPort: standardPort).map { items[$0].entry }
    }

     
    func includes(_ connection: Connection) -> Bool {
        decision(for: connection).map { !$0.excluded } ?? false
    }

     
    var spellings: [String] { items.map(\.entry.spelling) }
}

extension ModuleHostEntry {
    func matches(_ connection: ModuleHostList.Connection, standardPort: UInt16) -> Bool {
        matches(connection, loweredHost: connection.host.flatMap { $0.isEmpty ? nil : $0.lowercased() }, standardPort: standardPort)
    }

     
    func matches(_ connection: ModuleHostList.Connection, loweredHost host: String?, standardPort: UInt16) -> Bool {
        switch port {
        case .standard: guard connection.port == standardPort else { return false }
        case .port(let value): guard connection.port == value else { return false }
        case .all: break
        }
        switch pattern {
        case .name(let name):
             
             
             
             
             
             
             
             
             
            if ModuleIPLiteral.mightBe(name), let literal = ModuleIPLiteral(name) {
                return host == nil && connection.address.flatMap(ModuleIPLiteral.init)?.canonical == literal.canonical
            }
            return host.map { ModuleWildcard.matches(name, $0) } ?? false
        case .ipAddress: return host == nil
        case .ipv4Address: return host == nil && !connection.addressIsIPv6
        case .ipv6Address: return host == nil && connection.addressIsIPv6
        case .simpleHostname: return host.map { !$0.contains(".") } ?? false
        }
    }

    var spelling: String {
        var text: String
        switch pattern {
        case .name(let name): text = name
        case .ipAddress: text = "<ip-address>"
        case .ipv4Address: text = "<ipv4-address>"
        case .ipv6Address: text = "<ipv6-address>"
        case .simpleHostname: text = "<simple-hostname>"
        }
         
        let bracketed = text.contains(":") ? "[" + text + "]" : text
        switch port {
        case .standard: break
        case .port(let value): text = bracketed + ":\(value)"
        case .all: text = bracketed + ":0"
        }
        return (excluded ? "-" : "") + text
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
final class ModuleHostListIndex: Sendable {
    enum Kind: UInt8, Sendable {
        case exact
        case wildcard
         
        case address
        case ipAddress
        case ipv4Address
        case ipv6Address
        case simpleHostname
    }

     
    struct Entry: Sendable {
         
         
        let start: UInt32
         
        let count: UInt32
        let port: ModuleHostPort
        let kind: Kind
    }

    let bytes: [UInt8]
     
    let addresses: [String]
    let entries: [Entry]

    init(_ items: [ModuleHostList.Item]) {
        var capacity = 0
        for item in items {
            if case .name(let name) = item.entry.pattern { capacity += name.utf8.count }
        }
        var bytes: [UInt8] = []
        bytes.reserveCapacity(capacity)
        var addresses: [String] = []
        var entries: [Entry] = []
        entries.reserveCapacity(items.count)
        for item in items {
            let kind: ModuleHostListIndex.Kind
            var start = bytes.count, count = 0
            switch item.entry.pattern {
            case .name(let name):
                if ModuleIPLiteral.mightBe(name), let literal = ModuleIPLiteral(name) {
                    kind = .address
                    start = addresses.count
                    addresses.append(literal.canonical)
                } else {
                    bytes.append(contentsOf: name.utf8)
                    count = bytes.count - start
                    kind = name.contains("*") || name.contains("?") ? .wildcard : .exact
                }
            case .ipAddress: kind = .ipAddress
            case .ipv4Address: kind = .ipv4Address
            case .ipv6Address: kind = .ipv6Address
            case .simpleHostname: kind = .simpleHostname
            }
            entries.append(Entry(start: UInt32(start), count: UInt32(count), port: item.entry.port, kind: kind))
        }
        self.bytes = bytes
        self.addresses = addresses
        self.entries = entries
    }

     
     
    func firstMatch(_ connection: ModuleHostList.Connection, standardPort: UInt16) -> Int? {
        var host = connection.host.flatMap { $0.isEmpty ? nil : $0.lowercased() }
         
         
        var address: String??
        func canonicalAddress() -> String? {
            if let address { return address }
            let read = connection.address.flatMap(ModuleIPLiteral.init)?.canonical
            address = .some(read)
            return read
        }
        return bytes.withUnsafeBufferPointer { names -> Int? in
            func search(_ name: UnsafeBufferPointer<UInt8>?) -> Int? {
                for (position, entry) in entries.enumerated() {
                    switch entry.port {
                    case .standard: if connection.port != standardPort { continue }
                    case .port(let value): if connection.port != value { continue }
                    case .all: break
                    }
                    let matched: Bool
                    switch entry.kind {
                    case .exact:
                        let count = Int(entry.count)
                        guard let name, name.count == count, let base = names.baseAddress else { continue }
                        matched = count == 0 || memcmp(base + Int(entry.start), name.baseAddress!, count) == 0
                    case .wildcard:
                        guard let name else { continue }
                        let start = Int(entry.start)
                        matched = ModuleWildcard.matches(UnsafeBufferPointer(rebasing: names[start..<(start + Int(entry.count))]), name)
                    case .address:
                        matched = name == nil && canonicalAddress() == addresses[Int(entry.start)]
                    case .ipAddress: matched = name == nil
                    case .ipv4Address: matched = name == nil && !connection.addressIsIPv6
                    case .ipv6Address: matched = name == nil && connection.addressIsIPv6
                    case .simpleHostname: matched = name.map { !$0.contains(UInt8(ascii: ".")) } ?? false
                    }
                    if matched { return position }
                }
                return nil
            }
            guard host != nil else { return search(nil) }
            return host!.withUTF8 { search($0) }
        }
    }
}

 
 
 
 
 
enum ModuleWildcard {
    static func matches(_ pattern: String, _ text: String) -> Bool {
         
        var pattern = pattern
        var text = text
        return pattern.withUTF8 { p in text.withUTF8 { s in matches(p, s) } }
    }

    static func matches(_ p: UnsafeBufferPointer<UInt8>, _ s: UnsafeBufferPointer<UInt8>) -> Bool {
        guard !s.isEmpty else { return false }
         
        if !p.contains(UInt8(ascii: "*")), !p.contains(UInt8(ascii: "?")) {
            return p.count == s.count && memcmp(p.baseAddress!, s.baseAddress!, p.count) == 0
        }
        var pi = 0, si = 0, star = -1, mark = 0
        while si < s.count {
            if pi < p.count, p[pi] == UInt8(ascii: "*") {
                star = pi
                mark = si
                pi += 1
            } else if pi < p.count, p[pi] == UInt8(ascii: "?") || p[pi] == s[si] {
                pi += 1
                si += 1
            } else if star != -1 {
                pi = star + 1
                mark += 1
                si = mark
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == UInt8(ascii: "*") { pi += 1 }
        return pi == p.count
    }
}

 
struct ModuleIPLiteral {
    let isIPv6: Bool
     
    let canonical: String

     
     
    static func mightBe(_ text: String) -> Bool {
        var text = text
        return text.withUTF8 { bytes in
            bytes.contains(UInt8(ascii: ":")) || (!bytes.isEmpty && bytes.allSatisfy { $0 == UInt8(ascii: ".") || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains($0) })
        }
    }

     
     
     
     
     
    init?(_ text: String) {
        guard !text.isEmpty, text.utf8.count <= 45, text.utf8.allSatisfy({ byte in
            (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) || (UInt8(ascii: "a")...UInt8(ascii: "f")).contains(byte)
                || (UInt8(ascii: "A")...UInt8(ascii: "F")).contains(byte) || byte == UInt8(ascii: ":") || byte == UInt8(ascii: ".")
        }) else { return nil }
        var v4 = in_addr()
        var v6 = in6_addr()
        var buffer = [CChar](repeating: 0, count: 64)
        if inet_pton(AF_INET, text, &v4) == 1 {
            isIPv6 = false
            inet_ntop(AF_INET, &v4, &buffer, 64)
        } else if inet_pton(AF_INET6, text, &v6) == 1 {
            isIPv6 = true
            inet_ntop(AF_INET6, &v6, &buffer, 64)
        } else {
            return nil
        }
        canonical = String(cString: buffer)
        if !isIPv6, canonical != text { return nil }
    }
}
