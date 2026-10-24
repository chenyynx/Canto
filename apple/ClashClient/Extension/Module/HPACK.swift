#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 

 
enum HPACKIndexing: Equatable, Sendable {
     
    case incremental
     
    case withoutIndexing
     
     
    case neverIndexed

     
     
     
     
     
    static func preferred(name: String, value: String) -> HPACKIndexing {
        switch name {
        case #"authorization"#, #"proxy-authorization"#:
            return .neverIndexed
        case #"cookie"#:
            return HPACKOctets.count(value) < 20 ? .neverIndexed : .incremental
        case #":path"#, #"age"#, #"content-length"#, #"etag"#, #"if-modified-since"#, #"if-none-match"#, #"location"#,
             #"set-cookie"#:
            return .withoutIndexing
        default:
            return .incremental
        }
    }
}

 
struct HPACKField: Equatable, Sendable {
    var name: String
    var value: String
    var indexing: HPACKIndexing

    init(_ name: String, _ value: String, indexing: HPACKIndexing = .incremental) {
        self.name = name
        self.value = value
        self.indexing = indexing
    }

     
     
    var size: Int { HPACKOctets.count(name) + HPACKOctets.count(value) + 32 }
}

 
 
 
enum HPACKOctets {
    static func bytes(_ text: String) -> [UInt8] {
        if text.utf8.allSatisfy({ $0 < 0x80 }) { return Array(text.utf8) }
        if text.unicodeScalars.allSatisfy({ $0.value <= 0xFF }) { return text.unicodeScalars.map { UInt8($0.value) } }
        return Array(text.utf8)
    }

     
    static func count(_ text: String) -> Int {
        var scalars = 0
        for scalar in text.unicodeScalars {
            if scalar.value > 0xFF { return text.utf8.count }
            scalars += 1
        }
        return scalars
    }

    static func text(_ bytes: ArraySlice<UInt8>) -> String {
        if bytes.allSatisfy({ $0 < 0x80 }) { return String(decoding: bytes, as: UTF8.self) }
        var scalars = String.UnicodeScalarView()
        for byte in bytes { scalars.append(Unicode.Scalar(byte)) }
        return String(scalars)
    }

     
     
     
    static func same(_ a: String, _ b: String) -> Bool {
        a.utf8.elementsEqual(b.utf8)
    }
}

 
 
enum HPACKInteger {
     
    static func encode(_ value: Int, prefixBits: Int, flags: UInt8 = 0, into out: inout [UInt8]) {
        let value = max(0, value)
        let limit = (1 << prefixBits) - 1
        guard value >= limit else { return out.append(flags | UInt8(value)) }
        out.append(flags | UInt8(limit))
        var rest = value - limit
        while rest >= 128 {
            out.append(UInt8(rest % 128) | 0x80)
            rest /= 128
        }
        out.append(UInt8(rest))
    }

     
     
     
     
    static func decode(_ bytes: [UInt8], at index: inout Int, prefixBits: Int) throws -> Int {
        guard index < bytes.count else { throw HPACKError.truncated }
        let limit = (1 << prefixBits) - 1
        var value = Int(bytes[index]) & limit
        index += 1
        guard value == limit else { return value }
        var shift = 0
        while true {
            guard index < bytes.count else { throw HPACKError.truncated }
            let byte = bytes[index]
            index += 1
            value += Int(byte & 0x7F) << shift
            guard value <= Int(Int32.max) else { throw HPACKError.integerOverflow }
            if byte & 0x80 == 0 { return value }
            shift += 7
            guard shift <= 28 else { throw HPACKError.integerOverflow }
        }
    }
}

 
enum HPACKStaticTable {
    static let entries: [(name: String, value: String)] = [
        (#":authority"#, #""#),  
        (#":method"#, #"GET"#),  
        (#":method"#, #"POST"#),  
        (#":path"#, #"/"#),  
        (#":path"#, #"/index.html"#),  
        (#":scheme"#, #"http"#),  
        (#":scheme"#, #"https"#),  
        (#":status"#, #"200"#),  
        (#":status"#, #"204"#),  
        (#":status"#, #"206"#),  
        (#":status"#, #"304"#),  
        (#":status"#, #"400"#),  
        (#":status"#, #"404"#),  
        (#":status"#, #"500"#),  
        (#"accept-charset"#, #""#),  
        (#"accept-encoding"#, #"gzip, deflate"#),  
        (#"accept-language"#, #""#),  
        (#"accept-ranges"#, #""#),  
        (#"accept"#, #""#),  
        (#"access-control-allow-origin"#, #""#),  
        (#"age"#, #""#),  
        (#"allow"#, #""#),  
        (#"authorization"#, #""#),  
        (#"cache-control"#, #""#),  
        (#"content-disposition"#, #""#),  
        (#"content-encoding"#, #""#),  
        (#"content-language"#, #""#),  
        (#"content-length"#, #""#),  
        (#"content-location"#, #""#),  
        (#"content-range"#, #""#),  
        (#"content-type"#, #""#),  
        (#"cookie"#, #""#),  
        (#"date"#, #""#),  
        (#"etag"#, #""#),  
        (#"expect"#, #""#),  
        (#"expires"#, #""#),  
        (#"from"#, #""#),  
        (#"host"#, #""#),  
        (#"if-match"#, #""#),  
        (#"if-modified-since"#, #""#),  
        (#"if-none-match"#, #""#),  
        (#"if-range"#, #""#),  
        (#"if-unmodified-since"#, #""#),  
        (#"last-modified"#, #""#),  
        (#"link"#, #""#),  
        (#"location"#, #""#),  
        (#"max-forwards"#, #""#),  
        (#"proxy-authenticate"#, #""#),  
        (#"proxy-authorization"#, #""#),  
        (#"range"#, #""#),  
        (#"referer"#, #""#),  
        (#"refresh"#, #""#),  
        (#"retry-after"#, #""#),  
        (#"server"#, #""#),  
        (#"set-cookie"#, #""#),  
        (#"strict-transport-security"#, #""#),  
        (#"transfer-encoding"#, #""#),  
        (#"user-agent"#, #""#),  
        (#"vary"#, #""#),  
        (#"via"#, #""#),  
        (#"www-authenticate"#, #""#),  
    ]

     
    private static let firstIndex: [String: Int] = {
        var first: [String: Int] = [:]
        for (offset, entry) in entries.enumerated() where first[entry.name] == nil { first[entry.name] = offset + 1 }
        return first
    }()

     
    private static let tableEntries = entries.map { HPACKTableEntry(name: $0.name, value: $0.value) }

     
    static func entry(_ index: Int) -> HPACKTableEntry? {
        guard index >= 1, index <= tableEntries.count else { return nil }
        return tableEntries[index - 1]
    }

     
    static func index(name: String, value: String) -> (field: Int?, name: Int?) {
        guard let first = firstIndex[name], HPACKOctets.same(entries[first - 1].name, name) else { return (nil, nil) }
        var index = first
        while index <= entries.count, HPACKOctets.same(entries[index - 1].name, name) {
            if HPACKOctets.same(entries[index - 1].value, value) { return (index, first) }
            index += 1
        }
        return (nil, first)
    }
}

 
 
 
 
struct HPACKTableEntry: Equatable, Sendable {
    let name: String
    let value: String
    let nameOctets: Int
    let valueOctets: Int

     
    var size: Int { nameOctets + valueOctets + 32 }

    init(name: String, value: String) {
        self.init(name: name, value: value, nameOctets: HPACKOctets.count(name), valueOctets: HPACKOctets.count(value))
    }

     
     
    init(name: String, value: String, nameOctets: Int, valueOctets: Int) {
        self.name = name
        self.value = value
        self.nameOctets = nameOctets
        self.valueOctets = valueOctets
    }
}

 
struct HPACKDynamicTable: Equatable, Sendable {
    private(set) var entries: [HPACKTableEntry] = []
    private(set) var size = 0
    private(set) var maximumSize: Int

    init(maximumSize: Int) {
        self.maximumSize = max(0, maximumSize)
    }

     
    func entry(_ index: Int) -> HPACKTableEntry? {
        guard index >= 1, index <= entries.count else { return nil }
        return entries[index - 1]
    }

     
    mutating func resize(_ maximumSize: Int) {
        self.maximumSize = max(0, maximumSize)
        evict(toFit: 0)
    }

     
     
     
    mutating func makeRoom(for size: Int) -> Bool {
        guard size <= maximumSize else {
            entries.removeAll()
            self.size = 0
            return false
        }
        evict(toFit: size)
        return true
    }

     
    mutating func add(_ entry: HPACKTableEntry) {
        entries.insert(entry, at: 0)
        size += entry.size
    }

    private mutating func evict(toFit extra: Int) {
        while size + extra > maximumSize, let oldest = entries.popLast() {
            size -= oldest.size
        }
    }
}

 
 
 
 
 
 
 
 
struct HTTP2HeaderLimits: Equatable, Sendable {
     
    var maximumBlockBytes: Int
    var maximumListSize: Int
    var maximumFields: Int
     
     
    var maximumStringLength: Int
     
     
     
    var maximumContinuations: Int

    static let request = HTTP2HeaderLimits(maximumBlockBytes: 36 * 1024, maximumListSize: 36 * 1024, maximumFields: 128,
                                                  maximumStringLength: 16 * 1024, maximumContinuations: 32)
     
     
     
     
     
    static let response = HTTP2HeaderLimits(maximumBlockBytes: 256 * 1024, maximumListSize: 256 * 1024, maximumFields: 256,
                                                   maximumStringLength: 64 * 1024, maximumContinuations: 32)
}

enum HPACKError: Error, Equatable, Sendable {
     
    case truncated
    case integerOverflow
     
    case invalidIndex(Int)
     
    case huffmanPaddingTooLong
    case huffmanPaddingNotOnes
    case huffmanEOS
     
    case sizeUpdateNotFirst
     
    case sizeUpdateTooLarge
     
     
    case sizeUpdateMissing
     
    case stringTooLong
     
    case headerListTooLarge

     
     
     
     
    var leavesTableInStep: Bool { self == .stringTooLong || self == .headerListTooLarge }
}

 
 
struct HPACKEncoder: Sendable {
    enum Huffman: Equatable, Sendable {
        case never
        case always
         
        case whenShorter
    }

     
     
     
    static let tableSizeCeiling = 4096

    private(set) var table: HPACKDynamicTable
    let huffman: Huffman
     
     
    private var pendingUpdate: (smallest: Int, final: Int)?

     
     
    init(maximumTableSize: Int = 4096, huffman: Huffman = .whenShorter) {
        table = HPACKDynamicTable(maximumSize: maximumTableSize)
        self.huffman = huffman
    }

     
     
     
    mutating func setPeerMaximumTableSize(_ size: Int) {
        let chosen = min(max(0, size), Self.tableSizeCeiling)
        guard chosen != table.maximumSize || pendingUpdate != nil else { return }
        pendingUpdate = (min(pendingUpdate?.smallest ?? chosen, chosen), chosen)
        table.resize(chosen)
    }

    mutating func encode(_ fields: [HPACKField]) -> Data {
        var out: [UInt8] = []
        if let update = pendingUpdate {
            if update.smallest < update.final {
                HPACKInteger.encode(update.smallest, prefixBits: 5, flags: 0x20, into: &out)
            }
            HPACKInteger.encode(update.final, prefixBits: 5, flags: 0x20, into: &out)
            pendingUpdate = nil
        }
        for field in fields { encode(field, into: &out) }
        return Data(out)
    }

    private mutating func encode(_ field: HPACKField, into out: inout [UInt8]) {
        let fixed = HPACKStaticTable.index(name: field.name, value: field.value)
         
        if field.indexing != .neverIndexed, let index = fixed.field ?? dynamicIndex(of: field) {
            return HPACKInteger.encode(index, prefixBits: 7, flags: 0x80, into: &out)
        }
        let name = HPACKOctets.bytes(field.name)
        let value = HPACKOctets.bytes(field.value)
        let size = name.count + value.count + 32
        var indexing = field.indexing
         
         
        if indexing == .incremental, size > table.maximumSize * 3 / 4 { indexing = .withoutIndexing }
        let nameIndex = fixed.name ?? dynamicIndex(ofName: field.name) ?? 0
        switch indexing {
        case .incremental: HPACKInteger.encode(nameIndex, prefixBits: 6, flags: 0x40, into: &out)
        case .withoutIndexing: HPACKInteger.encode(nameIndex, prefixBits: 4, flags: 0x00, into: &out)
        case .neverIndexed: HPACKInteger.encode(nameIndex, prefixBits: 4, flags: 0x10, into: &out)
        }
        if nameIndex == 0 { string(name, into: &out) }
        string(value, into: &out)
        if indexing == .incremental, table.makeRoom(for: size) {
            table.add(HPACKTableEntry(name: field.name, value: field.value, nameOctets: name.count, valueOctets: value.count))
        }
    }

    private func dynamicIndex(of field: HPACKField) -> Int? {
        table.entries.firstIndex {
            HPACKOctets.same($0.name, field.name) && HPACKOctets.same($0.value, field.value)
        }.map { $0 + HPACKStaticTable.entries.count + 1 }
    }

    private func dynamicIndex(ofName name: String) -> Int? {
        table.entries.firstIndex { HPACKOctets.same($0.name, name) }.map { $0 + HPACKStaticTable.entries.count + 1 }
    }

     
    private func string(_ bytes: [UInt8], into out: inout [UInt8]) {
        let coded: Bool
        switch huffman {
        case .never: coded = false
        case .always: coded = true
        case .whenShorter: coded = HPACKHuffman.encodedLength(bytes) < bytes.count
        }
        if coded {
            HPACKInteger.encode(HPACKHuffman.encodedLength(bytes), prefixBits: 7, flags: 0x80, into: &out)
            HPACKHuffman.encode(bytes, into: &out)
        } else {
            HPACKInteger.encode(bytes.count, prefixBits: 7, into: &out)
            out.append(contentsOf: bytes)
        }
    }
}

 
 
 
 
 
 
 
 
 
struct HPACKDecoder: Sendable {
    private(set) var table: HPACKDynamicTable
     
     
    private(set) var maximumTableSizeLimit: Int
    var limits: HTTP2HeaderLimits
     
     
    private var requiredUpdate: Int?
     
     
    private(set) var heldOctetsPeak = 0

    init(maximumTableSize: Int = 4096, limits: HTTP2HeaderLimits = .request) {
        table = HPACKDynamicTable(maximumSize: maximumTableSize)
        maximumTableSizeLimit = max(0, maximumTableSize)
        self.limits = limits
    }

     
     
    mutating func setMaximumTableSizeLimit(_ size: Int) {
        let size = max(0, size)
        maximumTableSizeLimit = size
        if size < table.maximumSize { requiredUpdate = min(requiredUpdate ?? size, size) }
    }

    mutating func decode(_ block: Data) throws -> [HPACKField] {
        try decode([UInt8](block))
    }

     
     
     
    mutating func decode(_ block: [UInt8]) throws -> [HPACKField] {
        heldOctetsPeak = 0
        var fields: [HPACKField] = []
        var listSize = 0
        var held = 0
        var overflow: HPACKError?
        var index = 0
        var leading = true
        var updatedEnough = requiredUpdate == nil
        while index < block.count {
            let first = block[index]
            if first & 0xE0 == 0x20 {
                 
                guard leading else { throw HPACKError.sizeUpdateNotFirst }
                let size = try HPACKInteger.decode(block, at: &index, prefixBits: 5)
                guard size <= maximumTableSizeLimit else { throw HPACKError.sizeUpdateTooLarge }
                table.resize(size)
                if let required = requiredUpdate, size <= required { updatedEnough = true }
                continue
            }
            if leading {
                guard updatedEnough else { throw HPACKError.sizeUpdateMissing }
                leading = false
            }

            let indexing: HPACKIndexing
            let name: Source
            let value: Source
            if first & 0x80 != 0 {
                 
                 
                 
                let entry = try lookup(try HPACKInteger.decode(block, at: &index, prefixBits: 7))
                indexing = .incremental
                name = .text(entry.name, entry.nameOctets)
                value = .text(entry.value, entry.valueOctets)
            } else {
                let prefix: Int
                if first & 0xC0 == 0x40 {
                    indexing = .incremental
                    prefix = 6
                } else if first & 0xF0 == 0x10 {
                    indexing = .neverIndexed
                    prefix = 4
                } else {
                    indexing = .withoutIndexing
                    prefix = 4
                }
                let nameIndex = try HPACKInteger.decode(block, at: &index, prefixBits: prefix)
                if nameIndex == 0 {
                    name = try Self.literal(block, &index)
                } else {
                     
                    let entry = try lookup(nameIndex)
                    name = .text(entry.name, entry.nameOctets)
                }
                value = try Self.literal(block, &index)
            }

            let nameCount = try name.count(in: block)
            let valueCount = try value.count(in: block)
            let size = nameCount + valueCount + 32
            if overflow == nil {
                if nameCount > limits.maximumStringLength || valueCount > limits.maximumStringLength {
                    overflow = .stringTooLong
                } else if fields.count >= limits.maximumFields || listSize + size > limits.maximumListSize {
                    overflow = .headerListTooLarge
                }
                if overflow != nil {
                    fields = []
                    listSize = 0
                    held = 0
                }
            }
            let keep = overflow == nil
            let insert = first & 0xC0 == 0x40
            let fits = insert && table.makeRoom(for: size)
            if keep || fits {
                let nameText = try name.text(in: block)
                let valueText = try value.text(in: block)
                heldOctetsPeak = max(heldOctetsPeak, held + nameCount + valueCount)
                if fits {
                    table.add(HPACKTableEntry(name: nameText, value: valueText, nameOctets: nameCount, valueOctets: valueCount))
                }
                if keep {
                    fields.append(HPACKField(nameText, valueText, indexing: indexing))
                    listSize += size
                    held += nameCount + valueCount
                }
            }
        }
        guard updatedEnough else { throw HPACKError.sizeUpdateMissing }
        requiredUpdate = nil
        if let overflow { throw overflow }
        return fields
    }

    private func lookup(_ index: Int) throws -> HPACKTableEntry {
        if let entry = HPACKStaticTable.entry(index) { return entry }
        if index > HPACKStaticTable.entries.count,
           let entry = table.entry(index - HPACKStaticTable.entries.count) {
            return entry
        }
        throw HPACKError.invalidIndex(index)
    }

     
     
    private enum Source {
        case text(String, Int)
        case literal(huffman: Bool, range: Range<Int>)

         
         
        func count(in block: [UInt8]) throws -> Int {
            switch self {
            case .text(_, let count): return count
            case .literal(false, let range): return range.count
            case .literal(true, let range): return try HPACKHuffman.decodedLength(block[range])
            }
        }

        func text(in block: [UInt8]) throws -> String {
            switch self {
            case .text(let text, _): return text
            case .literal(false, let range): return HPACKOctets.text(block[range])
            case .literal(true, let range): return HPACKOctets.text(try HPACKHuffman.decode(block[range])[...])
            }
        }
    }

     
     
    private static func literal(_ block: [UInt8], _ index: inout Int) throws -> Source {
        guard index < block.count else { throw HPACKError.truncated }
        let huffman = block[index] & 0x80 != 0
        let length = try HPACKInteger.decode(block, at: &index, prefixBits: 7)
        guard length <= block.count - index else { throw HPACKError.truncated }
        defer { index += length }
        return .literal(huffman: huffman, range: index..<(index + length))
    }
}
#endif
