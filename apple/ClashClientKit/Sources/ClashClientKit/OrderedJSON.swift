import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
public indirect enum OrderedJSON: Equatable, Sendable {
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
     
    case scalar(String)

    public static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        switch (lhs, rhs) {
        case let (.object(l), .object(r)):
            return l.count == r.count
                && zip(l, r).allSatisfy { $0.key == $1.key && $0.value == $1.value }
        case let (.array(l), .array(r)):
            return l == r
        case let (.string(l), .string(r)):
            return l == r
        case let (.scalar(l), .scalar(r)):
            return l == r
        default:
            return false
        }
    }
}

public extension OrderedJSON {
    enum ParseError: Error, Equatable {
        case unexpectedEnd
        case unexpectedCharacter(Character, at: Int)
        case invalidNumber(at: Int)
        case invalidEscape(at: Int)
        case trailingContent(at: Int)
    }



     
     
     
     
     
     
     
    static func parse(_ text: String) throws -> OrderedJSON {


        var text = text
        return try text.withUTF8 { bytes in
            var parser = Parser(bytes)
            let value = try parser.parseValue()
            parser.skipWhitespace()
            guard parser.isAtEnd else { throw ParseError.trailingContent(at: parser.scalarOffset(parser.index)) }
            return value
        }
    }

     
    func serialized() -> String {


        var out = JSONByteSink()
        defer { out.release() }
        write(into: &out)
        let text = out.string()


        return text
    }

    fileprivate func write(into out: inout JSONByteSink) {
        switch self {
        case let .object(pairs):
            out.append(UInt8(ascii: "{"))
            var first = true
            for pair in pairs {
                if !first { out.append(UInt8(ascii: ",")) }
                first = false
                OrderedJSON.writeString(pair.key, into: &out)
                out.append(UInt8(ascii: ":"))
                pair.value.write(into: &out)
            }
            out.append(UInt8(ascii: "}"))
        case let .array(items):
            out.append(UInt8(ascii: "["))
            var first = true
            for item in items {
                if !first { out.append(UInt8(ascii: ",")) }
                first = false
                item.write(into: &out)
            }
            out.append(UInt8(ascii: "]"))
        case let .string(value):
            OrderedJSON.writeString(value, into: &out)
        case let .scalar(token):
            var token = token
            token.withUTF8 { out.append(contentsOf: $0) }
        }
    }

    private static let lowercaseHexDigits: [UInt8] = Array("0123456789abcdef".utf8)

     
     
     
     
    fileprivate static func writeString(_ value: String, into out: inout JSONByteSink) {
        out.append(UInt8(ascii: "\""))
        var value = value
        value.withUTF8 { bytes in
             
            var run = 0
            var position = 0
            while position < bytes.count {
                let byte = bytes[position]
                if byte >= 0x20, byte != 0x22, byte != 0x5C {
                    position += 1
                    continue
                }
                if run < position { out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[run..<position])) }
                switch byte {
                case 0x22: out.append(0x5C); out.append(0x22)
                case 0x5C: out.append(0x5C); out.append(0x5C)
                case 0x08: out.append(0x5C); out.append(UInt8(ascii: "b"))
                case 0x0C: out.append(0x5C); out.append(UInt8(ascii: "f"))
                case 0x0A: out.append(0x5C); out.append(UInt8(ascii: "n"))
                case 0x0D: out.append(0x5C); out.append(UInt8(ascii: "r"))
                case 0x09: out.append(0x5C); out.append(UInt8(ascii: "t"))
                default:
                    out.append(0x5C); out.append(UInt8(ascii: "u")); out.append(0x30); out.append(0x30)
                    out.append(lowercaseHexDigits[Int(byte >> 4)]); out.append(lowercaseHexDigits[Int(byte & 0x0F)])
                }
                position += 1
                run = position
            }
            if run < bytes.count { out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[run..<bytes.count])) }
        }
        out.append(UInt8(ascii: "\""))
    }

     
     
     
     
     
     
     
    struct TopLevel: Sendable {
        fileprivate struct Member: Sendable {
            let key: String
            let count: Int
            let range: Range<Int>
        }

        private let text: String
        private let members: [Member]

        fileprivate init(text: String, members: [Member]) {
            self.text = text
            self.members = members
        }

         
        public var keys: [String] { members.map(\.key) }

         
         
         
        public func count(_ key: String) -> Int {
            members.first { $0.key == key }?.count ?? 0
        }

         
         
        public func value(_ key: String) throws -> OrderedJSON? {
            guard let member = members.first(where: { $0.key == key }) else { return nil }
            var text = text
            return try text.withUTF8 { bytes in
                var parser = Parser(UnsafeBufferPointer(rebasing: bytes[member.range]))
                return try parser.parseValue()
            }
        }
    }

     
     
    static func topLevel(_ text: String) throws -> TopLevel? {
        var bytesText = text
        let members: [TopLevel.Member]? = try bytesText.withUTF8 { bytes in
            var parser = Parser(bytes)
            let members = try parser.skipTopLevel()
            parser.skipWhitespace()
            guard parser.isAtEnd else { throw ParseError.trailingContent(at: parser.scalarOffset(parser.index)) }
            return members
        }
        return members.map { TopLevel(text: text, members: $0) }
    }

     

    private struct Parser {
        private let bytes: UnsafeBufferPointer<UInt8>
        private(set) var index = 0

        init(_ bytes: UnsafeBufferPointer<UInt8>) { self.bytes = bytes }

        var isAtEnd: Bool { index >= bytes.count }

         
         
        func scalarOffset(_ offset: Int) -> Int {
            var count = 0
            var position = 0
            let end = Swift.min(offset, bytes.count)
            while position < end {
                if bytes[position] & 0xC0 != 0x80 { count += 1 }
                position += 1
            }
            return count
        }

         
        private func scalar(at offset: Int) -> Unicode.Scalar {
            let lead = bytes[offset]
            if lead < 0x80 { return Unicode.Scalar(lead) }
            var iterator = UnsafeBufferPointer(rebasing: bytes[offset...]).makeIterator()
            var codec = UTF8()
            if case .scalarValue(let scalar) = codec.decode(&iterator) { return scalar }
            return "\u{FFFD}"
        }

        private func unexpected(at offset: Int) -> ParseError {
            .unexpectedCharacter(Character(scalar(at: offset)), at: scalarOffset(offset))
        }

        mutating func skipWhitespace() {
            while index < bytes.count {
                switch bytes[index] {
                case 0x20, 0x09, 0x0A, 0x0D: index += 1
                default: return
                }
            }
        }

        private func peek() -> UInt8? {
            index < bytes.count ? bytes[index] : nil
        }

        mutating func parseValue() throws -> OrderedJSON {
            skipWhitespace()
            guard let c = peek() else { throw ParseError.unexpectedEnd }
            switch c {
            case UInt8(ascii: "{"): return try parseObject()
            case UInt8(ascii: "["): return try parseArray()
            case UInt8(ascii: "\""): return .string(try parseStringLiteral())
            case UInt8(ascii: "t"), UInt8(ascii: "f"), UInt8(ascii: "n"): return .scalar(try parseKeyword())
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"): return .scalar(try parseNumber())
            default: throw unexpected(at: index)
            }
        }

        private mutating func expect(_ byte: UInt8) throws {
            skipWhitespace()
            guard peek() == byte else {
                if peek() != nil { throw unexpected(at: index) }
                throw ParseError.unexpectedEnd
            }
            index += 1
        }

        private mutating func parseObject() throws -> OrderedJSON {
            index += 1  
            var pairs: [(key: String, value: OrderedJSON)] = []
            skipWhitespace()
            if peek() == UInt8(ascii: "}") { index += 1; return .object(pairs) }
            while true {
                skipWhitespace()
                guard peek() == UInt8(ascii: "\"") else {
                    if peek() != nil { throw unexpected(at: index) }
                    throw ParseError.unexpectedEnd
                }
                let key = try parseStringLiteral()
                try expect(UInt8(ascii: ":"))
                let value = try parseValue()
                pairs.append((key: key, value: value))
                skipWhitespace()
                switch peek() {
                case UInt8(ascii: ","): index += 1
                case UInt8(ascii: "}"): index += 1; return .object(pairs)
                case .some: throw unexpected(at: index)
                case nil: throw ParseError.unexpectedEnd
                }
            }
        }

        private mutating func parseArray() throws -> OrderedJSON {
            index += 1  
            var items: [OrderedJSON] = []
            skipWhitespace()
            if peek() == UInt8(ascii: "]") { index += 1; return .array(items) }
            while true {
                items.append(try parseValue())
                skipWhitespace()
                switch peek() {
                case UInt8(ascii: ","): index += 1
                case UInt8(ascii: "]"): index += 1; return .array(items)
                case .some: throw unexpected(at: index)
                case nil: throw ParseError.unexpectedEnd
                }
            }
        }

         

         
         
        mutating func skipTopLevel() throws -> [TopLevel.Member]? {
            skipWhitespace()
            guard let c = peek() else { throw ParseError.unexpectedEnd }
            guard c == UInt8(ascii: "{") else {
                _ = try skipValue()
                return nil
            }
            index += 1  
            var members: [TopLevel.Member] = []
            skipWhitespace()
            if peek() == UInt8(ascii: "}") { index += 1; return members }
            while true {
                skipWhitespace()
                guard peek() == UInt8(ascii: "\"") else {
                    if peek() != nil { throw unexpected(at: index) }
                    throw ParseError.unexpectedEnd
                }
                let key = try parseStringLiteral()
                try expect(UInt8(ascii: ":"))
                skipWhitespace()
                let start = index
                let count = try skipValue()
                members.append(.init(key: key, count: count, range: start..<index))
                skipWhitespace()
                switch peek() {
                case UInt8(ascii: ","): index += 1
                case UInt8(ascii: "}"): index += 1; return members
                case .some: throw unexpected(at: index)
                case nil: throw ParseError.unexpectedEnd
                }
            }
        }

         
         
        @discardableResult
        mutating func skipValue() throws -> Int {
            skipWhitespace()
            guard let c = peek() else { throw ParseError.unexpectedEnd }
            switch c {
            case UInt8(ascii: "{"):
                index += 1
                var count = 0
                skipWhitespace()
                if peek() == UInt8(ascii: "}") { index += 1; return 0 }
                while true {
                    skipWhitespace()
                    guard peek() == UInt8(ascii: "\"") else {
                        if peek() != nil { throw unexpected(at: index) }
                        throw ParseError.unexpectedEnd
                    }
                    try skipStringLiteral()
                    try expect(UInt8(ascii: ":"))
                    try skipValue()
                    count += 1
                    skipWhitespace()
                    switch peek() {
                    case UInt8(ascii: ","): index += 1
                    case UInt8(ascii: "}"): index += 1; return count
                    case .some: throw unexpected(at: index)
                    case nil: throw ParseError.unexpectedEnd
                    }
                }
            case UInt8(ascii: "["):
                index += 1
                var count = 0
                skipWhitespace()
                if peek() == UInt8(ascii: "]") { index += 1; return 0 }
                while true {
                    try skipValue()
                    count += 1
                    skipWhitespace()
                    switch peek() {
                    case UInt8(ascii: ","): index += 1
                    case UInt8(ascii: "]"): index += 1; return count
                    case .some: throw unexpected(at: index)
                    case nil: throw ParseError.unexpectedEnd
                    }
                }
            case UInt8(ascii: "\""):
                try skipStringLiteral()
                return 0
            case UInt8(ascii: "t"), UInt8(ascii: "f"), UInt8(ascii: "n"):
                _ = try parseKeyword()
                return 0
            case UInt8(ascii: "-"), UInt8(ascii: "0")...UInt8(ascii: "9"):
                try skipNumber()
                return 0
            default:
                throw unexpected(at: index)
            }
        }

         
        private mutating func skipNumber() throws {
            let start = index
            if peek() == UInt8(ascii: "-") { index += 1 }
            while isDigit(peek()) { index += 1 }
            if peek() == UInt8(ascii: ".") {
                index += 1
                while isDigit(peek()) { index += 1 }
            }
            if peek() == UInt8(ascii: "e") || peek() == UInt8(ascii: "E") {
                index += 1
                if peek() == UInt8(ascii: "+") || peek() == UInt8(ascii: "-") { index += 1 }
                while isDigit(peek()) { index += 1 }
            }
            guard index > start else { throw ParseError.invalidNumber(at: scalarOffset(start)) }
        }

         
         
        private mutating func skipStringLiteral() throws {
            index += 1  
            while index < bytes.count {
                let c = bytes[index]
                index += 1
                switch c {
                case UInt8(ascii: "\""):
                    return
                case UInt8(ascii: "\\"):
                    guard let escape = peek() else { throw ParseError.unexpectedEnd }
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"), UInt8(ascii: "b"),
                         UInt8(ascii: "f"), UInt8(ascii: "n"), UInt8(ascii: "r"), UInt8(ascii: "t"):
                        break
                    case UInt8(ascii: "u"):
                        _ = try parseUnicodeEscape()
                    default: throw ParseError.invalidEscape(at: scalarOffset(index - 1))
                    }
                default:
                    break
                }
            }
            throw ParseError.unexpectedEnd
        }

        private static let keywords: [(word: String, letters: [UInt8])] =
            ["true", "false", "null"].map { ($0, Array($0.utf8)) }

         
         
        private mutating func parseKeyword() throws -> String {
            for keyword in Self.keywords where index + keyword.letters.count <= bytes.count {
                var matches = true
                for (offset, letter) in keyword.letters.enumerated() where bytes[index + offset] != letter {
                    matches = false
                    break
                }
                if matches {
                    index += keyword.letters.count
                    return keyword.word
                }
            }
            throw unexpected(at: index)
        }

        private func isDigit(_ byte: UInt8?) -> Bool {
            guard let byte else { return false }
            return byte >= UInt8(ascii: "0") && byte <= UInt8(ascii: "9")
        }

         
         
        private mutating func parseNumber() throws -> String {
            let start = index
            if peek() == UInt8(ascii: "-") { index += 1 }
            while isDigit(peek()) { index += 1 }
            if peek() == UInt8(ascii: ".") {
                index += 1
                while isDigit(peek()) { index += 1 }
            }
            if peek() == UInt8(ascii: "e") || peek() == UInt8(ascii: "E") {
                index += 1
                if peek() == UInt8(ascii: "+") || peek() == UInt8(ascii: "-") { index += 1 }
                while isDigit(peek()) { index += 1 }
            }
            guard index > start else { throw ParseError.invalidNumber(at: scalarOffset(start)) }
            return String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)
        }

        private mutating func parseStringLiteral() throws -> String {
            index += 1  
            let start = index
             
            while index < bytes.count {
                switch bytes[index] {
                case UInt8(ascii: "\""):
                    let value = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<index]), as: UTF8.self)
                    index += 1
                    return value
                case UInt8(ascii: "\\"):
                    return try parseEscapedString(from: start)
                default:
                    index += 1
                }
            }
            throw ParseError.unexpectedEnd
        }

         
         
        private mutating func parseEscapedString(from start: Int) throws -> String {
            var value: [UInt8] = []
            value.reserveCapacity(index - start + 16)
            value.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[start..<index]))
            while index < bytes.count {
                let c = bytes[index]
                index += 1
                switch c {
                case UInt8(ascii: "\""):
                    return String(decoding: value, as: UTF8.self)
                case UInt8(ascii: "\\"):
                    guard let escape = peek() else { throw ParseError.unexpectedEnd }
                    index += 1
                    switch escape {
                    case UInt8(ascii: "\""): value.append(0x22)
                    case UInt8(ascii: "\\"): value.append(0x5C)
                    case UInt8(ascii: "/"): value.append(0x2F)
                    case UInt8(ascii: "b"): value.append(0x08)
                    case UInt8(ascii: "f"): value.append(0x0C)
                    case UInt8(ascii: "n"): value.append(0x0A)
                    case UInt8(ascii: "r"): value.append(0x0D)
                    case UInt8(ascii: "t"): value.append(0x09)
                    case UInt8(ascii: "u"):
                        let scalar = try parseUnicodeEscape()
                        UTF8.encode(scalar) { value.append($0) }
                    default: throw ParseError.invalidEscape(at: scalarOffset(index - 1))
                    }
                default:
                    value.append(c)
                }
            }
            throw ParseError.unexpectedEnd
        }

        private static func hexValue(_ byte: UInt8) -> UInt32? {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): return UInt32(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): return UInt32(byte - UInt8(ascii: "a") + 10)
            case UInt8(ascii: "A")...UInt8(ascii: "F"): return UInt32(byte - UInt8(ascii: "A") + 10)
            default: return nil
            }
        }

        private mutating func parseUnicodeEscape() throws -> Unicode.Scalar {
            func readHex4() throws -> UInt32 {
                 
                 
                var probe = index
                var remaining = 0
                while remaining < 4, probe < bytes.count {
                    probe += 1
                    while probe < bytes.count, bytes[probe] & 0xC0 == 0x80 { probe += 1 }
                    remaining += 1
                }
                guard remaining == 4 else { throw ParseError.unexpectedEnd }
                var code: UInt32 = 0
                for _ in 0..<4 {
                    guard let hex = Self.hexValue(bytes[index]) else {
                        throw ParseError.invalidEscape(at: scalarOffset(index))
                    }
                    code = code * 16 + hex
                    index += 1
                }
                return code
            }
            let first = try readHex4()
             
            if (0xD800...0xDBFF).contains(first) {
                guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else {
                    throw ParseError.invalidEscape(at: scalarOffset(index))
                }
                index += 2
                let second = try readHex4()
                guard (0xDC00...0xDFFF).contains(second) else { throw ParseError.invalidEscape(at: scalarOffset(index)) }
                let combined = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00)
                guard let scalar = Unicode.Scalar(combined) else { throw ParseError.invalidEscape(at: scalarOffset(index)) }
                return scalar
            }
            guard let scalar = Unicode.Scalar(first) else { throw ParseError.invalidEscape(at: scalarOffset(index)) }
            return scalar
        }
    }
}


 
 
 
 
struct JSONByteSink {
    private var storage: UnsafeMutablePointer<UInt8>
    private var capacity: Int
    private var count = 0

    init(capacity: Int = 4096) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
    }

    mutating func append(_ byte: UInt8) {
        if count == capacity { grow(toFit: count + 1) }
        storage[count] = byte
        count += 1
    }

    mutating func append(contentsOf bytes: UnsafeBufferPointer<UInt8>) {
        guard let base = bytes.baseAddress, bytes.count > 0 else { return }
        if count + bytes.count > capacity { grow(toFit: count + bytes.count) }
        (storage + count).update(from: base, count: bytes.count)
        count += bytes.count
    }

    private mutating func grow(toFit needed: Int) {
        var next = capacity * 2
        while next < needed { next *= 2 }
        let larger = UnsafeMutablePointer<UInt8>.allocate(capacity: next)
        larger.update(from: storage, count: count)
        storage.deallocate()
        storage = larger
        capacity = next
    }

    func string() -> String {
        String(decoding: UnsafeBufferPointer(start: storage, count: count), as: UTF8.self)
    }

    func release() {
        storage.deallocate()
    }
}

 

public extension OrderedJSON {
     
    func topLevelValue(_ key: String) -> OrderedJSON? {
        guard case let .object(pairs) = self else { return nil }
        return pairs.first { $0.key == key }?.value
    }

     
     
     
     
     
    func mergingAsTheCoreMerges(_ patch: OrderedJSON) -> OrderedJSON {
        guard case .object(let entries) = patch, case .object = self else { return patch }
        var result = self
        for entry in entries {
            let merged = result.topLevelValue(entry.key).map { $0.mergingAsTheCoreMerges(entry.value) } ?? entry.value
            result = result.settingTopLevel(entry.key, to: merged)
        }
        return result
    }

    func settingTopLevel(_ key: String, to value: OrderedJSON) -> OrderedJSON {
        guard case var .object(pairs) = self else { return self }
        if let existing = pairs.firstIndex(where: { $0.key == key }) {
            pairs[existing] = (key: key, value: value)
        } else {
            pairs.append((key: key, value: value))
        }
        return .object(pairs)
    }
}

 

public extension OrderedJSON {
     
     
     
     
     
    func canonicalSerialized(preservingOrderForKeys: Set<String>) -> String {
        var out = JSONByteSink()
        defer { out.release() }
        writeCanonical(sortKeys: true, preservingOrderForKeys: preservingOrderForKeys, into: &out)
        return out.string()
    }

    private func writeCanonical(
        sortKeys: Bool,
        preservingOrderForKeys keys: Set<String>,
        into out: inout JSONByteSink
    ) {
        switch self {
        case let .object(pairs):
            let ordered = sortKeys ? pairs.sorted { $0.key < $1.key } : pairs
            out.append(UInt8(ascii: "{"))
            for (offset, pair) in ordered.enumerated() {
                if offset > 0 { out.append(UInt8(ascii: ",")) }
                OrderedJSON.writeString(pair.key, into: &out)
                out.append(UInt8(ascii: ":"))
                 
                pair.value.writeCanonical(
                    sortKeys: keys.contains(pair.key) ? false : true,
                    preservingOrderForKeys: keys,
                    into: &out
                )
            }
            out.append(UInt8(ascii: "}"))
        case let .array(items):
            out.append(UInt8(ascii: "["))
            for (offset, item) in items.enumerated() {
                if offset > 0 { out.append(UInt8(ascii: ",")) }
                item.writeCanonical(sortKeys: sortKeys, preservingOrderForKeys: keys, into: &out)
            }
            out.append(UInt8(ascii: "]"))
        case .string, .scalar:
            write(into: &out)
        }
    }
}

 

public extension OrderedJSON {
     
     
     
     
    var foundationValue: Any {
        switch self {
        case let .object(pairs):
            var dict: [String: Any] = [:]
            for pair in pairs { dict[pair.key] = pair.value.foundationValue }
            return dict
        case let .array(items):
            return items.map { $0.foundationValue }
        case let .string(value):
            return value
        case let .scalar(token):
            switch token {
            case "true": return true
            case "false": return false
            case "null": return NSNull()
            default:
                if let int = Int(token) { return int }
                if let double = Double(token) { return double }
                return token
            }
        }
    }

     
     
     
    static func from(foundation value: Any) -> OrderedJSON {
        switch value {
        case let node as OrderedJSON:
            return node
        case let string as String:
            return .string(string)
        case is NSNull:
            return .scalar("null")
         
         
         
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID():
            return .scalar(number.boolValue ? "true" : "false")
        case let number as NSNumber:
            if let int = number as? Int, Double(int) == number.doubleValue {
                return .scalar(String(int))
            }
            return .scalar(String(describing: number))
        case let array as [Any]:
            return .array(array.map { OrderedJSON.from(foundation: $0) })
        case let dict as [String: Any]:
            return .object(dict.keys.sorted().map { (key: $0, value: OrderedJSON.from(foundation: dict[$0]!)) })
        default:
            return .string(String(describing: value))
        }
    }

     
    func node(at path: [String]) -> OrderedJSON? {
        var node: OrderedJSON? = self
        for key in path { node = node?.topLevelValue(key) }
        return node
    }

     
    func orderedObject(at path: [String]) -> [(key: String, value: OrderedJSON)]? {
        guard case let .object(pairs)? = node(at: path) else { return nil }
        return pairs
    }

     
     
     
    func setting(path: [String], to value: OrderedJSON?) -> OrderedJSON {
        guard let head = path.first else { return value ?? self }
        let base: OrderedJSON = { if case .object = self { return self } else { return .object([]) } }()
        let child = base.topLevelValue(head) ?? .object([])
        if path.count == 1 {
            guard let value else { return base.removingTopLevel(head) }
            return base.settingTopLevel(head, to: value)
        }
        let updatedChild = child.setting(path: Array(path.dropFirst()), to: value)
         
        if case let .object(pairs) = updatedChild, pairs.isEmpty {
            return base.removingTopLevel(head)
        }
        return base.settingTopLevel(head, to: updatedChild)
    }

    func removingTopLevel(_ key: String) -> OrderedJSON {
        guard case let .object(pairs) = self else { return self }
        return .object(pairs.filter { $0.key != key })
    }
}

public extension OrderedJSON {
     
     
     
     
     
     
     
     
     
    func reorderingMappings(following source: OrderedJSON) -> OrderedJSON {
        switch (self, source) {
        case let (.object(pairs), .object(sourcePairs)):
             
             
            var position: [String: Int] = [:]
            position.reserveCapacity(pairs.count)
            for (index, pair) in pairs.enumerated() where position[pair.key] == nil {
                position[pair.key] = index
            }
            var ordered: [(key: String, value: OrderedJSON)] = []
            ordered.reserveCapacity(pairs.count)
            var placed = Set<Int>()
            for sourcePair in sourcePairs {
                guard let index = position[sourcePair.key], !placed.contains(index) else { continue }
                placed.insert(index)
                ordered.append((
                    key: pairs[index].key,
                    value: pairs[index].value.reorderingMappings(following: sourcePair.value)
                ))
            }
            for (index, pair) in pairs.enumerated() where !placed.contains(index) {
                ordered.append(pair)
            }
            return .object(ordered)
        case let (.array(items), .array(sourceItems)):
            var paired = items
            for index in 0..<min(items.count, sourceItems.count) {
                paired[index] = items[index].reorderingMappings(following: sourceItems[index])
            }
            return .array(paired)
        default:
            return self
        }
    }
}
