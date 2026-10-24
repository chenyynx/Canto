#if os(iOS) || os(macOS)
import Foundation

 

extension ModuleJQMachine {
     
     
     
     
    func applyFormat(_ name: String, _ value: Value) throws -> String {
        switch name {
        case "text":
            return try tostring(value)
        case "json":
            return try text(value)
        case "html":
            let source = try tostring(value)
            try produce(source.utf8.count * 6)
            try charge(source.utf8.count >> 5)
            var out = ""
            for scalar in source.unicodeScalars {
                switch scalar {
                case "<": out += "&lt;"
                case ">": out += "&gt;"
                case "&": out += "&amp;"
                case "'": out += "&" + "apos;"
                case "\"": out += "&quot;"
                default: out.unicodeScalars.append(scalar)
                }
            }
            return out
        case "uri":
            let source = try tostring(value)
             
            try produce(source.utf8.count * 6)
            try charge(source.utf8.count >> 5)
            var out: [UInt8] = []
            let hex = Array("0123456789ABCDEF".utf8)
            for byte in source.utf8 {
                switch byte {
                case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                     UInt8(ascii: "-"), UInt8(ascii: "_"), UInt8(ascii: "."), UInt8(ascii: "~"):
                    out.append(byte)
                default:
                    out.append(UInt8(ascii: "%"))
                    out.append(hex[Int(byte >> 4)])
                    out.append(hex[Int(byte & 0xF)])
                }
            }
            return String(decoding: out, as: UTF8.self)
        case "csv", "tsv":
            guard case .array(let row) = value else {
                throw typeError(value, "cannot be \(name)-formatted, only an array can be")
            }
            var fields: [String] = []
            for item in row.items {
                try tick()
                switch item {
                case .null:
                    fields.append("")
                case .bool, .number:
                    if case .number(let number) = item, number.value.isNaN { fields.append(""); continue }
                    fields.append(ModuleJSONText.string(item))
                case .string(let text):
                    try produce(text.utf8.count * 2 + 2)
                    try charge(text.utf8.count >> 5)
                    if name == "csv" {
                        fields.append("\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"")
                    } else {
                        var escaped = ""
                        for scalar in text.unicodeScalars {
                            switch scalar {
                            case "\\": escaped += "\\\\"
                            case "\t": escaped += "\\t"
                            case "\n": escaped += "\\n"
                            case "\r": escaped += "\\r"
                            default: escaped.unicodeScalars.append(scalar)
                            }
                        }
                        fields.append(escaped)
                    }
                default:
                    throw typeError(item, "is not valid in a \(name) row")
                }
            }
            return fields.joined(separator: name == "csv" ? "," : "\t")
        case "sh":
            let items: [Value]
            if case .array(let array) = value { items = array.items } else { items = [value] }
            var words: [String] = []
            for item in items {
                try tick()
                switch item {
                case .string(let text):
                    try produce(text.utf8.count * 4 + 2)
                    try charge(text.utf8.count >> 5)
                    words.append("'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'")
                case .array, .object:
                    throw typeError(item, "can not be escaped for shell")
                default:
                    words.append(ModuleJSONText.string(item))
                }
            }
            return words.joined(separator: " ")
        case "base64":
            let source = try tostring(value)
             
            try produce(source.utf8.count + source.utf8.count / 3 * 4 + 4)
            try charge(source.utf8.count >> 5)
            return Data(source.utf8).base64EncodedString()
        case "base64d":
            let text = try tostring(value)
             
            try produce(text.utf8.count * 3)
            try charge(text.utf8.count >> 5)
            let data = Array(text.utf8)
            var result: [UInt8] = []
            result.reserveCapacity(data.count * 3 / 4)
            var code: UInt32 = 0
            var read = 0
            for byte in data {
                if byte == UInt8(ascii: "=") { break }
                guard let sextet = Self.base64Value(byte) else { throw typeError(value, "is not valid base64 data") }
                code |= sextet
                read += 1
                if read == 4 {
                    result.append(UInt8((code >> 16) & 0xFF))
                    result.append(UInt8((code >> 8) & 0xFF))
                    result.append(UInt8(code & 0xFF))
                    read = 0
                    code = 0
                } else {
                    code <<= 6
                }
            }
            if read == 3 {
                result.append(UInt8((code >> 16) & 0xFF))
                result.append(UInt8((code >> 8) & 0xFF))
            } else if read == 2 {
                result.append(UInt8((code >> 10) & 0xFF))
            } else if read == 1 {
                throw typeError(value, "trailing base64 byte found")
            }
            return String(decoding: result, as: UTF8.self)
        default:
            throw fail("\(name) is not a valid format")
        }
    }

    private static func base64Value(_ byte: UInt8) -> UInt32? {
        switch byte {
        case UInt8(ascii: "A")...UInt8(ascii: "Z"): return UInt32(byte - UInt8(ascii: "A"))
        case UInt8(ascii: "a")...UInt8(ascii: "z"): return UInt32(byte - UInt8(ascii: "a")) + 26
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return UInt32(byte - UInt8(ascii: "0")) + 52
        case UInt8(ascii: "+"): return 62
        case UInt8(ascii: "/"): return 63
        default: return nil
        }
    }
}
#endif
