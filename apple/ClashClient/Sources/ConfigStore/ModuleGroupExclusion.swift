import ClashClientKit
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleGroupExclusion {
     
     
    static let wholeDocumentLimit = 4 * 1024 * 1024

    private static let key = "proxy-groups"

    static func apply(to yaml: String, engineName: String) throws -> String {
         
        guard !engineName.contains("`") else { throw ModuleInjectionError.unsupportedSectionLayout(key) }
         
         
         
         
        guard mentionsIncludeAll(yaml) else { return yaml }

        let mark = "\u{FEFF}"
        let hasMark = yaml.hasPrefix(mark)
        let body = hasMark ? String(yaml.dropFirst()) : yaml
        let filter = "^" + escapedForTheKernelsPatterns(engineName) + "$"

        let result: String?
        if let keys = TopLevelYAMLSections.keyLines(of: body) {
            guard let index = keys.firstIndex(where: { $0.key == key }) else { return yaml }
             
             
            let start = keys[index].offset
            var text = body
            let end = index + 1 < keys.count ? keys[index + 1].offset : text.utf8.count
            let section = text.withUTF8 { String(decoding: UnsafeBufferPointer(rebasing: $0[start..<end]), as: UTF8.self) }
             
            if TopLevelYAMLSections.cutting([key], from: section) != nil {
                result = try rewriteSection(section, filter: filter).map { replaced in
                    text.withUTF8 { bytes in
                        var out: [UInt8] = []
                        out.reserveCapacity(bytes.count - (end - start) + replaced.utf8.count)
                        out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[..<start]))
                        out.append(contentsOf: replaced.utf8)
                        out.append(contentsOf: UnsafeBufferPointer(rebasing: bytes[end...]))
                        return String(decoding: out, as: UTF8.self)
                    }
                }
            } else {
                result = try rewriteWholeDocument(body, filter: filter)
            }
        } else {
            result = try rewriteWholeDocument(body, filter: filter)
        }
        guard let result else { return yaml }
        return (hasMark ? mark : "") + result
    }

     

     
     
     
     
     
    private static func rewriteSection(_ section: String, filter: String) throws -> String? {
         
         
         
        let lines = section.utf8.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .map { String(decoding: $0, as: UTF8.self) }
        let crlf = lines.first?.hasSuffix("\r") ?? false
        var pieces: [String] = []    
        var itemIndent: Int?
        var current: [String] = []
        var headerOK = false
        for (index, line) in lines.enumerated() {
            if index == 0 {
                let value = line.dropFirst(key.count + 1).trimmingCharacters(in: .whitespacesAndNewlines)
                headerOK = value.isEmpty || value.hasPrefix("#")
                pieces.append(line)
                continue
            }
            let indent = line.prefix { $0 == " " }.count
            let rest = line.dropFirst(indent)
            let opensItem = rest.hasPrefix("-") && (rest.count == 1 || rest.dropFirst().first == " " || rest.dropFirst().first == "\t" || rest.dropFirst().first == "\r")
            if opensItem, itemIndent == nil || itemIndent == indent {
                itemIndent = indent
                if !current.isEmpty {
                     
                     
                     
                     
                    var tail = current.count
                    while tail > 1, isMarginComment(current[tail - 1], margin: indent) { tail -= 1 }
                    pieces.append(current[..<tail].joined(separator: "\n"))
                    if tail < current.count { pieces.append(current[tail...].joined(separator: "\n")) }
                    current = []
                }
            } else if itemIndent == nil, !rest.isEmpty, !rest.hasPrefix("#"), !rest.hasPrefix("\r") {
                headerOK = false    
            }
            current.append(line)
        }
        if !current.isEmpty { pieces.append(current.joined(separator: "\n")) }
        guard headerOK, let indent = itemIndent else {
            return try rewriteWholeSection(section, filter: filter)
        }

        var changed = false
        var out: [String] = [pieces[0]]
        for item in pieces.dropFirst() {
            guard mentionsIncludeAll(item) else { out.append(item); continue }
            let converted = try OrderedJSON.parse(read(key + ":\n" + item))
            guard case .array(let groups)? = converted.topLevelValue(key), groups.count == 1,
                  let edited = try edit(groups[0], filter: filter) else { out.append(item); continue }
            let written = try ConfigTransforms.jsonToYAML(converted.settingTopLevel(key, to: .array([edited])).serialized())
            let item = reindented(afterHeaderOf: written, to: indent)
             
             
            out.append(crlf ? item.split(separator: "\n", omittingEmptySubsequences: false).joined(separator: "\r\n") + "\r" : item)
            changed = true
        }
        guard changed else { return nil }
        var text = out.joined(separator: "\n")
         
        if text.utf8.last != UInt8(ascii: "\n") { text += text.utf8.last == UInt8(ascii: "\r") || !crlf ? "\n" : "\r\n" }
        return text
    }

     
     
    private static func isMarginComment(_ line: String, margin: Int) -> Bool {
        let indent = line.prefix { $0 == " " }.count
        return indent <= margin && line.dropFirst(indent).hasPrefix("#")
    }

     
    private static func reindented(afterHeaderOf written: String, to indent: Int) -> String {
        var lines = written.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        lines.removeFirst()
        while lines.last == "" { lines.removeLast() }
        let margin = lines.first.map { $0.prefix { $0 == " " }.count } ?? 0
        return lines.map { line in
            line.isEmpty ? line : String(repeating: " ", count: indent) + line.dropFirst(min(margin, line.prefix { $0 == " " }.count))
        }.joined(separator: "\n")
    }

    private static func rewriteWholeSection(_ section: String, filter: String) throws -> String? {
        let root = try OrderedJSON.parse(read(section))
        guard case .array(let groups)? = root.topLevelValue(key) else { return nil }
        guard let adjusted = try edit(groups, filter: filter) else { return nil }
        var text = try ConfigTransforms.jsonToYAML(root.settingTopLevel(key, to: .array(adjusted)).serialized())
        if text.utf8.last != UInt8(ascii: "\n") { text += "\n" }
        return text
    }

     

     
     
     
    private static func rewriteWholeDocument(_ body: String, filter: String) throws -> String? {
        guard body.utf8.count <= wholeDocumentLimit else { throw ModuleInjectionError.unsupportedSectionLayout(key) }
        let root = try OrderedJSON.parse(read(body))
        guard case .array(let groups)? = root.topLevelValue(key), let adjusted = try edit(groups, filter: filter) else { return nil }
        return try ConfigTransforms.jsonToYAML(root.settingTopLevel(key, to: .array(adjusted)).serialized())
    }

     
     
     
     
     
     
     
    private static func read(_ yaml: String) throws -> String {
        try ConfigTransforms.yamlToJSON(yaml, omitting: [])
    }

     

     
     
    private static func edit(_ groups: [OrderedJSON], filter: String) throws -> [OrderedJSON]? {
        var changed = false
        let adjusted = try groups.map { group -> OrderedJSON in
            if let edited = try edit(group, filter: filter) { changed = true; return edited }
            return group
        }
        return changed ? adjusted : nil
    }

    private static func edit(_ group: OrderedJSON, filter: String) throws -> OrderedJSON? {
        guard case .object(var fields) = group, takesEveryProxy(fields) else { return nil }
         
        guard let index = fields.firstIndex(where: { $0.key.lowercased() == "exclude-filter" }) else {
            fields.append((key: "exclude-filter", value: .string(filter)))
            return .object(fields)
        }
        switch fields[index].value {
        case .string(let existing) where existing.isEmpty:
            fields[index].value = .string(filter)
        case .string(let existing):
             
            if existing.split(separator: "`", omittingEmptySubsequences: false).contains(Substring(filter)) { return nil }
            fields[index].value = .string(existing + "`" + filter)
        case .scalar("null"):
            fields[index].value = .string(filter)
        case .scalar(let token):
            fields[index].value = .string(token + "`" + filter)
        default:
             
            throw ModuleInjectionError.unsupportedSectionLayout(key)
        }
        return .object(fields)
    }

     
     
     
     
     
     
     
     
    static func mentionsIncludeAll(_ text: String) -> Bool {
        var text = text
        let needle = Array("include-all".utf8)
        let providers = Array("-providers".utf8)
        return text.withUTF8 { bytes in
            guard bytes.count >= needle.count else { return false }
            let last = bytes.count - needle.count
            func lower(_ byte: UInt8) -> UInt8 { byte >= 0x41 && byte <= 0x5A ? byte + 0x20 : byte }
            func matches(_ word: [UInt8], at start: Int) -> Bool {
                guard start + word.count <= bytes.count else { return false }
                var j = 0
                while j < word.count, lower(bytes[start + j]) == word[j] { j += 1 }
                return j == word.count
            }
            var atLineStart = true
            var commentLine = false
            var i = 0
            while i <= last {
                let byte = bytes[i]
                if byte == UInt8(ascii: "\n") {
                    atLineStart = true
                    commentLine = false
                } else if atLineStart, byte != UInt8(ascii: " "), byte != UInt8(ascii: "\t") {
                    atLineStart = false
                    commentLine = byte == UInt8(ascii: "#")
                }
                if !commentLine, lower(byte) == needle[0], matches(needle, at: i),
                   !matches(providers, at: i + needle.count) {
                    return true
                }
                i += 1
            }
            return false
        }
    }

     
     
     
     
     
     
    static func takesEveryProxy(_ fields: [(key: String, value: OrderedJSON)]) -> Bool {
        fields.contains { field in
            let name = field.key.lowercased()
            guard name == "include-all" || name == "include-all-proxies" else { return false }
            switch field.value {
            case .scalar(let token): return token == "true" || (Int(token).map { $0 != 0 } ?? false)
            case .string(let text): return ["true", "yes", "on"].contains(text.lowercased())
            default: return false
            }
        }
    }

     
     
    private static func escapedForTheKernelsPatterns(_ name: String) -> String {
        var out = ""
        for character in name {
            if "\\^$.|?*+()[]{}".contains(character) { out.append("\\") }
            out.append(character)
        }
        return out
    }
}
