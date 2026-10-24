#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 

 
enum ModuleJSONValue: Sendable {
    case null
    case bool(Bool)
    case number(ModuleJSONNumber)
    case string(String)
    case array(ModuleJSONArray)
    case object(ModuleJSONObject)

    static func number(_ value: Double) -> ModuleJSONValue { .number(ModuleJSONNumber(value)) }

    static let emptyArray = ModuleJSONValue.array(ModuleJSONArray())
    static let emptyObject = ModuleJSONValue.object(ModuleJSONObject())

     
    var typeName: String {
        switch self {
        case .null: return "null"
        case .bool: return "boolean"
        case .number: return "number"
        case .string: return "string"
        case .array: return "array"
        case .object: return "object"
        }
    }

     
    var kindRank: Int {
        switch self {
        case .null: return 1
        case .bool(let value): return value ? 3 : 2
        case .number: return 4
        case .string: return 5
        case .array: return 6
        case .object: return 7
        }
    }

     
    var isTruthy: Bool {
        switch self {
        case .null: return false
        case .bool(let value): return value
        default: return true
        }
    }

     
    var depth: Int {
        switch self {
        case .array(let array): return array.depth
        case .object(let object): return object.depth
        default: return 0
        }
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var numberValue: Double? {
        if case .number(let value) = self { return value.value }
        return nil
    }
}

 

 
 
 
 
struct ModuleJSONNumber: Sendable {
    let value: Double
     
    let literal: ModuleJSONLiteral?

    init(_ value: Double) {
        self.value = value
        literal = nil
    }

    init(value: Double, literal: ModuleJSONLiteral?) {
        self.value = value
        self.literal = literal
    }
}

 
 
 
final class ModuleJSONLiteral: Sendable {
     
    let canonical: String?

    init(canonical: String?) {
        self.canonical = canonical
    }

    static let plain = ModuleJSONLiteral(canonical: nil)
}

 

 
enum ModuleJSONBytes {
    @inline(__always)
    static func equal(_ a: String, _ b: String) -> Bool {
        let ua = a.utf8, ub = b.utf8
        guard ua.count == ub.count else { return false }
        if ua.isEmpty { return true }
        if let result = ua.withContiguousStorageIfAvailable({ pa in
            ub.withContiguousStorageIfAvailable { pb in memcmp(pa.baseAddress!, pb.baseAddress!, pa.count) == 0 }
        }), let result {
            return result
        }
        return ua.elementsEqual(ub)
    }

    static func compare(_ a: String, _ b: String) -> Int {
        let ua = a.utf8, ub = b.utf8
        let shorter = min(ua.count, ub.count)
        if shorter > 0 {
            let fast = ua.withContiguousStorageIfAvailable { pa in
                ub.withContiguousStorageIfAvailable { pb in Int(memcmp(pa.baseAddress!, pb.baseAddress!, shorter)) }
            }
            if let outer = fast, let result = outer {
                if result != 0 { return result < 0 ? -1 : 1 }
            } else {
                for (x, y) in zip(ua, ub) where x != y { return x < y ? -1 : 1 }
            }
        }
        return ua.count == ub.count ? 0 : (ua.count < ub.count ? -1 : 1)
    }

    static func hash(_ string: String, into hasher: inout Hasher) {
        let utf8 = string.utf8
        hasher.combine(utf8.count)
        if utf8.withContiguousStorageIfAvailable({ hasher.combine(bytes: UnsafeRawBufferPointer($0)) }) == nil {
            for byte in utf8 { hasher.combine(byte) }
        }
    }
}

 
struct ModuleJSONKey: Hashable, Sendable {
    let string: String

    static func == (a: ModuleJSONKey, b: ModuleJSONKey) -> Bool { ModuleJSONBytes.equal(a.string, b.string) }

    func hash(into hasher: inout Hasher) { ModuleJSONBytes.hash(string, into: &hasher) }
}

 

 
 
 
 
 
 
 
 
 
 
 
final class ModuleJSONLedger {
     
    var live = 0
     
     
    let run: UInt32

    init() {
        run = UInt32.random(in: 1...UInt32.max)
    }

    var total: Int { live }

     
     
     
    @inline(__always)
    static func stringBytes(_ string: String) -> Int {
        let count = string.utf8.count
        return count > 15 ? count &+ 32 : 0
    }

    @inline(__always)
    static func stringBytes(_ value: ModuleJSONValue) -> Int {
        if case .string(let string) = value { return stringBytes(string) }
        return 0
    }

    private static let key: pthread_key_t = {
        var key = pthread_key_t()
        guard pthread_key_create(&key, nil) == 0 else { preconditionFailure("no thread-specific key for the jq ledger") }
        return key
    }()

     
    @inline(__always)
    static var current: ModuleJSONLedger? {
        guard let raw = pthread_getspecific(key) else { return nil }
        return Unmanaged<ModuleJSONLedger>.fromOpaque(raw).takeUnretainedValue()
    }

     
    static func begin(_ ledger: ModuleJSONLedger) -> UnsafeMutableRawPointer? {
        let previous = pthread_getspecific(key)
        pthread_setspecific(key, Unmanaged.passUnretained(ledger).toOpaque())
        return previous
    }

    static func end(restoring previous: UnsafeMutableRawPointer?) {
        pthread_setspecific(key, previous)
    }

     
     
    @inline(__always)
    static func arrayBytes(capacity: Int) -> Int { 64 &+ capacity &* MemoryLayout<ModuleJSONValue>.stride }

    @inline(__always)
    static func objectBytes(keys: Int, values: Int, indexed: Bool) -> Int {
        var bytes = 112 &+ keys &* MemoryLayout<String>.stride &+ values &* MemoryLayout<ModuleJSONValue>.stride
        if indexed { bytes &+= 48 &+ keys &* 48 }
        return bytes
    }
}

 
 
 
enum ModuleJSONRelease {
     
    static let shallow: Int32 = 16

    static func drain(_ items: inout [ModuleJSONValue]) {
        var work: [ModuleJSONValue] = []
        swap(&work, &items)
        while var value = work.popLast() {
            value.handOver(into: &work)
        }
    }
}

extension ModuleJSONValue {
     
     
     
     
    fileprivate mutating func handOver(into work: inout [ModuleJSONValue]) {
        if var array = takeArray() {
            guard array.storage.depth > 1, isKnownUniquelyReferenced(&array.storage) else { return }
            array.storage.settle()
            work.append(contentsOf: array.storage.items)
            array.storage.items = []
        } else if var object = takeObject() {
            guard object.storage.depth > 1, isKnownUniquelyReferenced(&object.storage) else { return }
            object.storage.settle()
            work.append(contentsOf: object.storage.values)
            object.storage.values = []
        }
    }

    private mutating func takeArray() -> ModuleJSONArray? {
        guard case .array(let array) = self else { return nil }
        self = .null
        return array
    }

    private mutating func takeObject() -> ModuleJSONObject? {
        guard case .object(let object) = self else { return nil }
        self = .null
        return object
    }
}

 

 
struct ModuleJSONArray: Sendable {
    fileprivate final class Storage: @unchecked Sendable {
        var items: [ModuleJSONValue]
        var depth: Int32
         
         
         
        private(set) var run: UInt32 = 0
         
        var strings = 0

        init(_ items: [ModuleJSONValue], depth: Int32) {
            self.items = items
            self.depth = depth
            if let ledger = ModuleJSONLedger.current {
                run = ledger.run
                for item in items { strings &+= ModuleJSONLedger.stringBytes(item) }
                ledger.live &+= charge
            }
        }

        private var charge: Int { ModuleJSONLedger.arrayBytes(capacity: items.capacity) &+ strings }

         
        func recountStrings() {
            guard run != 0 else { return }
            strings = 0
            for item in items { strings &+= ModuleJSONLedger.stringBytes(item) }
        }

         
        private init() {
            items = []
            depth = 1
        }

        static let empty = Storage()

         
        @inline(__always)
        func changing(_ body: () throws -> Void) rethrows {
            guard run != 0, let ledger = ModuleJSONLedger.current, ledger.run == run else { return try body() }
            let before = charge
            defer { ledger.live &+= charge &- before }
            try body()
        }

         
        func settle() {
            if run != 0, let ledger = ModuleJSONLedger.current, ledger.run == run { ledger.live &-= charge }
            run = 0
        }

        deinit {
            settle()
            if depth > ModuleJSONRelease.shallow { ModuleJSONRelease.drain(&items) }
        }
    }

    fileprivate var storage: Storage

    init() {
        storage = .empty
    }

    init(_ items: [ModuleJSONValue]) {
        var deepest = 0
        for item in items { deepest = max(deepest, item.depth) }
        storage = items.isEmpty ? .empty : Storage(items, depth: Int32(clamping: deepest + 1))
    }

     
    init(_ items: [ModuleJSONValue], childDepth: Int) {
        storage = items.isEmpty ? .empty : Storage(items, depth: Int32(clamping: childDepth + 1))
    }

    var items: [ModuleJSONValue] { storage.items }
    var count: Int { storage.items.count }
    var isEmpty: Bool { storage.items.isEmpty }
    var depth: Int { Int(storage.depth) }

    subscript(index: Int) -> ModuleJSONValue { storage.items[index] }

     
    func isIdentical(to other: ModuleJSONArray) -> Bool { storage === other.storage }

     
    mutating func modify<R>(_ body: (inout [ModuleJSONValue]) throws -> R) rethrows -> R {
        if !isKnownUniquelyReferenced(&storage) || storage === Storage.empty {
            storage = Storage(storage.items, depth: storage.depth)
        }
        var result: R?
        try storage.changing {
            result = try body(&storage.items)
            storage.recountStrings()
        }
        var deepest = 0
        for item in storage.items { deepest = max(deepest, item.depth) }
        storage.depth = Int32(clamping: deepest + 1)
        return result!
    }

     
    mutating func set(_ index: Int, _ value: ModuleJSONValue) {
        if !isKnownUniquelyReferenced(&storage) || storage === Storage.empty {
            storage = Storage(storage.items, depth: storage.depth)
        }
         
         
        storage.changing {
            if storage.run != 0 {
                storage.strings &+= ModuleJSONLedger.stringBytes(value) &- ModuleJSONLedger.stringBytes(storage.items[index])
            }
            storage.items[index] = value
        }
        storage.depth = max(storage.depth, Int32(clamping: value.depth + 1))
    }

     
     
    mutating func remove(at index: Int) {
        if !isKnownUniquelyReferenced(&storage) || storage === Storage.empty {
            storage = Storage(storage.items, depth: storage.depth)
        }
        storage.changing {
            let removed = storage.items.remove(at: index)
            if storage.run != 0 { storage.strings &-= ModuleJSONLedger.stringBytes(removed) }
        }
    }

    mutating func append(_ value: ModuleJSONValue) {
        if !isKnownUniquelyReferenced(&storage) || storage === Storage.empty {
            storage = Storage(storage.items, depth: storage.depth)
        }
        storage.changing {
            storage.items.append(value)
            if storage.run != 0 { storage.strings &+= ModuleJSONLedger.stringBytes(value) }
        }
        storage.depth = max(storage.depth, Int32(clamping: value.depth + 1))
    }
}

 

 
 
 
struct ModuleJSONObject: Sendable {
    static let indexThreshold = 32

    fileprivate final class Storage: @unchecked Sendable {
        var keys: [String] {
            didSet { sortedKeys = nil }
        }
        var values: [ModuleJSONValue]
        var index: [ModuleJSONKey: Int]?
        var depth: Int32
         
         
         
         
        var sortedKeys: [String]?
        private(set) var run: UInt32 = 0
         
        var strings = 0

        init(keys: [String], values: [ModuleJSONValue], index: [ModuleJSONKey: Int]?, depth: Int32,
             sortedKeys: [String]? = nil) {
            self.keys = keys
            self.values = values
            self.index = index
            self.depth = depth
            self.sortedKeys = sortedKeys
            if let ledger = ModuleJSONLedger.current {
                run = ledger.run
                recountStrings()
                ledger.live &+= charge
            }
        }

        private var charge: Int {
            ModuleJSONLedger.objectBytes(keys: keys.capacity, values: values.capacity, indexed: index != nil) &+ strings
        }

        func recountStrings() {
            guard run != 0 else { return }
            strings = 0
            for key in keys { strings &+= ModuleJSONLedger.stringBytes(key) }
            for value in values { strings &+= ModuleJSONLedger.stringBytes(value) }
        }

         
        private init() {
            keys = []
            values = []
            depth = 1
        }

        static let empty = Storage()

        func copy() -> Storage { Storage(keys: keys, values: values, index: index, depth: depth, sortedKeys: sortedKeys) }

        @inline(__always)
        func changing(_ body: () throws -> Void) rethrows {
            guard run != 0, let ledger = ModuleJSONLedger.current, ledger.run == run else { return try body() }
            let before = charge
            defer { ledger.live &+= charge &- before }
            try body()
        }

        func settle() {
            if run != 0, let ledger = ModuleJSONLedger.current, ledger.run == run { ledger.live &-= charge }
            run = 0
        }

        deinit {
            settle()
            if depth > ModuleJSONRelease.shallow { ModuleJSONRelease.drain(&values) }
        }

        func position(of key: String) -> Int? {
            if let index { return index[ModuleJSONKey(string: key)] }
            for (position, candidate) in keys.enumerated() where ModuleJSONBytes.equal(candidate, key) { return position }
            return nil
        }

        func rebuildIndex() {
            guard keys.count > ModuleJSONObject.indexThreshold else { index = nil; return }
            var built = [ModuleJSONKey: Int](minimumCapacity: keys.count)
            for (position, key) in keys.enumerated() { built[ModuleJSONKey(string: key)] = position }
            index = built
        }
    }

    fileprivate var storage: Storage

    init() {
        storage = .empty
    }

     
     
    init(uniqueKeys keys: [String], values: [ModuleJSONValue], childDepth: Int? = nil) {
        precondition(keys.count == values.count)
        if keys.isEmpty {
            storage = .empty
            return
        }
        let deepest: Int
        if let childDepth {
            deepest = childDepth
        } else {
            var found = 0
            for value in values { found = max(found, value.depth) }
            deepest = found
        }
        storage = Storage(keys: keys, values: values, index: nil, depth: Int32(clamping: deepest + 1))
        if keys.count > Self.indexThreshold { storage.changing { storage.rebuildIndex() } }
    }

     
    init(_ pairs: [(String, ModuleJSONValue)]) {
        self.init()
        for (key, value) in pairs { self[key] = value }
    }

    var keys: [String] { storage.keys }
    var values: [ModuleJSONValue] { storage.values }
    var count: Int { storage.keys.count }
    var isEmpty: Bool { storage.keys.isEmpty }
    var depth: Int { Int(storage.depth) }

     
    var sortedKeys: [String] {
        if let sorted = storage.sortedKeys { return sorted }
        let sorted = storage.keys.sorted { ModuleJSONBytes.compare($0, $1) < 0 }
        if storage !== Storage.empty { storage.sortedKeys = sorted }
        return sorted
    }

     
     
    static func settleSortedKeys(in value: ModuleJSONValue) {
        var work = [value]
        while let next = work.popLast() {
            switch next {
            case .array(let array): work.append(contentsOf: array.items)
            case .object(let object):
                _ = object.sortedKeys
                work.append(contentsOf: object.values)
            default: break
            }
        }
    }

    func isIdentical(to other: ModuleJSONObject) -> Bool { storage === other.storage }

    func position(of key: String) -> Int? { storage.position(of: key) }

    func value(at position: Int) -> ModuleJSONValue { storage.values[position] }

    func key(at position: Int) -> String { storage.keys[position] }

    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) || storage === Storage.empty {
            storage = storage.copy()
        }
    }

    subscript(key: String) -> ModuleJSONValue? {
        get {
            guard let position = storage.position(of: key) else { return nil }
            return storage.values[position]
        }
        set {
            if let newValue {
                set(key, newValue)
            } else {
                remove(key)
            }
        }
    }

     
    mutating func set(_ key: String, _ value: ModuleJSONValue) {
        makeUnique()
        if let position = storage.position(of: key) {
            storage.changing {
                if storage.run != 0 {
                    storage.strings &+= ModuleJSONLedger.stringBytes(value) &- ModuleJSONLedger.stringBytes(storage.values[position])
                }
                storage.values[position] = value
            }
        } else {
            storage.changing {
                if storage.run != 0 {
                    storage.strings &+= ModuleJSONLedger.stringBytes(key) &+ ModuleJSONLedger.stringBytes(value)
                }
                storage.keys.append(key)
                storage.values.append(value)
                if storage.index != nil {
                    storage.index?[ModuleJSONKey(string: key)] = storage.keys.count - 1
                } else if storage.keys.count > Self.indexThreshold {
                    storage.rebuildIndex()
                }
            }
        }
        storage.depth = max(storage.depth, Int32(clamping: value.depth + 1))
    }

     
    @discardableResult
    mutating func remove(_ key: String) -> ModuleJSONValue? {
        guard let position = storage.position(of: key) else { return nil }
        makeUnique()
        var removed = ModuleJSONValue.null
        storage.changing {
            removed = storage.values.remove(at: position)
            let key = storage.keys.remove(at: position)
            if storage.run != 0 {
                storage.strings &-= ModuleJSONLedger.stringBytes(key) &+ ModuleJSONLedger.stringBytes(removed)
            }
            if storage.index != nil { storage.rebuildIndex() }
        }
        return removed
    }

     
    mutating func remove(keys doomed: [String]) {
        var positions = Set<Int>()
        for key in doomed { if let position = storage.position(of: key) { positions.insert(position) } }
        guard !positions.isEmpty else { return }
        makeUnique()
        var keys: [String] = []
        var values: [ModuleJSONValue] = []
        keys.reserveCapacity(storage.keys.count - positions.count)
        values.reserveCapacity(storage.keys.count - positions.count)
        for position in storage.keys.indices where !positions.contains(position) {
            keys.append(storage.keys[position])
            values.append(storage.values[position])
        }
        storage.changing {
            storage.keys = keys
            storage.values = values
            storage.rebuildIndex()
            storage.recountStrings()
        }
    }
}

 

extension ModuleJSONValue: Equatable {
     
    static func == (a: ModuleJSONValue, b: ModuleJSONValue) -> Bool {
        if case .number(let x) = a, case .number(let y) = b { return ModuleJSONOrder.numbers(x, y) == 0 }
        return ModuleJSONOrder.compare(a, b) == 0
    }
}

 
 
 
 
 
 
enum ModuleJSONOrder {
    private enum Open {
        case arrays(ModuleJSONArray, ModuleJSONArray, next: Int)
        case objects(ModuleJSONObject, ModuleJSONObject, keys: [String], next: Int)
    }

    static func compare(_ a: ModuleJSONValue, _ b: ModuleJSONValue) -> Int {
        var open: [Open] = []
        var pending: (ModuleJSONValue, ModuleJSONValue)? = (a, b)
        while true {
            if let (x, y) = pending {
                pending = nil
                let rankX = x.kindRank, rankY = y.kindRank
                if rankX != rankY { return rankX < rankY ? -1 : 1 }
                switch (x, y) {
                case (.number(let p), .number(let q)):
                    if p.value.isNaN { return -1 }
                    if q.value.isNaN { return 1 }
                    let result = numbers(p, q)
                    if result != 0 { return result }
                case (.string(let p), .string(let q)):
                    let result = ModuleJSONBytes.compare(p, q)
                    if result != 0 { return result }
                case (.array(let p), .array(let q)):
                    if !p.isIdentical(to: q) { open.append(.arrays(p, q, next: 0)) }
                case (.object(let p), .object(let q)):
                    if !p.isIdentical(to: q) {
                        let keysP = p.sortedKeys, keysQ = q.sortedKeys
                        let shared = min(keysP.count, keysQ.count)
                        for index in 0..<shared {
                            let result = ModuleJSONBytes.compare(keysP[index], keysQ[index])
                            if result != 0 { return result }
                        }
                        if keysP.count != keysQ.count { return keysP.count < keysQ.count ? -1 : 1 }
                        open.append(.objects(p, q, keys: keysP, next: 0))
                    }
                default:
                    break
                }
            }
            guard let top = open.popLast() else { return 0 }
            switch top {
            case .arrays(let p, let q, let next):
                if next < min(p.count, q.count) {
                    open.append(.arrays(p, q, next: next + 1))
                    pending = (p[next], q[next])
                } else if p.count != q.count {
                    return p.count < q.count ? -1 : 1
                }
            case .objects(let p, let q, let keys, let next):
                if next < keys.count {
                    open.append(.objects(p, q, keys: keys, next: next + 1))
                    pending = (p[keys[next]] ?? .null, q[keys[next]] ?? .null)
                }
            }
        }
    }

     
     
    static func numbers(_ x: ModuleJSONNumber, _ y: ModuleJSONNumber) -> Int {
        if let lx = x.literal, let ly = y.literal, lx.canonical != nil || ly.canonical != nil,
           let dx = ModuleJSONDecimal(x), let dy = ModuleJSONDecimal(y) {
            return ModuleJSONDecimal.compare(dx, dy)
        }
        let a = x.value, b = y.value
        return a < b ? -1 : (a == b ? 0 : 1)
    }
}

 
 
struct ModuleJSONDecimal {
    var negative: Bool
    var digits: [UInt8]
    var exponent: Int

    init?(_ number: ModuleJSONNumber) {
        if let canonical = number.literal?.canonical {
            guard let parsed = ModuleJSONDecimal(canonical: canonical) else { return nil }
            self = parsed
        } else {
            guard number.value.isFinite else { return nil }
            let parts = ModuleJSONNumberText.shortestDigits(abs(number.value))
            negative = number.value.sign == .minus
            digits = parts.digits.isEmpty ? [UInt8(ascii: "0")] : parts.digits
            exponent = parts.decimalPoint - digits.count
            if parts.digits.isEmpty { exponent = 0 }
        }
    }

     
    init?(canonical text: String) {
        var bytes = Array(text.utf8)
        negative = bytes.first == UInt8(ascii: "-")
        if negative { bytes.removeFirst() }
        var exponentPart = 0
        if let e = bytes.firstIndex(where: { $0 == UInt8(ascii: "E") || $0 == UInt8(ascii: "e") }) {
            guard let parsed = Int(String(decoding: bytes[(e + 1)...], as: UTF8.self)) else { return nil }
            exponentPart = parsed
            bytes.removeSubrange(e...)
        }
        var coefficient: [UInt8] = []
        var fraction = 0
        var seenPoint = false
        for byte in bytes {
            if byte == UInt8(ascii: ".") { seenPoint = true; continue }
            guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
            coefficient.append(byte)
            if seenPoint { fraction += 1 }
        }
        while coefficient.count > 1, coefficient.first == UInt8(ascii: "0") { coefficient.removeFirst() }
        if coefficient.isEmpty { coefficient = [UInt8(ascii: "0")] }
        digits = coefficient
        exponent = exponentPart - fraction
    }

    var isZero: Bool { digits.allSatisfy { $0 == UInt8(ascii: "0") } }

    static func compare(_ a: ModuleJSONDecimal, _ b: ModuleJSONDecimal) -> Int {
        let zeroA = a.isZero, zeroB = b.isZero
        if zeroA && zeroB { return 0 }
        let signA = zeroA ? 0 : (a.negative ? -1 : 1)
        let signB = zeroB ? 0 : (b.negative ? -1 : 1)
        if signA != signB { return signA < signB ? -1 : 1 }
        let magnitude = compareMagnitude(a, b)
        return signA < 0 ? -magnitude : magnitude
    }

    private static func compareMagnitude(_ a: ModuleJSONDecimal, _ b: ModuleJSONDecimal) -> Int {
        var da = a.digits, db = b.digits
        while da.count > 1, da.last == UInt8(ascii: "0") { da.removeLast() }
        while db.count > 1, db.last == UInt8(ascii: "0") { db.removeLast() }
        let ea = a.exponent + (a.digits.count - da.count), eb = b.exponent + (b.digits.count - db.count)
        let adjustedA = ea + da.count - 1, adjustedB = eb + db.count - 1
        if adjustedA != adjustedB { return adjustedA < adjustedB ? -1 : 1 }
        let length = max(da.count, db.count)
        for index in 0..<length {
            let x = index < da.count ? da[index] : UInt8(ascii: "0")
            let y = index < db.count ? db[index] : UInt8(ascii: "0")
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}
#endif
