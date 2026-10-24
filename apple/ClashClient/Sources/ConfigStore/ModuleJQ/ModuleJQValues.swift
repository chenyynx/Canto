#if os(iOS) || os(macOS)
import Foundation

 
 
 

extension ModuleJQMachine {
    func arrayIndices(of needle: [Value], in haystack: [Value]) throws -> [Int] {
        var result: [Int] = []
        guard !needle.isEmpty else { return result }
        for start in haystack.indices {
            var matches = true
            for (offset, item) in needle.enumerated() {
                try tick()
                guard start + offset < haystack.count, haystack[start + offset] == item else {
                    matches = false
                    break
                }
            }
            if matches { result.append(start) }
        }
        return result
    }

     
     
     

    func occurrences(of needle: String, in haystack: String, overlapping: Bool, _ body: (Int) throws -> Bool) throws {
        var needle = needle, haystack = haystack
        let total = needle.utf8.count &+ haystack.utf8.count
        try charge(total >> 5)
        try reserve(needle.utf8.count * MemoryLayout<Int>.stride)
        try needle.withUTF8 { pattern in
            try haystack.withUTF8 { text in
                try ModuleJQByteSearch(pattern).forEach(in: text, overlapping: overlapping, body)
            }
        }
    }

    static func hasPrefix(_ string: String, _ affix: String) -> Bool {
        let s = string.utf8, a = affix.utf8
        return a.count <= s.count && s.prefix(a.count).elementsEqual(a)
    }

    static func hasSuffix(_ string: String, _ affix: String) -> Bool {
        let s = string.utf8, a = affix.utf8
        return a.count <= s.count && s.suffix(a.count).elementsEqual(a)
    }

     

    func has(_ t: Value, _ k: Value) throws -> Bool {
        switch (t, k) {
        case (.null, _):
            return false
        case (.object(let object), .string(let key)):
            return object.position(of: key) != nil
        case (.array(let array), .number(let number)):
            if number.value.isNaN { return false }
            let index = Self.int32(number.value)
            return index >= 0 && index < array.count
        default:
            throw fail("Cannot check whether \(t.typeName) has a \(k.typeName) key")
        }
    }

     
     

    func contains(_ a: Value, _ b: Value) throws -> Bool {
        try guardStack()
        guard a.kindRank == b.kindRank else { return false }
        switch (a, b) {
        case (.object(let x), .object(let y)):
            for key in y.keys {
                try tick()
                guard let value = x[key], try contains(value, y[key]!) else { return false }
            }
            return true
        case (.array(let x), .array(let y)):
            for item in y.items {
                var found = false
                for candidate in x.items {
                    try tick()
                    if try contains(candidate, item) {
                        found = true
                        break
                    }
                }
                if !found { return false }
            }
            return true
        case (.string(let x), .string(let y)):
            if y.isEmpty { return true }
            var found = false
            try occurrences(of: y, in: x, overlapping: false) { _ in
                found = true
                return false
            }
            return found
        default:
            return a == b
        }
    }

    func length(_ value: Value) throws -> Value {
        switch value {
        case .array(let array): return .number(Double(array.count))
        case .object(let object): return .number(Double(object.count))
        case .string(let string): return .number(Double(string.unicodeScalars.count))
        case .number(let number): return .number(Swift.abs(number.value))
        case .null: return .number(0)
        default: throw typeError(value, "has no length")
        }
    }

    func parseJSON(_ text: String) throws -> Value {
        try reserve(text.utf8.count * 24)
        try charge(text.utf8.count >> 4)
        do {
            let value = try ModuleJSONText.parseLeniently(text)
            try checkDepth(value)
            return value
        } catch let failure as ModuleJSONReadError {
            throw fail(failure.message)
        }
    }

     
     
     

    func split(_ string: String, _ separator: String) throws -> Value {
        let s = string.utf8
        try produce(s.count)
        try charge(s.count >> 4)
        var parts: [Value] = []
        if separator.isEmpty {
            try reserve(ModuleJSONLedger.arrayBytes(capacity: s.count))
            parts = string.unicodeScalars.map { .string(String($0)) }
        } else {
            let length = separator.utf8.count
            var starts: [Int] = []
            try occurrences(of: separator, in: string, overlapping: false) { start in
                try self.tick()
                try self.beforeAppend(to: starts)
                starts.append(start)
                return true
            }
            try reserve(ModuleJSONLedger.arrayBytes(capacity: starts.count + 1))
             
             
             
            parts.reserveCapacity(starts.count + 1)
            var p = 0
            var string = string
            string.withUTF8 { bytes in
                for start in starts {
                    parts.append(.string(String(decoding: UnsafeBufferPointer(rebasing: bytes[p..<start]), as: UTF8.self)))
                    p = start + length
                }
                if p < bytes.count || !starts.isEmpty {
                    parts.append(.string(String(decoding: UnsafeBufferPointer(rebasing: bytes[p..<bytes.count]), as: UTF8.self)))
                }
            }
        }
        return .array(ModuleJSONArray(parts, childDepth: 0))
    }

    func implode(_ value: Value) throws -> String {
        guard case .array(let array) = value else { throw fail("implode input must be an array") }
        try produce(array.count * 4)
        try charge(array.count >> 3)
        var scalars = String.UnicodeScalarView()
        for item in array.items {
            guard case .number(let number) = item, !number.value.isNaN else {
                throw typeError(value, "can't be imploded, unicode codepoint needs to be numeric")
            }
            let code = Self.int32(number.value)
            let scalar = (code < 0 || code > 0x10FFFF || (0xD800...0xDFFF).contains(code)) ? Unicode.Scalar(0xFFFD)! : Unicode.Scalar(UInt32(code))!
            scalars.append(scalar)
        }
        return String(scalars)
    }

     

    func sorted(_ items: [Value], keys: [Value]) throws -> [(key: Value, value: Value)] {
         
        try charge(items.count &* max(1, Int.bitWidth - items.count.leadingZeroBitCount))
        try reserve(ModuleJSONLedger.arrayBytes(capacity: items.count) * 2)
        let order = keys.indices.sorted { a, b in
            let result = ModuleJSONOrder.compare(keys[a], keys[b])
            return result != 0 ? result < 0 : a < b
        }
        return order.map { (keys[$0], items[$0]) }
    }

     
     

    func minimumOrMaximum(_ values: Value, keys: Value, minimum: Bool) throws -> Value {
        guard case .array(let items) = values else { throw typeError(values, keys, "cannot be iterated over") }
        guard case .array(let keyItems) = keys else { throw typeError(values, keys, "cannot be iterated over") }
        guard items.count == keyItems.count else { throw typeError(values, keys, "have wrong length") }
        guard !items.isEmpty else { return .null }
        try charge(items.count)
        var result = items[0], resultKey = keyItems[0]
        for index in 1..<items.count {
            let key = keyItems[index]
            if (ModuleJSONOrder.compare(key, resultKey) < 0) == minimum {
                result = items[index]
                resultKey = key
            }
        }
        return result
    }

    func toEntries(_ value: Value) throws -> Value {
        let entryKeys = ["key", "value"]
         
        try checkDepth(building: value.depth + 1)
         
        let count = value.depth > 0 ? (try length(value)).numberValue.map { Int($0) } ?? 0 : 0
        try reserve(ModuleJSONLedger.arrayBytes(capacity: count) + count * ModuleJSONLedger.objectBytes(keys: 2, values: 2, indexed: false))
        switch value {
        case .object(let object):
            try charge(object.count)
            let keys = object.keys, values = object.values
            return .array(ModuleJSONArray(keys.indices.map {
                .object(ModuleJSONObject(uniqueKeys: entryKeys, values: [.string(keys[$0]), values[$0]]))
            }))
        case .array(let array):
            try charge(array.count)
            return .array(ModuleJSONArray(array.items.enumerated().map {
                .object(ModuleJSONObject(uniqueKeys: entryKeys, values: [.number(Double($0.offset)), $0.element]))
            }))
        default:
            throw typeError(value, "has no keys")
        }
    }

     

    func fromEntries(_ entries: [Value]) throws -> Value {
        var result = Value.null
        for entry in entries {
            try tick()
            var key = Value.null
            for name in ["key", "Key", "name", "Name"] {
                key = try self.index(entry, .string(name))
                if key.isTruthy { break }
            }
            let item = try self.has(entry, .string("value")) ? try self.index(entry, .string("value")) : try self.index(entry, .string("Value"))
            guard case .string(let name) = key else { throw self.fail("Cannot use \(key.typeName) (\(Self.dump(key))) as object key") }
            try checkDepth(building: item.depth + 1)
            var object: ModuleJSONObject
            if case .object(let existing) = result { object = existing } else { object = ModuleJSONObject() }
            result = .null
            object.set(name, item)
            result = .object(object)
        }
        if case .null = result { return .emptyObject }
        return result
    }

     

    func add(_ value: Value) throws -> Value {
        var result = Value.null
        try iterate(value, nil) { item, _ in
            try self.tick()
            if case .string(let more) = item, case .string(var text) = result {
                 
                try self.produce(text.utf8.count + more.utf8.count)
                result = .null
                text += more
                result = .string(text)
            } else if case .array(let more) = item, case .array(var array) = result {
                try self.reserve(ModuleJSONLedger.arrayBytes(capacity: array.count + more.count))
                try self.charge(more.count >> 4)
                result = .null
                array.modify { $0.append(contentsOf: more.items) }
                result = .array(array)
                try self.checkMemory()
            } else {
                result = try self.binary(.plus, result, item)
            }
        }
        return result
    }

     

    func join(_ value: Value, _ separator: Value) throws -> Value {
        var result = Value.null
        try iterate(value, nil) { item, _ in
            try self.tick()
            var piece: Value
            switch item {
            case .bool, .number: piece = .string(try self.tostring(item))
            case .null: piece = .string("")
            default: piece = item
            }
            var left: Value
            if case .null = result {
                left = .string("")
            } else if case .string(var text) = result, case .string(let more) = separator {
                try self.produce(text.utf8.count + more.utf8.count)
                result = .null
                text += more
                left = .string(text)
            } else {
                left = try self.binary(.plus, result, separator)
            }
            if case .string(var text) = left, case .string(let more) = piece {
                try self.produce(text.utf8.count + more.utf8.count)
                left = .null
                text += more
                result = .string(text)
            } else {
                result = try self.binary(.plus, left, piece)
            }
        }
        if case .null = result { return .string("") }
        if case .bool(false) = result { return .string("") }
        return result
    }

     

    func reverse(_ value: Value) throws -> Value {
        if case .array(let array) = value {
            try reserve(ModuleJSONLedger.arrayBytes(capacity: array.count))
            return .array(ModuleJSONArray(array.items.reversed(), childDepth: array.depth - 1))
        }
        guard case .number(let count) = try length(value) else { return .emptyArray }
        if count.value <= 0 { return .emptyArray }
        _ = try index(value, .number(count.value - 1))
        return .emptyArray
    }

    func binary(_ operation: ModuleJQBinaryOperator, _ a: Value, _ b: Value) throws -> Value {
        switch operation {
        case .plus:
            switch (a, b) {
            case (.null, _): return b
            case (_, .null): return a
            case (.number(let x), .number(let y)): return .number(x.value + y.value)
            case (.string(let x), .string(let y)):
                try produce(x.utf8.count + y.utf8.count)
                return .string(x + y)
            case (.array(let x), .array(let y)):
                 
                try reserve(ModuleJSONLedger.arrayBytes(capacity: x.count + y.count))
                try charge((x.count + y.count) >> 4)
                var joined = x
                joined.modify { $0.append(contentsOf: y.items) }
                try checkMemory()
                return .array(joined)
            case (.object(let x), .object(let y)):
                try reserve(ModuleJSONLedger.objectBytes(keys: x.count + y.count, values: x.count + y.count, indexed: x.count + y.count > 32))
                try charge(y.count >> 2)
                var merged = x
                for (key, value) in zip(y.keys, y.values) { merged.set(key, value) }
                try checkMemory()
                return .object(merged)
            default:
                throw typeError(a, b, "cannot be added")
            }
        case .minus:
            switch (a, b) {
            case (.number(let x), .number(let y)): return .number(x.value - y.value)
            case (.array(let x), .array(let y)):
                try charge(x.count * max(1, y.count) / 16)
                try reserve(ModuleJSONLedger.arrayBytes(capacity: x.count))
                return .array(ModuleJSONArray(x.items.filter { item in !y.items.contains { $0 == item } }))
            default:
                throw typeError(a, b, "cannot be subtracted")
            }
        case .multiply:
            switch (a, b) {
            case (.number(let x), .number(let y)):
                return .number(x.value * y.value)
            case (.string(let text), .number(let n)), (.number(let n), .string(let text)):
                let d = n.value
                if d < 0 || d.isNaN { return .null }
                let times = d >= 2_147_483_647 ? Int(Int32.max) : Int(d)
                let bytes = times.multipliedReportingOverflow(by: max(1, text.utf8.count)).partialValue
                try produce(bytes)
                try charge(bytes >> 6)
                return .string(String(repeating: text, count: times))
            case (.object(let x), .object(let y)):
                return .object(try deepMerge(x, y))
            default:
                throw typeError(a, b, "cannot be multiplied")
            }
        case .divide:
            switch (a, b) {
            case (.number(let x), .number(let y)):
                if y.value == 0 { throw typeError(a, b, "cannot be divided because the divisor is zero") }
                return .number(x.value / y.value)
            case (.string(let x), .string(let y)):
                return try split(x, y)
            default:
                throw typeError(a, b, "cannot be divided")
            }
        case .modulo:
             
            guard case .number(let x) = a, case .number(let y) = b else { throw typeError(a, b, "cannot be divided (remainder)") }
            if x.value.isNaN || y.value.isNaN { return .number(.nan) }
            let divisor = Self.saturatingInt64(y.value)
            if divisor == 0 { throw typeError(a, b, "cannot be divided (remainder) because the divisor is zero") }
            return .number(divisor == -1 ? 0 : Double(Self.saturatingInt64(x.value) % divisor))
        case .equal: return .bool(a == b)
        case .notEqual: return .bool(!(a == b))
        case .less: return .bool(ModuleJSONOrder.compare(a, b) < 0)
        case .lessOrEqual: return .bool(ModuleJSONOrder.compare(a, b) <= 0)
        case .greater: return .bool(ModuleJSONOrder.compare(a, b) > 0)
        case .greaterOrEqual: return .bool(ModuleJSONOrder.compare(a, b) >= 0)
        }
    }

    static func saturatingInt64(_ x: Double) -> Int64 {
        if x >= 9.223372036854775807e18 { return .max }
        if x <= -9.223372036854775808e18 { return .min }
        return Int64(x)
    }

     

    func deepMerge(_ a: ModuleJSONObject, _ b: ModuleJSONObject) throws -> ModuleJSONObject {
        try guardStack()
        var merged = a
        for (key, value) in zip(b.keys, b.values) {
            try tick()
            if case .object(let left)? = merged[key], case .object(let right) = value {
                merged.set(key, .object(try deepMerge(left, right)))
            } else {
                merged.set(key, value)
            }
        }
        return merged
    }

    static func math1(_ name: String, _ x: Double) -> Double {
        switch name {
        case "acos": return Foundation.acos(x)
        case "acosh": return Foundation.acosh(x)
        case "asin": return Foundation.asin(x)
        case "asinh": return Foundation.asinh(x)
        case "atan": return Foundation.atan(x)
        case "atanh": return Foundation.atanh(x)
        case "cbrt": return Foundation.cbrt(x)
        case "ceil": return Foundation.ceil(x)
        case "cos": return Foundation.cos(x)
        case "cosh": return Foundation.cosh(x)
        case "exp": return Foundation.exp(x)
        case "exp10": return __exp10(x)
        case "exp2": return Foundation.exp2(x)
        case "expm1": return Foundation.expm1(x)
        case "fabs": return Swift.abs(x)
        case "floor": return Foundation.floor(x)
        case "gamma", "lgamma": return Foundation.lgamma(x)
        case "j0": return Foundation.j0(x)
        case "j1": return Foundation.j1(x)
        case "log": return Foundation.log(x)
        case "log10": return Foundation.log10(x)
        case "log1p": return Foundation.log1p(x)
        case "log2": return Foundation.log2(x)
        case "logb": return Foundation.logb(x)
        case "nearbyint": return Foundation.nearbyint(x)
        case "rint": return Foundation.rint(x)
        case "round": return Foundation.round(x)
        case "significand":
            if x == 0 || !x.isFinite { return x }
            return Foundation.scalbn(x, -Int(Foundation.ilogb(x)))
        case "sin": return Foundation.sin(x)
        case "sinh": return Foundation.sinh(x)
        case "sqrt": return x.squareRoot()
        case "tan": return Foundation.tan(x)
        case "tanh": return Foundation.tanh(x)
        case "tgamma": return Foundation.tgamma(x)
        case "trunc": return Foundation.trunc(x)
        case "y0": return Foundation.y0(x)
        case "y1": return Foundation.y1(x)
        case "erf": return Foundation.erf(x)
        case "erfc": return Foundation.erfc(x)
        default: return .nan
        }
    }

    static func math2(_ name: String, _ a: Double, _ b: Double) -> Double {
        switch name {
        case "atan2": return Foundation.atan2(a, b)
        case "copysign": return Foundation.copysign(a, b)
        case "drem", "remainder": return Foundation.remainder(a, b)
        case "fdim": return Foundation.fdim(a, b)
        case "fmax": return Foundation.fmax(a, b)
        case "fmin": return Foundation.fmin(a, b)
        case "fmod": return Foundation.fmod(a, b)
        case "hypot": return Foundation.hypot(a, b)
        case "jn": return Foundation.jn(Int32(clamping: int32(a)), b)
        case "ldexp": return Foundation.scalbn(a, int32(b))
        case "nextafter", "nexttoward": return Foundation.nextafter(a, b)
        case "pow": return Foundation.pow(a, b)
        case "scalb":
            guard b.isFinite, b == b.rounded() else { return b.isNaN ? .nan : (b > 0 ? a * .infinity : a * 0) }
            return Foundation.scalbn(a, int32(b))
        case "scalbln": return Foundation.scalbn(a, Int(saturatingInt64(b.rounded(.towardZero))))
        case "yn": return Foundation.yn(Int32(clamping: int32(a)), b)
        default: return .nan
        }
    }
}

 
 
 
struct ModuleJQByteSearch {
    private let pattern: UnsafeBufferPointer<UInt8>
    private var fallback: [Int]

    init(_ pattern: UnsafeBufferPointer<UInt8>) {
        self.pattern = pattern
        var fallback = [Int](repeating: 0, count: pattern.count)
        var k = 0
        if pattern.count > 1 {
            for index in 1..<pattern.count {
                while k > 0, pattern[index] != pattern[k] { k = fallback[k - 1] }
                if pattern[index] == pattern[k] { k += 1 }
                fallback[index] = k
            }
        }
        self.fallback = fallback
    }

     
     
    func forEach(in text: UnsafeBufferPointer<UInt8>, overlapping: Bool, _ body: (Int) throws -> Bool) rethrows {
        let m = pattern.count
        guard m > 0, m <= text.count else { return }
        var k = 0
        for index in 0..<text.count {
            let byte = text[index]
            while k > 0, byte != pattern[k] { k = fallback[k - 1] }
            if byte == pattern[k] { k += 1 }
            if k == m {
                guard try body(index - m + 1) else { return }
                k = overlapping ? fallback[k - 1] : 0
            }
        }
    }
}
#endif
