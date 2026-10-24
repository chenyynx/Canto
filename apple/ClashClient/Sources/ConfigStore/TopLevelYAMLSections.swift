import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
enum TopLevelYAMLSections {
     
    struct Cut {
         
        let rest: String
         
         
         
         
         
        let sections: [(key: String, text: Substring)]
         
         
        let following: [String: [String]]
         
         
         
        var writtenKeys: Set<String>? = nil

         
         
         
         
         
         
         
        private func keysWritten(after position: Int) -> [String] {
            let followers = following[sections[position].key] ?? []
            let later = sections[(position + 1)...].map(\.key)
            var keys: [String] = []
            for index in 0...followers.count {
                let tail = Array(followers[index...])
                keys += later.filter { (following[$0] ?? []) == tail }
                if index < followers.count { keys.append(followers[index]) }
            }
            return keys
        }

         
         
         
         
        func splicing(into restYAML: String) -> String? {
            var result = restYAML
             
             
            if result.trimmingCharacters(in: .whitespacesAndNewlines) == "{}" { result = "" }
             
             
            guard let written = TopLevelYAMLSections.keyLines(of: result) else { return nil }
            if sections.contains(where: { section in written.contains { $0.key == section.key } }) {
                return nil
            }
             
             
            result.reserveCapacity(result.utf8.count + sections.reduce(0) { $0 + $1.text.utf8.count } + sections.count)
             
             
            for (position, section) in sections.enumerated().reversed() {
                let lines = TopLevelYAMLSections.keyLines(of: result)
                let at = lines.flatMap { lines in
                    keysWritten(after: position).lazy.compactMap { key in lines.first { $0.key == key }?.offset }.first
                }
                let before = at ?? writtenKeys.flatMap { writtenKeys in
                     
                    lines?.first(where: { !writtenKeys.contains($0.key) })?.offset
                }
                if let before {
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    var newline = ""
                    if section.text.utf8.last != UInt8(ascii: "\n") {
                        guard section.key == "rules", RuleLines(section.text) != nil else { return nil }
                        newline = section.text.contains("\r\n") ? "\r\n" : "\n"
                    }
                    result.insert(contentsOf: section.text, at: result.utf8.index(result.utf8.startIndex, offsetBy: before))
                    if !newline.isEmpty {
                        let after = before + section.text.utf8.count
                        result.insert(contentsOf: newline, at: result.utf8.index(result.utf8.startIndex, offsetBy: after))
                    }
                } else {
                    if !result.isEmpty, result.utf8.last != UInt8(ascii: "\n") { result += "\n" }
                    result += section.text
                }
            }
            return result
        }
    }

     
     
    static func cutting(_ keys: Set<String>, from yaml: String) -> Cut? {
        var text = yaml
         
         
         
        guard let found = text.withUTF8({ cut(keys, $0) }) else { return nil }
         
        let utf8 = text.utf8
        let sections = found.ranges.map { key, range -> (key: String, text: Substring) in
            let start = utf8.index(utf8.startIndex, offsetBy: range.lowerBound)
            let end = utf8.index(start, offsetBy: range.count)
            return (key, Substring(utf8[start..<end]))
        }
        return Cut(rest: found.rest, sections: sections, following: found.following, writtenKeys: found.writtenKeys)
    }

     
     
    @_optimize(speed)
    private static func cut(_ keys: Set<String>, _ bytes: UnsafeBufferPointer<UInt8>)
        -> (rest: String, ranges: [(key: String, range: Range<Int>)], following: [String: [String]], writtenKeys: Set<String>)? {
        guard let lines = keyLines(bytes) else { return nil }
        let present = lines.filter { keys.contains($0.key) }
        guard !present.isEmpty else { return nil }
        var ranges: [(key: String, range: Range<Int>)] = []
        var following: [String: [String]] = [:]
        var rest: [UInt8] = []
        var cursor = 0
         
        rest.reserveCapacity(min(bytes.count, 32 << 20))
        for (index, line) in lines.enumerated() where keys.contains(line.key) {
            let end = index + 1 < lines.count ? lines[index + 1].offset : bytes.count
            let section = bytes[line.offset..<end]
             
             
             
             
             
            guard (line.key == "rules" && RuleLines.isOneRuleALine(UnsafeBufferPointer(rebasing: section)))
                    || !mentionsAnchorOrAlias(section) else { return nil }
            rest.append(contentsOf: bytes[cursor..<line.offset])
            cursor = end
             
             
             
            ranges.append((line.key, line.offset..<end))
            following[line.key] = lines[(index + 1)...].map(\.key).filter { !keys.contains($0) }
        }
        rest.append(contentsOf: bytes[cursor...])
        return (String(decoding: rest, as: UTF8.self), ranges, following, Set(lines.map(\.key)))
    }

     
     
     
    struct PlacedCut {
         
        let rest: String
         
         
        let ranges: [(key: String, range: Range<Int>)]
        let following: [String: [String]]
        let writtenKeys: Set<String>

         
        func cut(writing texts: [String: String]) -> Cut {
            Cut(rest: rest, sections: ranges.map { (key: $0.key, text: Substring(texts[$0.key] ?? "")) },
                following: following, writtenKeys: writtenKeys)
        }
    }

     
    static func cutting(_ keys: Set<String>, inBytes bytes: UnsafeBufferPointer<UInt8>) -> PlacedCut? {
        guard let found = cut(keys, bytes) else { return nil }
        return PlacedCut(rest: found.rest, ranges: found.ranges, following: found.following, writtenKeys: found.writtenKeys)
    }

     
     
     
     
    static func section(_ key: String, inBytes bytes: UnsafeBufferPointer<UInt8>) -> String? {
        guard let lines = keyLines(bytes) else { return nil }
        guard let index = lines.firstIndex(where: { $0.key == key }) else { return "" }
        let end = index + 1 < lines.count ? lines[index + 1].offset : bytes.count
        let section = bytes[lines[index].offset..<end]
        guard !mentionsAnchorOrAlias(section) else { return nil }
        return String(decoding: section, as: UTF8.self)
    }

     
     
     
     
     
     
     
    static func sections(_ keys: Set<String>, inBytes bytes: UnsafeBufferPointer<UInt8>)
        -> (texts: [String: String], refused: Set<String>, ranges: [String: Range<Int>])? {
        guard let lines = keyLines(bytes) else { return nil }
        var texts: [String: String] = [:]
        var refused = Set<String>()
        var ranges: [String: Range<Int>] = [:]
        for (index, line) in lines.enumerated() {
            let end = index + 1 < lines.count ? lines[index + 1].offset : bytes.count
            ranges[line.key] = line.offset..<end
            guard keys.contains(line.key) else { continue }
            let section = bytes[line.offset..<end]
            if mentionsAnchorOrAlias(section) {
                refused.insert(line.key)
            } else {
                texts[line.key] = String(decoding: UnsafeBufferPointer(rebasing: section), as: UTF8.self)
            }
        }
        return (texts, refused, ranges)
    }

     
     
     
     
    static func sectionRange(_ key: String, inBytes bytes: UnsafeBufferPointer<UInt8>) -> Range<Int>? {
        guard let lines = keyLines(bytes), let index = lines.firstIndex(where: { $0.key == key }) else { return nil }
        let end = index + 1 < lines.count ? lines[index + 1].offset : bytes.count
        return lines[index].offset..<end
    }

    struct KeyLine: Equatable {
        let key: String
         
        let offset: Int
    }

     
    static func keyLines(inBytes bytes: UnsafeBufferPointer<UInt8>) -> [KeyLine]? {
        keyLines(bytes)
    }

     
     
    static func keyLines(of yaml: String) -> [KeyLine]? {
        var text = yaml
        return text.withUTF8 { keyLines($0) }
    }

    @_optimize(speed)
    private static func keyLines(_ bytes: UnsafeBufferPointer<UInt8>) -> [KeyLine]? {
        var lines: [KeyLine] = []
        var seen = Set<String>()
        var sawDocumentStart = false
        var start = 0
        let count = bytes.count
        while start < count {
            let end = nextNewline(bytes, from: start)
            defer { start = end + 1 }
            let first = bytes[start]
            switch first {
            case UInt8(ascii: "\n"), UInt8(ascii: "\r"), UInt8(ascii: " "), UInt8(ascii: "#"):
                 
                continue
            case UInt8(ascii: "\t"), UInt8(ascii: "%"), UInt8(ascii: "."):
                return nil
            case UInt8(ascii: "-"):
                if isMarker(bytes, start, end, "---") {
                     
                     
                    guard lines.isEmpty, !sawDocumentStart, isBareMarker(bytes, start, end) else { return nil }
                    sawDocumentStart = true
                    continue
                }
                 
                 
                guard !lines.isEmpty else { return nil }
                continue
            default:
                guard let key = plainKey(bytes, start, end), key != "<<", seen.insert(key).inserted else { return nil }
                lines.append(KeyLine(key: key, offset: start))
            }
        }
        return lines
    }

     
    private static func isMarker(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int, _ marker: String) -> Bool {
        let mark = Array(marker.utf8)
        guard end - start >= mark.count, Array(bytes[start..<(start + mark.count)]) == mark else { return false }
        let after = start + mark.count
        return after == end || [UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r")].contains(bytes[after])
    }

    private static func isBareMarker(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> Bool {
        var index = start + 3
        while index < end, [UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r")].contains(bytes[index]) {
            index += 1
        }
        return index == end || bytes[index] == UInt8(ascii: "#")
    }

     
    private static func plainKey(_ bytes: UnsafeBufferPointer<UInt8>, _ start: Int, _ end: Int) -> String? {
        func isWord(_ byte: UInt8, first: Bool) -> Bool {
            switch byte {
            case UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"),
                 UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "_"):
                return true
            case UInt8(ascii: "-"), UInt8(ascii: "."):
                return !first
            default:
                return false
            }
        }
        var index = start
        while index < end, isWord(bytes[index], first: index == start) { index += 1 }
        guard index > start, index < end, bytes[index] == UInt8(ascii: ":") else { return nil }
        let after = index + 1
        guard after == end || [UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\r")].contains(bytes[after]) else {
            return nil
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

     
     
     
     
    @_optimize(speed)
    static func mentionsAnchorOrAlias(inBytes section: UnsafeBufferPointer<UInt8>) -> Bool {
        guard let base = section.baseAddress, !section.isEmpty else { return false }
        let count = section.count
        func opens(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x2C || byte == 0x5B || byte == 0x7B || byte == 0x3A || byte == 0x2D
        }
        func closes(_ byte: UInt8) -> Bool {
            byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D || byte == 0x2C || byte == 0x5D || byte == 0x7D
        }
        for mark in [UInt8(ascii: "&"), UInt8(ascii: "*")] {
            var from = 0
            while from < count, let hit = memchr(base + from, Int32(mark), count - from) {
                let index = UnsafeRawPointer(base).distance(to: UnsafeRawPointer(hit))
                let before = index == 0 ? UInt8(ascii: "\n") : base[index - 1]
                let next = index + 1 < count ? base[index + 1] : UInt8(ascii: "\n")
                if opens(before), !closes(next) { return true }
                from = index + 1
            }
        }
        return false
    }

     
     
     
     
    @_optimize(speed)
    private static func mentionsAnchorOrAlias(_ section: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
        let opens: Set<UInt8> = [UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: ","),
                                 UInt8(ascii: "["), UInt8(ascii: "{"), UInt8(ascii: ":"), UInt8(ascii: "-")]
        let closes: Set<UInt8> = [UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"),
                                  UInt8(ascii: ","), UInt8(ascii: "]"), UInt8(ascii: "}")]
        var index = section.startIndex
        while index < section.endIndex {
            let byte = section[index]
            if byte == UInt8(ascii: "&") || byte == UInt8(ascii: "*") {
                let before = index == section.startIndex ? UInt8(ascii: "\n") : section[index - 1]
                let next = index + 1 < section.endIndex ? section[index + 1] : UInt8(ascii: "\n")
                if opens.contains(before), !closes.contains(next) { return true }
            }
            index += 1
        }
        return false
    }
}

 

 
 
@inline(__always)
func nextNewline(_ bytes: UnsafeBufferPointer<UInt8>, from start: Int) -> Int {
    guard start < bytes.count, let base = bytes.baseAddress else { return bytes.count }
    guard let found = memchr(base + start, 0x0A, bytes.count - start) else { return bytes.count }
    return base.distance(to: found.assumingMemoryBound(to: UInt8.self))
}

extension TopLevelYAMLSections.Cut {
     
     
    func replacingSection(_ key: String, with text: some StringProtocol) -> TopLevelYAMLSections.Cut {
        let replacement = Substring(text)
        return TopLevelYAMLSections.Cut(rest: rest,
                                        sections: sections.map { $0.key == key ? (key: key, text: replacement) : $0 },
                                        following: following, writtenKeys: writtenKeys)
    }

     
    func section(_ key: String) -> String? {
        sections.first { $0.key == key }.map { String($0.text) }
    }

     
     
    func sectionText(_ key: String) -> Substring? {
        sections.first { $0.key == key }?.text
    }
}

 
 
 
 
 
 
 
 
 
struct RuleLines {
     
     
    let text: Substring
     
    var count: Int { layout.count }
     
    private let layout: Layout

     
     
     
    struct Layout: Equatable {
         
        let count: Int
         
         
        let firstItem: Int
        let afterLastItem: Int
         
         
        let firstPrefix: String
        let lastPrefix: String
        let newline: String
        let lastLineEndsWithNewline: Bool
    }

    private struct Reading {
        var count = 0
        var first: (start: Int, prefix: String)?
        var last: (start: Int, next: Int, prefix: String, newline: Bool)?
        var lastPrefixRange: Range<Int>?
        var crlf = false
    }

    init?(_ section: String) {
        self.init(Substring(section))
    }

    init?(_ section: Substring) {
        var copy = section
         
        guard let layout = copy.withUTF8({ Self.layout($0) }) else { return nil }
        self.text = section
        self.layout = layout
    }

     
     
    static func layout(_ bytes: UnsafeBufferPointer<UInt8>) -> Layout? {
        guard let reading = read(bytes), let first = reading.first, let last = reading.last else { return nil }
        return Layout(count: reading.count, firstItem: first.start, afterLastItem: last.next,
                      firstPrefix: first.prefix, lastPrefix: last.prefix, newline: reading.crlf ? "\r\n" : "\n",
                      lastLineEndsWithNewline: last.newline)
    }

     
    static func isOneRuleALine(_ bytes: UnsafeBufferPointer<UInt8>) -> Bool {
        read(bytes) != nil
    }

    @_optimize(speed)
    private static func read(_ bytes: UnsafeBufferPointer<UInt8>) -> Reading? {
        var reading = Reading()
        var start = 0
        var isKey = true
        var indent: Int?
        while start < bytes.count {
            let end = nextNewline(bytes, from: start)
            let next = end < bytes.count ? end + 1 : end
            var contentEnd = end
            if contentEnd > start, bytes[contentEnd - 1] == UInt8(ascii: "\r") { contentEnd -= 1 }
            defer { start = next }
            let content = bytes[start..<contentEnd]
            if isKey {
                isKey = false
                guard isBareKeyLine(content) else { return nil }
                reading.crlf = contentEnd < end
                continue
            }
            var index = content.startIndex
            while index < content.endIndex, content[index] == UInt8(ascii: " ") { index += 1 }
            if index == content.endIndex || content[index] == UInt8(ascii: "#") { continue }
             
            let column = index - content.startIndex
            guard content[index] == UInt8(ascii: "-"), index + 1 < content.endIndex,
                  content[index + 1] == UInt8(ascii: " "), indent == nil || indent == column else { return nil }
            indent = column
            var scalar = index + 2
            while scalar < content.endIndex, content[scalar] == UInt8(ascii: " ") { scalar += 1 }
            guard isWholeScalar(content[scalar..<content.endIndex]) else { return nil }
             
             
            if reading.first == nil {
                reading.first = (start, String(decoding: content[content.startIndex..<scalar], as: UTF8.self))
            }
            reading.last = (start, next, "", next > end || end < bytes.count)
            reading.lastPrefixRange = content.startIndex..<scalar
            reading.count += 1
        }
        guard reading.count > 0, let range = reading.lastPrefixRange, reading.last != nil else { return nil }
        reading.last!.prefix = String(decoding: bytes[range], as: UTF8.self)
        return reading
    }

     
    private static func isBareKeyLine(_ line: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
        let key = Array("rules:".utf8)
        guard line.count >= key.count, Array(line.prefix(key.count)) == key else { return false }
        let rest = line.dropFirst(key.count)
        guard let first = rest.firstIndex(where: { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\t") }) else { return true }
        return rest[first] == UInt8(ascii: "#") && first > rest.startIndex
    }

     
     
     
     
    @_optimize(speed)
    private static func isWholeScalar(_ scalar: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
        guard let first = scalar.first else { return false }
        func onlyComment(_ tail: Slice<UnsafeBufferPointer<UInt8>>) -> Bool {
            guard let next = tail.firstIndex(where: { $0 != UInt8(ascii: " ") && $0 != UInt8(ascii: "\t") }) else {
                return true
            }
            return tail[next] == UInt8(ascii: "#") && next > tail.startIndex
        }
        switch first {
        case UInt8(ascii: "\""):
            var index = scalar.startIndex + 1
            while index < scalar.endIndex {
                switch scalar[index] {
                case UInt8(ascii: "\\"): index += 2
                case UInt8(ascii: "\""): return onlyComment(scalar[(index + 1)...])
                default: index += 1
                }
            }
            return false
        case UInt8(ascii: "'"):
            var index = scalar.startIndex + 1
            while index < scalar.endIndex {
                if scalar[index] == UInt8(ascii: "'") {
                    if index + 1 < scalar.endIndex, scalar[index + 1] == UInt8(ascii: "'") { index += 2; continue }
                    return onlyComment(scalar[(index + 1)...])
                }
                index += 1
            }
            return false
        default:
            let isWordStart = (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(first)
                || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(first)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(first)
            guard isWordStart, let base = scalar.base.baseAddress else { return false }
             
             
             
            var value = scalar.endIndex
            var from = scalar.startIndex
            while from < scalar.endIndex, let hit = memchr(base + from, Int32(UInt8(ascii: "#")), scalar.endIndex - from) {
                let index = base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                if index > scalar.startIndex, scalar[index - 1] == UInt8(ascii: " ") || scalar[index - 1] == UInt8(ascii: "\t") {
                    value = index
                    break
                }
                from = index + 1
            }
            from = scalar.startIndex
            while from < value, let hit = memchr(base + from, Int32(UInt8(ascii: ":")), value - from) {
                let index = base.distance(to: hit.assumingMemoryBound(to: UInt8.self))
                let after = index + 1
                if after == scalar.endIndex || scalar[after] == UInt8(ascii: " ") || scalar[after] == UInt8(ascii: "\t") {
                    return false
                }
                from = after
            }
            return value > scalar.startIndex
        }
    }

     
     
    func appending(_ rules: [String]) -> String {
        writing(layout.pieces(ofSectionOf: text.utf8.count, prepending: [], appending: rules))
    }

     
     
    func prepending(_ rules: [String]) -> String {
        writing(layout.pieces(ofSectionOf: text.utf8.count, prepending: rules, appending: []))
    }

     
     
    private func writing(_ pieces: [TextPiece]) -> String {
        if pieces == [.bytes(0..<text.utf8.count)] { return String(text) }
        var out = ""
        out.reserveCapacity(pieces.reduce(0) { total, piece in
            switch piece {
            case .bytes(let range): return total + range.count
            case .text(let added): return total + added.utf8.count
            }
        })
        for piece in pieces {
            switch piece {
            case .bytes(let range): out.append(contentsOf: self.piece(range))
            case .text(let added): out += added
            }
        }
        return out
    }

     
    private func piece(_ range: some RangeExpression<Int>) -> Substring {
        let bounds = range.relative(to: 0..<text.utf8.count)
        let utf8 = text.utf8
        let start = utf8.index(utf8.startIndex, offsetBy: bounds.lowerBound)
        return Substring(utf8[start..<utf8.index(start, offsetBy: bounds.count)])
    }

     
     
     
    func rules(whoseLinesHold needles: [String]) throws -> [String] {
        try indexedRules(whoseLinesHold: needles).map(\.rule)
    }

     
    func indexedRules(whoseLinesHold needles: [String]) throws -> [(index: Int, rule: String)] {
        var copy = text
        return try copy.withUTF8 { try Self.indexedRules(in: $0, laidOut: layout, whoseLinesHold: needles) }
    }

     
     
    static func rules(in bytes: UnsafeBufferPointer<UInt8>, laidOut layout: Layout,
                      whoseLinesHold needles: [String]) throws -> [String] {
        try indexedRules(in: bytes, laidOut: layout, whoseLinesHold: needles).map(\.rule)
    }

    private static func indexedRules(in bytes: UnsafeBufferPointer<UInt8>, laidOut layout: Layout,
                                     whoseLinesHold needles: [String]) throws -> [(index: Int, rule: String)] {
        let folded = needles.map { Array($0.lowercased().utf8) }
        let matched = itemLines(bytes, from: layout.firstItem, to: layout.afterLastItem, holding: folded)
        guard !matched.isEmpty else { return [] }
         
         
         
        let json = try ConfigTransforms.yamlToJSON("rules:" + "\n" + matched.map(\.line).joined(separator: "\n") + "\n")
        guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let list = root["rules"] as? [Any], list.count == matched.count else { return [] }
        return zip(matched, list).compactMap { entry, value in (value as? String).map { (entry.index, $0) } }
    }

     
     
    @_optimize(speed)
    private static func itemLines(_ bytes: UnsafeBufferPointer<UInt8>, from: Int, to: Int,
                                  holding folded: [[UInt8]]) -> [(index: Int, line: String)] {
        var lines: [(index: Int, line: String)] = []
        var ordinal = 0
        var start = from
        while start < to {
            let end = nextNewline(bytes, from: start)
            let line = bytes[start..<end]
            var first = line.startIndex
            while first < line.endIndex, line[first] == UInt8(ascii: " ") { first += 1 }
             
            if first < line.endIndex, line[first] == UInt8(ascii: "-") {
                if folded.allSatisfy({ holds(line, $0) }) {
                    var content = String(decoding: line, as: UTF8.self)
                    if content.hasSuffix("\r") { content.removeLast() }
                    lines.append((ordinal, content))
                }
                ordinal += 1
            }
            start = end + 1
        }
        return lines
    }

    @_optimize(speed)
    private static func holds(_ line: UnsafeBufferPointer<UInt8>.SubSequence, _ needle: [UInt8]) -> Bool {
        guard !needle.isEmpty else { return true }
        guard line.count >= needle.count else { return false }
        var index = line.startIndex
        while index <= line.endIndex - needle.count {
            var offset = 0
            while offset < needle.count {
                var byte = line[index + offset]
                if (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte) { byte += 32 }
                if byte != needle[offset] { break }
                offset += 1
            }
            if offset == needle.count { return true }
            index += 1
        }
        return false
    }

     
     
    static func written(_ rule: String) -> String {
        if isPlainSafe(rule) { return rule }
        let data = (try? JSONSerialization.data(withJSONObject: [rule], options: [.withoutEscapingSlashes])) ?? Data("[\"\"]".utf8)
        let array = String(decoding: data, as: UTF8.self)
        return String(array.dropFirst().dropLast())
    }

     
     
     
    private static func isPlainSafe(_ rule: String) -> Bool {
        guard let first = rule.unicodeScalars.first, first.isASCII,
              CharacterSet.alphanumerics.contains(first), rule.contains(","),
              !rule.contains(": "), !rule.contains(" #"), !rule.hasSuffix(":"),
              rule.trimmingCharacters(in: .whitespaces) == rule,
              !rule.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F }) else { return false }
        return true
    }
}

 
 
 
enum TextPiece: Equatable {
    case bytes(Range<Int>)
    case text(String)
}

extension RuleLines.Layout {
     
     
     
     
     
    func pieces(ofSectionOf count: Int, prepending prepended: [String], appending appended: [String]) -> [TextPiece] {
        var pieces: [TextPiece] = []
        var at = 0
        if !prepended.isEmpty {
            pieces.append(.bytes(0..<firstItem))
            pieces.append(.text(prepended.map { firstPrefix + RuleLines.written($0) + newline }.joined()))
            at = firstItem
        }
        if !appended.isEmpty {
            pieces.append(.bytes(at..<afterLastItem))
            var added = (lastLineEndsWithNewline ? "" : newline)
                + appended.map { lastPrefix + RuleLines.written($0) + newline }.joined()
            if !lastLineEndsWithNewline, afterLastItem == count {
                 
                 
                added.removeLast(newline.count)
            }
            pieces.append(.text(added))
            at = afterLastItem
        }
        pieces.append(.bytes(at..<count))
        return pieces.filter {
            switch $0 {
            case .bytes(let range): return !range.isEmpty
            case .text(let text): return !text.isEmpty
            }
        }
    }
}
