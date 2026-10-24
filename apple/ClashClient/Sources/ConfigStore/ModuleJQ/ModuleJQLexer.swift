#if os(iOS) || os(macOS)
import Foundation

 
 
 
 

struct ModuleJQToken {
    enum Kind {
         
        case dot
         
        case recurse
         
        case field(String)
        case identifier(String)
        case keyword(String)
         
        case variable(String)
         
        case format(String)
        case number(ModuleJSONNumber)
        case string([Piece])
         
        case punctuation(String)
        case end
    }

    enum Piece {
        case text(String)
        case interpolation([ModuleJQToken])
    }

    let kind: Kind
    let line: Int

    var spelling: String {
        switch kind {
        case .dot: return "'.'"
        case .recurse: return "'..'"
        case .field(let name): return "FIELD .\(name)"
        case .identifier(let name): return "IDENT \(name)"
        case .keyword(let word): return word
        case .variable(let name): return "BINDING $\(name)"
        case .format(let name): return "FORMAT @\(name)"
        case .number: return "LITERAL"
        case .string: return "QQSTRING_START"
        case .punctuation(let text): return "'\(text)'"
        case .end: return "end of file"
        }
    }

    func isPunctuation(_ text: String) -> Bool {
        if case .punctuation(let value) = kind { return value == text }
        return false
    }

    func isKeyword(_ word: String) -> Bool {
        if case .keyword(let value) = kind { return value == word }
        return false
    }
}

struct ModuleJQSyntaxError: Error, CustomStringConvertible {
    let message: String
    var description: String { message }
}

struct ModuleJQLexer {
    static let keywords: Set<String> = [
        "def", "if", "then", "elif", "else", "end", "as", "reduce", "foreach", "try", "catch", "label",
        "import", "include", "module", "and", "or", "__loc__", "break",
    ]

    private static let punctuation: [String] = [
        "?//", "//=", "|=", "+=", "-=", "*=", "/=", "%=", "==", "!=", "<=", ">=", "//",
        "[", "]", "{", "}", "(", ")", "|", ",", ":", ";", "=", "<", ">", "+", "-", "*", "/", "%", "?",
    ]

    private let bytes: [UInt8]
    private var position = 0
    private var line = 1
     
     
    private var nesting = 0
    private let stackFloor: UInt

    init(_ text: String) {
        bytes = Array(text.utf8)
        stackFloor = ModuleJQStack.floor(reserve: ModuleJQStack.readReserve)
    }

    static func tokens(_ text: String) throws -> [ModuleJQToken] {
        var lexer = ModuleJQLexer(text)
        return try lexer.run(untilClosingParenthesis: false)
    }

    private func fail(_ message: String) -> ModuleJQSyntaxError {
        ModuleJQSyntaxError(message: "\(message) at line \(line)")
    }

    private static func isIdentifierStart(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
            || byte == UInt8(ascii: "_")
    }

    private static func isIdentifierByte(_ byte: UInt8) -> Bool {
        isIdentifierStart(byte) || isDigit(byte)
    }

    private static func isDigit(_ byte: UInt8) -> Bool { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) }

    private func peek(_ offset: Int = 0) -> UInt8? {
        position + offset < bytes.count ? bytes[position + offset] : nil
    }

     
     
    private mutating func run(untilClosingParenthesis: Bool) throws -> [ModuleJQToken] {
        var tokens: [ModuleJQToken] = []
        var depth = 0
        while true {
            skipSpaceAndComments()
            guard let byte = peek() else {
                if untilClosingParenthesis { throw fail("syntax error, unterminated string interpolation") }
                tokens.append(ModuleJQToken(kind: .end, line: line))
                return tokens
            }
            if untilClosingParenthesis {
                if byte == UInt8(ascii: "(") { depth += 1 }
                if byte == UInt8(ascii: ")") {
                    if depth == 0 {
                        position += 1
                        tokens.append(ModuleJQToken(kind: .end, line: line))
                        return tokens
                    }
                    depth -= 1
                }
            }
            tokens.append(try token(byte))
        }
    }

    private mutating func skipSpaceAndComments() {
        while let byte = peek() {
            if byte == UInt8(ascii: "#") {
                while let next = peek(), next != 0x0A { position += 1 }
            } else if byte == 0x0A {
                line += 1
                position += 1
            } else if byte == 0x20 || byte == 0x09 || byte == 0x0D {
                position += 1
            } else {
                return
            }
        }
    }

    private mutating func token(_ byte: UInt8) throws -> ModuleJQToken {
        let here = line
        if byte == UInt8(ascii: "\"") {
            position += 1
            return ModuleJQToken(kind: .string(try string()), line: here)
        }
        if byte == UInt8(ascii: ".") {
            if peek(1) == UInt8(ascii: ".") {
                position += 2
                return ModuleJQToken(kind: .recurse, line: here)
            }
            if let next = peek(1), Self.isIdentifierStart(next) {
                position += 1
                return ModuleJQToken(kind: .field(identifier(allowNamespaces: false)), line: here)
            }
            if let next = peek(1), Self.isDigit(next) {
                return ModuleJQToken(kind: .number(try number()), line: here)
            }
            position += 1
            return ModuleJQToken(kind: .dot, line: here)
        }
        if Self.isDigit(byte) {
            return ModuleJQToken(kind: .number(try number()), line: here)
        }
        if byte == UInt8(ascii: "$") {
             
            var offset = 1
            while peek(offset) == UInt8(ascii: "$") { offset += 1 }
            guard offset == 1 || offset == 4, let next = peek(offset), Self.isIdentifierStart(next) else {
                position += 1
                return ModuleJQToken(kind: .punctuation("$"), line: here)
            }
            position += offset
            return ModuleJQToken(kind: .variable(identifier(allowNamespaces: true)), line: here)
        }
        if byte == UInt8(ascii: "@") {
            position += 1
            let start = position
            while let next = peek(), Self.isIdentifierByte(next) { position += 1 }
            guard position > start else { throw fail("syntax error, unexpected INVALID_CHARACTER") }
            return ModuleJQToken(kind: .format(String(decoding: bytes[start..<position], as: UTF8.self)), line: here)
        }
        if Self.isIdentifierStart(byte) {
            let name = identifier(allowNamespaces: true)
            return ModuleJQToken(kind: Self.keywords.contains(name) ? .keyword(name) : .identifier(name), line: here)
        }
        for candidate in Self.punctuation {
            let utf8 = Array(candidate.utf8)
            if position + utf8.count <= bytes.count, Array(bytes[position..<position + utf8.count]) == utf8 {
                position += utf8.count
                return ModuleJQToken(kind: .punctuation(candidate), line: here)
            }
        }
        throw fail("syntax error, unexpected INVALID_CHARACTER")
    }

     
    private mutating func identifier(allowNamespaces: Bool) -> String {
        let start = position
        while true {
            while let next = peek(), Self.isIdentifierByte(next) { position += 1 }
            if allowNamespaces, peek() == UInt8(ascii: ":"), peek(1) == UInt8(ascii: ":"), let after = peek(2),
               Self.isIdentifierStart(after) {
                position += 2
                continue
            }
            break
        }
        return String(decoding: bytes[start..<position], as: UTF8.self)
    }

     
    private mutating func number() throws -> ModuleJSONNumber {
        let start = position
        while let next = peek(), Self.isDigit(next) { position += 1 }
        if peek() == UInt8(ascii: ".") {
            position += 1
            while let next = peek(), Self.isDigit(next) { position += 1 }
        }
        if let e = peek(), e == UInt8(ascii: "e") || e == UInt8(ascii: "E") {
            var offset = 1
            if let sign = peek(1), sign == UInt8(ascii: "+") || sign == UInt8(ascii: "-") { offset = 2 }
            if let digit = peek(offset), Self.isDigit(digit) {
                position += offset
                while let next = peek(), Self.isDigit(next) { position += 1 }
            }
        }
        let text = String(decoding: bytes[start..<position], as: UTF8.self)
        guard let number = ModuleJSONNumberText.decNumberLiteral(text) else { throw fail("Invalid numeric literal") }
         
         
        if let literal = number.literal, literal === ModuleJSONLiteral.plain {
            return ModuleJSONNumber(value: number.value, literal: ModuleJSONLiteral(canonical: nil))
        }
        return number
    }

     
    private mutating func string() throws -> [ModuleJQToken.Piece] {
        var pieces: [ModuleJQToken.Piece] = []
        var buffer: [UInt8] = []
        func flush() {
            if !buffer.isEmpty {
                pieces.append(.text(String(decoding: buffer, as: UTF8.self)))
                buffer.removeAll()
            }
        }
        while let byte = peek() {
            position += 1
            if byte == UInt8(ascii: "\"") {
                flush()
                if pieces.isEmpty { pieces.append(.text("")) }
                return pieces
            }
            if byte == 0x0A { line += 1 }
            guard byte == UInt8(ascii: "\\") else {
                buffer.append(byte)
                continue
            }
            guard let escape = peek() else { break }
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
                var scalar = try hex4()
                if (0xD800...0xDBFF).contains(scalar) {
                    guard peek() == UInt8(ascii: "\\"), peek(1) == UInt8(ascii: "u") else {
                        throw fail("Invalid \\uXXXX\\uXXXX surrogate pair escape")
                    }
                    position += 2
                    let low = try hex4()
                    guard (0xDC00...0xDFFF).contains(low) else { throw fail("Invalid \\uXXXX\\uXXXX surrogate pair escape") }
                    scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                } else if (0xDC00...0xDFFF).contains(scalar) {
                    throw fail("Invalid \\uXXXX\\uXXXX surrogate pair escape")
                }
                ModuleJSONReader.appendUTF8(UInt32(scalar), to: &buffer)
            case UInt8(ascii: "("):
                flush()
                guard nesting < ModuleJQParser.maximumNesting else {
                    throw ModuleJQSyntaxError(message: "the program nests deeper than \(ModuleJQParser.maximumNesting) levels")
                }
                guard ModuleJQStack.address() >= stackFloor else {
                    throw ModuleJQSyntaxError(message: "the program nests too deep for the thread's stack")
                }
                var inner = ModuleJQLexer(bytes: bytes, position: position, line: line, nesting: nesting + 1, stackFloor: stackFloor)
                let tokens = try inner.run(untilClosingParenthesis: true)
                position = inner.position
                line = inner.line
                pieces.append(.interpolation(tokens))
            default:
                throw fail("Invalid escape")
            }
        }
        throw fail("syntax error, unterminated string")
    }

    private init(bytes: [UInt8], position: Int, line: Int, nesting: Int, stackFloor: UInt) {
        self.bytes = bytes
        self.position = position
        self.line = line
        self.nesting = nesting
        self.stackFloor = stackFloor
    }

    private mutating func hex4() throws -> Int {
        var value = 0
        for _ in 0..<4 {
            guard let byte = peek() else { throw fail("Invalid escape") }
            let digit: Int
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"): digit = Int(byte - UInt8(ascii: "0"))
            case UInt8(ascii: "a")...UInt8(ascii: "f"): digit = Int(byte - UInt8(ascii: "a")) + 10
            case UInt8(ascii: "A")...UInt8(ascii: "F"): digit = Int(byte - UInt8(ascii: "A")) + 10
            default: throw fail("Invalid escape")
            }
            value = value * 16 + digit
            position += 1
        }
        return value
    }
}
#endif
