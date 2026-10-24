#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 

enum ModuleJSONText {
     
     
    static let maximumDepth = 512

     
    static func parse(_ data: Data) -> ModuleJSONValue? {
        guard case .value(let value) = parse(data, maximumNodes: .max) else { return nil }
        return value
    }

    enum Reading {
        case value(ModuleJSONValue)
        case notJSON
         
        case tooManyNodes
    }

     
     
     
     
     
     
    static func parse(_ data: Data, maximumNodes: Int) -> Reading {
        data.withUnsafeBytes { raw in
            var reader = ModuleJSONReader(raw.bindMemory(to: UInt8.self), lenient: false, maximumNodes: maximumNodes)
            do {
                return .value(try reader.document())
            } catch is ModuleJSONReader.TooManyNodes {
                return .tooManyNodes
            } catch {
                return .notJSON
            }
        }
    }

     
     
    static func parseLeniently(_ text: String) throws -> ModuleJSONValue {
        var text = text
        return try text.withUTF8 { buffer in
            var reader = ModuleJSONReader(buffer, lenient: true)
            do {
                return try reader.document()
            } catch let failure as ModuleJSONReader.Failure {
                throw ModuleJSONReadError(message: "\(failure.message) (while parsing '\(String(decoding: buffer, as: UTF8.self))')")
            }
        }
    }

     
     
    static func serialize(_ value: ModuleJSONValue) -> Data {
        serialize(value, limit: .max)!
    }

     
    static func serialize(_ value: ModuleJSONValue, limit: Int) -> Data? {
        guard let length = length(value, limit: limit) else { return nil }
        var data = Data(count: length)
        data.withUnsafeMutableBytes { raw in
            var writer = ModuleJSONWriter(ModuleJSONBufferSink(raw.bindMemory(to: UInt8.self)))
            writer.write(value)
        }
        return data
    }

     
    static func length(_ value: ModuleJSONValue, limit: Int) -> Int? {
        var writer = ModuleJSONWriter(ModuleJSONCountingSink(limit: limit))
        return writer.write(value) ? writer.sink.total : nil
    }

    static func string(_ value: ModuleJSONValue) -> String {
        string(value, limit: .max)!
    }

     
     
    static func string(_ value: ModuleJSONValue, limit: Int) -> String? {
        guard let length = length(value, limit: limit) else { return nil }
        return written(value, length: length)
    }

     
    static func written(_ value: ModuleJSONValue, length: Int) -> String {
        if length == 0 { return "" }
        return String(unsafeUninitializedCapacity: length) { buffer in
            var writer = ModuleJSONWriter(ModuleJSONBufferSink(buffer))
            writer.write(value)
            return writer.sink.position
        }
    }

     
     
     
    static func truncated(_ value: ModuleJSONValue, bufferSize: Int) -> String {
        var writer = ModuleJSONWriter(ModuleJSONGrowingSink(limit: bufferSize))
        let whole = writer.write(value)
        var bytes = writer.sink.bytes
        if !whole || bytes.count > bufferSize - 1 {
            bytes = Array(bytes.prefix(max(0, bufferSize - 4))) + Array("...".utf8)
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

struct ModuleJSONReadError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

 

struct ModuleJSONReader {
    struct Failure: Error {
        let message: String
    }

     
    struct TooManyNodes: Error {}

    private let bytes: UnsafeBufferPointer<UInt8>
    private let lenient: Bool
    private var position = 0
     
     
     
    private let stackFloor = ModuleJQStack.floor(reserve: 32 << 10)
     
    private var shapes: [ModuleJSONKeyList: [String]] = [:]
    private static let maximumShapes = 512
    private let maximumNodes: Int
    private var nodes = 0

    init(_ bytes: UnsafeBufferPointer<UInt8>, lenient: Bool, maximumNodes: Int = .max) {
        self.bytes = bytes
        self.lenient = lenient
        self.maximumNodes = maximumNodes
    }

    @inline(__always)
    private mutating func count(_ more: Int) throws {
        nodes &+= more
        if nodes > maximumNodes { throw TooManyNodes() }
    }

    private func fail(_ message: String) -> Failure {
        if lenient {
            var line = 1, column = 0
            for index in 0..<min(position, bytes.count) {
                if bytes[index] == 0x0A { line += 1; column = 0 } else { column += 1 }
            }
            let place = position >= bytes.count ? "at EOF " : ""
            return Failure(message: "\(message) \(place)at line \(line), column \(column)")
        }
        return Failure(message: message)
    }

    mutating func document() throws -> ModuleJSONValue {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { position = 3 }
        skipWhitespace()
        guard position < bytes.count else { throw Failure(message: "Expected JSON value") }
        let value = try read(depth: 1)
        skipWhitespace()
        guard position == bytes.count else { throw Failure(message: "Unexpected extra JSON values") }
        return value
    }

    @inline(__always)
    private mutating func skipWhitespace() {
        while position < bytes.count {
            switch bytes[position] {
            case 0x20, 0x09, 0x0A, 0x0D: position += 1
            default: return
            }
        }
    }

    private mutating func read(depth: Int) throws -> ModuleJSONValue {
        guard depth <= ModuleJSONText.maximumDepth, ModuleJQStack.address() >= stackFloor else {
            throw fail("Exceeds depth limit for parsing")
        }
        guard position < bytes.count else { throw fail("Unfinished JSON term") }
        try count(1)
        switch bytes[position] {
        case UInt8(ascii: "{"):
            return try readObject(depth: depth)
        case UInt8(ascii: "["):
            return try readArray(depth: depth)
        case UInt8(ascii: "\""):
            return .string(try readString())
        default:
            return lenient ? try readLenientLiteral() : try readStrictLiteral()
        }
    }

     
     
     
    private var pending: [ModuleJSONValue] = []

    private mutating func takePending(from start: Int) -> [ModuleJSONValue] {
        let count = pending.count - start
        let exact = [ModuleJSONValue](unsafeUninitializedCapacity: count) { buffer, initialized in
            pending.withUnsafeBufferPointer { source in
                _ = buffer.initialize(from: source[start...])
            }
            initialized = count
        }
        pending.removeSubrange(start...)
        return exact
    }

    private mutating func readArray(depth: Int) throws -> ModuleJSONValue {
        position += 1
        let start = pending.count
        var deepest = 0
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "]") {
            position += 1
            return .emptyArray
        }
        try count(2)
        while true {
            skipWhitespace()
            guard position < bytes.count else { throw fail("Unfinished JSON term") }
            if bytes[position] == UInt8(ascii: "]") { throw fail("Expected another array element") }
            let item = try read(depth: depth + 1)
            deepest = max(deepest, item.depth)
            pending.append(item)
            skipWhitespace()
            guard position < bytes.count else { throw fail("Unfinished JSON term") }
            let byte = bytes[position]
            position += 1
            if byte == UInt8(ascii: ",") { continue }
            if byte == UInt8(ascii: "]") { break }
            throw fail("Expected separator between values")
        }
        return .array(ModuleJSONArray(takePending(from: start), childDepth: deepest))
    }

    private mutating func readObject(depth: Int) throws -> ModuleJSONValue {
        position += 1
        var keys: [String] = []
        let start = pending.count
        var seen: Set<ModuleJSONKey>?
        var deepest = 0
        skipWhitespace()
        if position < bytes.count, bytes[position] == UInt8(ascii: "}") {
            position += 1
            return .emptyObject
        }
        try count(2)
        while true {
            skipWhitespace()
            guard position < bytes.count else { throw fail("Unfinished JSON term") }
            guard bytes[position] == UInt8(ascii: "\"") else { throw fail("Object keys must be strings") }
            let key = try readString()
            skipWhitespace()
            guard position < bytes.count, bytes[position] == UInt8(ascii: ":") else { throw fail("Objects must consist of key:value pairs") }
            position += 1
            skipWhitespace()
            let value = try read(depth: depth + 1)
            deepest = max(deepest, value.depth)
             
            var repeated: Int?
            if keys.count >= 16 {
                if seen == nil { seen = Set(keys.map { ModuleJSONKey(string: $0) }) }
                if seen!.contains(ModuleJSONKey(string: key)) {
                    repeated = keys.firstIndex { ModuleJSONBytes.equal($0, key) }
                } else {
                    seen!.insert(ModuleJSONKey(string: key))
                }
            } else {
                repeated = keys.firstIndex { ModuleJSONBytes.equal($0, key) }
            }
            if let repeated {
                pending[start + repeated] = value
            } else {
                keys.append(key)
                pending.append(value)
            }
            skipWhitespace()
            guard position < bytes.count else { throw fail("Unfinished JSON term") }
            let byte = bytes[position]
            position += 1
            if byte == UInt8(ascii: ",") { continue }
            if byte == UInt8(ascii: "}") { break }
            throw fail("Expected separator between values")
        }
        let shape = ModuleJSONKeyList(keys: keys)
        if let shared = shapes[shape] {
            keys = shared
        } else {
            keys = keys.withUnsafeBufferPointer { Array($0) }
            if shapes.count < Self.maximumShapes { shapes[shape] = keys }
        }
        return .object(ModuleJSONObject(uniqueKeys: keys, values: takePending(from: start), childDepth: deepest))
    }

    private mutating func readString() throws -> String {
        position += 1
        let start = position
         
        while position < bytes.count {
            let byte = bytes[position]
            if byte == UInt8(ascii: "\"") {
                let text = String(decoding: UnsafeBufferPointer(rebasing: bytes[start..<position]), as: UTF8.self)
                position += 1
                return text
            }
            if byte == UInt8(ascii: "\\") { break }
            if byte < 0x20 { throw fail("Invalid string: control characters from U+0000 through U+001F must be escaped") }
            if byte >= 0x80 { try skipUTF8() } else { position += 1 }
        }
        var buffer = Array(UnsafeBufferPointer(rebasing: bytes[start..<min(position, bytes.count)]))
        while position < bytes.count {
            let byte = bytes[position]
            if byte == UInt8(ascii: "\"") {
                position += 1
                return String(decoding: buffer, as: UTF8.self)
            }
            if byte < 0x20 { throw fail("Invalid string: control characters from U+0000 through U+001F must be escaped") }
            if byte == UInt8(ascii: "\\") {
                position += 1
                guard position < bytes.count else { break }
                let escape = bytes[position]
                position += 1
                switch escape {
                case UInt8(ascii: "\""): buffer.append(0x22)
                case UInt8(ascii: "\\"): buffer.append(0x5C)
                case UInt8(ascii: "/"): buffer.append(0x2F)
                case UInt8(ascii: "b"): buffer.append(0x08)
                case UInt8(ascii: "f"): buffer.append(0x0C)
                case UInt8(ascii: "n"): buffer.append(0x0A)
                case UInt8(ascii: "r"): buffer.append(0x0D)
                case UInt8(ascii: "t"): buffer.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try readHex4()
                    if (0xD800...0xDBFF).contains(scalar) {
                        guard position + 1 < bytes.count, bytes[position] == UInt8(ascii: "\\"), bytes[position + 1] == UInt8(ascii: "u") else {
                            throw fail("Invalid \\uXXXX\\uXXXX surrogate pair escape")
                        }
                        position += 2
                        let low = try readHex4()
                        guard (0xDC00...0xDFFF).contains(low) else { throw fail("Invalid \\uXXXX\\uXXXX surrogate pair escape") }
                        scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                    } else if (0xDC00...0xDFFF).contains(scalar) {
                        throw fail("Invalid \\uXXXX\\uXXXX surrogate pair escape")
                    }
                    Self.appendUTF8(UInt32(scalar), to: &buffer)
                default:
                    throw fail("Invalid escape")
                }
                continue
            }
            if byte >= 0x80 {
                let from = position
                try skipUTF8()
                buffer.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[from..<position]))
            } else {
                buffer.append(byte)
                position += 1
            }
        }
        throw fail("Unfinished string")
    }

    private mutating func readHex4() throws -> Int {
        guard position + 4 <= bytes.count else { throw fail("Invalid escape") }
        var value = 0
        for _ in 0..<4 {
            let byte = bytes[position]
            let digit: Int
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = Int(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = Int(byte - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = Int(byte - UInt8(ascii: "A")) + 10
            default: throw fail("Invalid characters in \\uXXXX escape")
            }
            value = value * 16 + digit
            position += 1
        }
        return value
    }

     
    private mutating func skipUTF8() throws {
        let lead = bytes[position]
        let length: Int
        var minimum: UInt32
        var scalar: UInt32
        switch lead {
        case 0xC2...0xDF: length = 2; minimum = 0x80; scalar = UInt32(lead & 0x1F)
        case 0xE0...0xEF: length = 3; minimum = 0x800; scalar = UInt32(lead & 0x0F)
        case 0xF0...0xF4: length = 4; minimum = 0x10000; scalar = UInt32(lead & 0x07)
        default: throw fail("Invalid UTF-8")
        }
        guard position + length <= bytes.count else { throw fail("Invalid UTF-8") }
        for offset in 1..<length {
            let next = bytes[position + offset]
            guard next & 0xC0 == 0x80 else { throw fail("Invalid UTF-8") }
            scalar = scalar << 6 | UInt32(next & 0x3F)
        }
        guard scalar >= minimum, scalar <= 0x10FFFF, !(0xD800...0xDFFF).contains(scalar) else { throw fail("Invalid UTF-8") }
        minimum = 0
        position += length
    }

    static func appendUTF8(_ scalar: UInt32, to buffer: inout [UInt8]) {
        switch scalar {
        case 0..<0x80:
            buffer.append(UInt8(scalar))
        case 0x80..<0x800:
            buffer.append(UInt8(0xC0 | (scalar >> 6)))
            buffer.append(UInt8(0x80 | (scalar & 0x3F)))
        case 0x800..<0x10000:
            buffer.append(UInt8(0xE0 | (scalar >> 12)))
            buffer.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
            buffer.append(UInt8(0x80 | (scalar & 0x3F)))
        default:
            buffer.append(UInt8(0xF0 | (scalar >> 18)))
            buffer.append(UInt8(0x80 | ((scalar >> 12) & 0x3F)))
            buffer.append(UInt8(0x80 | ((scalar >> 6) & 0x3F)))
            buffer.append(UInt8(0x80 | (scalar & 0x3F)))
        }
    }

     
    private mutating func readStrictLiteral() throws -> ModuleJSONValue {
        let start = position
        func expect(_ word: StaticString) -> Bool {
            let length = word.utf8CodeUnitCount
            guard position + length <= bytes.count else { return false }
            for offset in 0..<length where bytes[position + offset] != word.utf8Start[offset] { return false }
            position += length
            return true
        }
        switch bytes[position] {
        case UInt8(ascii: "t"): if expect("true") { return .bool(true) }
        case UInt8(ascii: "f"): if expect("false") { return .bool(false) }
        case UInt8(ascii: "n"): if expect("null") { return .null }
        default: break
        }
        position = start
        func digits() -> Int {
            let from = position
            while position < bytes.count, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(bytes[position]) { position += 1 }
            return position - from
        }
        if position < bytes.count, bytes[position] == UInt8(ascii: "-") { position += 1 }
        guard position < bytes.count else { throw fail("Invalid numeric literal") }
        if bytes[position] == UInt8(ascii: "0") {
            position += 1
        } else if digits() == 0 {
            throw fail("Invalid literal")
        }
        if position < bytes.count, bytes[position] == UInt8(ascii: ".") {
            position += 1
            guard digits() > 0 else { throw fail("Invalid numeric literal") }
        }
        if position < bytes.count, bytes[position] == UInt8(ascii: "e") || bytes[position] == UInt8(ascii: "E") {
            position += 1
            if position < bytes.count, bytes[position] == UInt8(ascii: "+") || bytes[position] == UInt8(ascii: "-") { position += 1 }
            guard digits() > 0 else { throw fail("Invalid numeric literal") }
        }
        guard let number = ModuleJSONNumberText.literal(UnsafeBufferPointer(rebasing: bytes[start..<position])) else {
            throw fail("Invalid numeric literal")
        }
        return .number(number)
    }

     
    private mutating func readLenientLiteral() throws -> ModuleJSONValue {
        let start = position
        while position < bytes.count {
            switch bytes[position] {
            case UInt8(ascii: "["), UInt8(ascii: "{"), UInt8(ascii: ":"), UInt8(ascii: ","), UInt8(ascii: "]"),
                 UInt8(ascii: "}"), UInt8(ascii: "\""), 0x20, 0x09, 0x0A, 0x0D:
                break
            default:
                position += 1
                continue
            }
            break
        }
        let token = UnsafeBufferPointer(rebasing: bytes[start..<position])
        guard !token.isEmpty else {
            position += 1
            switch bytes[start] {
            case UInt8(ascii: ","): throw fail("Expected value before ','")
            case UInt8(ascii: ":"): throw fail("':' not as part of an object")
            case UInt8(ascii: "]"), UInt8(ascii: "}"): throw fail("Unmatched '\(Character(Unicode.Scalar(bytes[start])))'")
            default: throw fail("Invalid literal")
            }
        }
        let text = String(decoding: token, as: UTF8.self)
        switch token[0] {
        case UInt8(ascii: "t"):
            guard text == "true" else { throw fail("Invalid literal") }
            return .bool(true)
        case UInt8(ascii: "f"):
            guard text == "false" else { throw fail("Invalid literal") }
            return .bool(false)
        case UInt8(ascii: "n"):
            if token.count == 3 {
                guard text == "nan" else { throw fail("Invalid literal") }
                return .number(Double.nan)
            }
            guard text == "null" else { throw fail("Invalid literal") }
            return .null
        case UInt8(ascii: "'"):
            throw fail("Invalid string literal; expected \", but got '")
        default:
            guard let number = ModuleJSONNumberText.decNumberLiteral(text) else { throw fail("Invalid numeric literal") }
            return .number(number)
        }
    }
}

 
struct ModuleJSONKeyList: Hashable {
    let keys: [String]

    static func == (a: ModuleJSONKeyList, b: ModuleJSONKeyList) -> Bool {
        guard a.keys.count == b.keys.count else { return false }
        for (x, y) in zip(a.keys, b.keys) where !ModuleJSONBytes.equal(x, y) { return false }
        return true
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(keys.count)
        for key in keys { ModuleJSONBytes.hash(key, into: &hasher) }
    }
}

 

 
 
protocol ModuleJSONSink {
    mutating func put(_ byte: UInt8) -> Bool
    mutating func put(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool
}

 
 
 
struct ModuleJSONWriter<Sink: ModuleJSONSink> {
    var sink: Sink

    init(_ sink: Sink) {
        self.sink = sink
    }

    private enum Open {
        case array(ModuleJSONArray, next: Int)
        case object(ModuleJSONObject, next: Int)
    }

     
    @discardableResult
    mutating func write(_ value: ModuleJSONValue) -> Bool {
        var open: [Open] = []
        var pending: ModuleJSONValue? = value
        while true {
            if let current = pending {
                pending = nil
                switch current {
                case .null: guard put("null") else { return false }
                case .bool(let flag): guard put(flag ? "true" : "false") else { return false }
                case .number(let number):
                    var text = ModuleJSONNumberText.text(number)
                    guard text.withUTF8({ sink.put($0) }) else { return false }
                case .string(let string): guard quoted(string) else { return false }
                case .array(let array):
                    guard sink.put(UInt8(ascii: "[")) else { return false }
                    open.append(.array(array, next: 0))
                case .object(let object):
                    guard sink.put(UInt8(ascii: "{")) else { return false }
                    open.append(.object(object, next: 0))
                }
            }
            guard let top = open.popLast() else { return true }
            switch top {
            case .array(let array, let next):
                if next == array.count {
                    guard sink.put(UInt8(ascii: "]")) else { return false }
                    continue
                }
                if next > 0, !sink.put(UInt8(ascii: ",")) { return false }
                open.append(.array(array, next: next + 1))
                pending = array[next]
            case .object(let object, let next):
                if next == object.count {
                    guard sink.put(UInt8(ascii: "}")) else { return false }
                    continue
                }
                if next > 0, !sink.put(UInt8(ascii: ",")) { return false }
                guard quoted(object.key(at: next)), sink.put(UInt8(ascii: ":")) else { return false }
                open.append(.object(object, next: next + 1))
                pending = object.value(at: next)
            }
        }
    }

    private mutating func put(_ word: StaticString) -> Bool {
        sink.put(UnsafeBufferPointer(start: word.utf8Start, count: word.utf8CodeUnitCount))
    }

    private static var hex: StaticString { "0123456789abcdef" }

     
     
    private mutating func quoted(_ string: String) -> Bool {
        guard sink.put(UInt8(ascii: "\"")) else { return false }
        var string = string
        let whole = string.withUTF8 { bytes -> Bool in
            var start = 0
            for index in 0..<bytes.count {
                let byte = bytes[index]
                let escape: (UInt8, UInt8)?
                switch byte {
                case UInt8(ascii: "\""): escape = (0x5C, 0x22)
                case UInt8(ascii: "\\"): escape = (0x5C, 0x5C)
                case 0x08: escape = (0x5C, UInt8(ascii: "b"))
                case 0x09: escape = (0x5C, UInt8(ascii: "t"))
                case 0x0A: escape = (0x5C, UInt8(ascii: "n"))
                case 0x0C: escape = (0x5C, UInt8(ascii: "f"))
                case 0x0D: escape = (0x5C, UInt8(ascii: "r"))
                case 0..<0x20, 0x7F: escape = (0, 0)
                default: continue
                }
                if index > start, !sink.put(UnsafeBufferPointer(rebasing: bytes[start..<index])) { return false }
                start = index + 1
                if let (first, second) = escape, first != 0 {
                    guard sink.put(first), sink.put(second) else { return false }
                } else {
                    let digits = Self.hex.utf8Start
                    guard sink.put(0x5C), sink.put(UInt8(ascii: "u")), sink.put(UInt8(ascii: "0")), sink.put(UInt8(ascii: "0")),
                          sink.put(digits[Int(byte >> 4)]), sink.put(digits[Int(byte & 0xF)]) else { return false }
                }
            }
            if bytes.count > start, !sink.put(UnsafeBufferPointer(rebasing: bytes[start..<bytes.count])) { return false }
            return true
        }
        return whole && sink.put(UInt8(ascii: "\""))
    }
}

 
struct ModuleJSONCountingSink: ModuleJSONSink {
    private(set) var total = 0
    let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    @inline(__always)
    mutating func put(_ byte: UInt8) -> Bool {
        total &+= 1
        return total <= limit
    }

    @inline(__always)
    mutating func put(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        total &+= bytes.count
        return total <= limit
    }
}

 
struct ModuleJSONBufferSink: ModuleJSONSink {
    private let buffer: UnsafeMutableBufferPointer<UInt8>
    private(set) var position = 0

    init(_ buffer: UnsafeMutableBufferPointer<UInt8>) {
        self.buffer = buffer
    }

    @inline(__always)
    mutating func put(_ byte: UInt8) -> Bool {
        guard position < buffer.count else { return false }
        buffer[position] = byte
        position += 1
        return true
    }

    @inline(__always)
    mutating func put(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        guard bytes.count <= buffer.count - position else { return false }
        if let source = bytes.baseAddress, let target = buffer.baseAddress {
            (target + position).update(from: source, count: bytes.count)
        }
        position += bytes.count
        return true
    }
}

 
struct ModuleJSONGrowingSink: ModuleJSONSink {
    private(set) var bytes: [UInt8] = []
    let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    mutating func put(_ byte: UInt8) -> Bool {
        guard bytes.count < limit else { return false }
        bytes.append(byte)
        return true
    }

    mutating func put(_ some: UnsafeBufferPointer<UInt8>) -> Bool {
        let room = limit - bytes.count
        bytes.append(contentsOf: some.prefix(max(0, room)))
        return some.count <= room
    }
}

 
 
struct ModuleJSONCheckedSink<Inner: ModuleJSONSink>: ModuleJSONSink {
    var inner: Inner
    private let check: () -> Bool
    private let stride: Int
    private var untilCheck: Int

    init(_ inner: Inner, every stride: Int = 64 << 10, check: @escaping () -> Bool) {
        self.inner = inner
        self.check = check
        self.stride = stride
        untilCheck = stride
    }

    @inline(__always)
    private mutating func passed(_ count: Int) -> Bool {
        untilCheck &-= count
        if untilCheck > 0 { return true }
        untilCheck = stride
        return check()
    }

    mutating func put(_ byte: UInt8) -> Bool { inner.put(byte) && passed(1) }

    mutating func put(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool { inner.put(bytes) && passed(bytes.count) }
}

 

enum ModuleJSONNumberText {
     
     
     
     
     
    static func text(_ number: ModuleJSONNumber) -> String {
        if let canonical = number.literal?.canonical { return canonical }
        return text(number.value)
    }

    static func text(_ value: Double) -> String {
        if value.isNaN { return "null" }
        var x = value
        if x == .infinity { x = .greatestFiniteMagnitude } else if x == -.infinity { x = -.greatestFiniteMagnitude }
        if x == 0 { return x.sign == .minus ? "-0" : "0" }
        if x == x.rounded(.towardZero), abs(x) < 1e15 {
            return String(Int64(x))
        }
        let parts = shortestDigits(abs(x))
        return format(negative: x < 0, digits: parts.digits, decimalPoint: parts.decimalPoint)
    }

    private static func format(negative: Bool, digits: [UInt8], decimalPoint decpt: Int) -> String {
        var out: [UInt8] = negative ? [UInt8(ascii: "-")] : []
        let n = digits.count
        if decpt <= -4 || decpt > n + 15 {
            out.append(digits[0])
            if n > 1 {
                out.append(UInt8(ascii: "."))
                out.append(contentsOf: digits[1...])
            }
            out.append(UInt8(ascii: "e"))
            let exponent = decpt - 1
            out.append(exponent < 0 ? UInt8(ascii: "-") : UInt8(ascii: "+"))
            let magnitude = abs(exponent)
            if magnitude < 10 { out.append(UInt8(ascii: "0")) }
            out.append(contentsOf: String(magnitude).utf8)
        } else if decpt <= 0 {
            out.append(contentsOf: Array("0.".utf8))
            out.append(contentsOf: [UInt8](repeating: UInt8(ascii: "0"), count: -decpt))
            out.append(contentsOf: digits)
        } else if decpt >= n {
            out.append(contentsOf: digits)
            out.append(contentsOf: [UInt8](repeating: UInt8(ascii: "0"), count: decpt - n))
        } else {
            out.append(contentsOf: digits[..<decpt])
            out.append(UInt8(ascii: "."))
            out.append(contentsOf: digits[decpt...])
        }
        return String(decoding: out, as: UTF8.self)
    }

     
     
     
    static func shortestDigits(_ x: Double) -> (digits: [UInt8], decimalPoint: Int) {
        let text = Array(x.description.utf8)
        var mantissa = text[...]
        var exponent = 0
        if let e = text.firstIndex(where: { $0 == UInt8(ascii: "e") || $0 == UInt8(ascii: "E") }) {
            mantissa = text[..<e]
            exponent = Int(String(decoding: text[(e + 1)...], as: UTF8.self)) ?? 0
        }
        var digits: [UInt8] = []
        var integerDigits = 0
        var seenPoint = false
        for byte in mantissa {
            if byte == UInt8(ascii: ".") { seenPoint = true; continue }
            guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { continue }
            digits.append(byte)
            if !seenPoint { integerDigits += 1 }
        }
        var decimalPoint = integerDigits + exponent
        var leading = 0
        while leading < digits.count - 1, digits[leading] == UInt8(ascii: "0") { leading += 1 }
        digits.removeFirst(leading)
        decimalPoint -= leading
        while digits.count > 1, digits.last == UInt8(ascii: "0") { digits.removeLast() }
        return (digits, decimalPoint)
    }

     
    static func literal(_ token: UnsafeBufferPointer<UInt8>) -> ModuleJSONNumber? {
        var negative = false
        var index = 0
        if token[index] == UInt8(ascii: "-") { negative = true; index += 1 }
         
         
        var value: Int64 = 0
        var simple = true
        var count = 0
        while index < token.count {
            let byte = token[index]
            guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { simple = false; break }
            value = value * 10 + Int64(byte - UInt8(ascii: "0"))
            count += 1
            index += 1
            if count > 15 { simple = false; break }
        }
        if simple, count > 0, !(count > 1 && token[negative ? 1 : 0] == UInt8(ascii: "0")) {
            let double = negative ? -Double(value) : Double(value)
            return ModuleJSONNumber(value: double, literal: .plain)
        }
        return decNumberLiteral(String(decoding: token, as: UTF8.self))
    }

     
     
     
     
    static func decNumberLiteral(_ text: String) -> ModuleJSONNumber? {
        var bytes = Array(text.utf8)[...]
        guard !bytes.isEmpty else { return nil }
        var negative = false
        if bytes.first == UInt8(ascii: "-") || bytes.first == UInt8(ascii: "+") {
            negative = bytes.first == UInt8(ascii: "-")
            bytes = bytes.dropFirst()
        }
        let word = String(decoding: bytes, as: UTF8.self).lowercased()
        if word == "inf" || word == "infinity" { return ModuleJSONNumber(negative ? -.infinity : .infinity) }
        if word == "nan" || word == "snan" { return ModuleJSONNumber(.nan) }
        var coefficient: [UInt8] = []
        var fraction = 0
        var seenPoint = false
        var seenDigit = false
        var index = bytes.startIndex
        while index < bytes.endIndex {
            let byte = bytes[index]
            if byte == UInt8(ascii: ".") {
                guard !seenPoint else { return nil }
                seenPoint = true
            } else if (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) {
                seenDigit = true
                coefficient.append(byte)
                if seenPoint { fraction += 1 }
            } else {
                break
            }
            index += 1
        }
        guard seenDigit else { return nil }
        var exponent = 0
        if index < bytes.endIndex {
            guard bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") else { return nil }
            index += 1
            var exponentNegative = false
            if index < bytes.endIndex, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
                exponentNegative = bytes[index] == UInt8(ascii: "-")
                index += 1
            }
            guard index < bytes.endIndex else { return nil }
            var magnitude = 0
            while index < bytes.endIndex {
                let byte = bytes[index]
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
                if magnitude < 10_000_000_000 { magnitude = magnitude * 10 + Int(byte - UInt8(ascii: "0")) }
                index += 1
            }
            exponent = exponentNegative ? -magnitude : magnitude
        }
        let double = Double(String(decoding: (negative ? [UInt8(ascii: "-")] : []) + coefficient, as: UTF8.self)
                            + (fraction > 0 || exponent != 0 ? "e\(exponent - fraction)" : "")) ?? .nan
        var significant = coefficient[...]
        while significant.count > 1, significant.first == UInt8(ascii: "0") { significant = significant.dropFirst() }
        let finalExponent = exponent - fraction
         
        let adjusted = finalExponent + significant.count - 1
        guard adjusted <= 999_999_999, adjusted >= -999_999_999 else { return ModuleJSONNumber(double) }
        let canonical = canonicalText(negative: negative, coefficient: Array(significant), exponent: finalExponent)
        if double.isFinite, canonical == Self.text(double) {
            return ModuleJSONNumber(value: double, literal: .plain)
        }
        return ModuleJSONNumber(value: double, literal: ModuleJSONLiteral(canonical: canonical))
    }

     
    static func canonicalText(negative: Bool, coefficient: [UInt8], exponent: Int) -> String {
        var out: [UInt8] = negative ? [UInt8(ascii: "-")] : []
        let n = coefficient.count
        let adjusted = exponent + n - 1
        if exponent <= 0, adjusted >= -6 {
            if exponent == 0 {
                out.append(contentsOf: coefficient)
            } else {
                let point = n + exponent
                if point > 0 {
                    out.append(contentsOf: coefficient[..<point])
                    out.append(UInt8(ascii: "."))
                    out.append(contentsOf: coefficient[point...])
                } else {
                    out.append(contentsOf: Array("0.".utf8))
                    out.append(contentsOf: [UInt8](repeating: UInt8(ascii: "0"), count: -point))
                    out.append(contentsOf: coefficient)
                }
            }
        } else {
            out.append(coefficient[0])
            if n > 1 {
                out.append(UInt8(ascii: "."))
                out.append(contentsOf: coefficient[1...])
            }
            out.append(UInt8(ascii: "E"))
            out.append(adjusted >= 0 ? UInt8(ascii: "+") : UInt8(ascii: "-"))
            out.append(contentsOf: String(abs(adjusted)).utf8)
        }
        return String(decoding: out, as: UTF8.self)
    }
}
#endif
