import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
enum LargeConfigurationDisplay {
     
    enum Told: Equatable {
        case nodes(Int?)
        case rules(Int?)
        case groups(Int?)
        case entries(Int?)
    }

     
     
    nonisolated(unsafe) static var toldFromBytes = 1 << 20

     
     
     
    static func text(of text: String, nodeCount: Int? = nil, ruleCount: Int? = nil, containerPath: String?,
                     telling: (Told) -> String) -> String {
        var copy = text
        let shown = copy.withUTF8 { bytes in
            form(bytes, nodeCount: nodeCount, ruleCount: ruleCount, telling: telling)
        }
        return relative(shown, containerPath: containerPath)
    }

     
     
    static func text(ofFileAt url: URL, containerPath: String?, telling: (Told) -> String) -> String? {
        guard let data = try? Data(contentsOf: url, options: [.alwaysMapped]) else { return nil }
        let shown = data.withUnsafeBytes { raw in
            form(raw.bindMemory(to: UInt8.self), nodeCount: nil, ruleCount: nil, telling: telling)
        }
        return relative(shown, containerPath: containerPath)
    }

    private static func form(_ bytes: UnsafeBufferPointer<UInt8>, nodeCount: Int?, ruleCount: Int?,
                             telling: (Told) -> String) -> String {
        guard let lines = TopLevelYAMLSections.keyLines(inBytes: bytes) else {
             
             
            let end = min(bytes.count, toldFromBytes)
            var shown = withoutPublicationKeys(String(decoding: UnsafeBufferPointer(rebasing: bytes[..<end]), as: UTF8.self),
                                               telling: telling)
            if end < bytes.count { shown += "\n# " + telling(.entries(nil)) + "\n" }
            return shown
        }
        var out = ""
        out.reserveCapacity(min(bytes.count, 4 * toldFromBytes))
        let head = lines.first?.offset ?? bytes.count
        out += String(decoding: UnsafeBufferPointer(rebasing: bytes[..<head]), as: UTF8.self)
        for (index, line) in lines.enumerated() {
            let end = index + 1 < lines.count ? lines[index + 1].offset : bytes.count
            let section = UnsafeBufferPointer(rebasing: bytes[line.offset..<end])
             
             
            if line.key.hasPrefix(publicationKeyPrefix), line.key != ConfigTransforms.nodeLibraryKey,
               line.key != ConfigTransforms.ruleIndexKey { continue }
            let told: (key: String, what: Told)?
            switch line.key {
            case ConfigTransforms.nodeLibraryKey: told = ("proxies", .nodes(nodeCount))
            case ConfigTransforms.ruleIndexKey: told = ("rules", .rules(ruleCount))
            case "proxies": told = ("proxies", .nodes(entries(section)))
            case "rules": told = ("rules", .rules(entries(section)))
            default:
                guard section.count >= toldFromBytes else { told = nil; break }
                told = (line.key, line.key == "proxy-groups" ? .groups(entries(section)) : .entries(entries(section)))
            }
            if let told {
                out += told.key + ": # " + telling(told.what) + "\n"
            } else {
                out += withoutPublicationKeys(String(decoding: section, as: UTF8.self), telling: telling)
                if end == bytes.count, !out.hasSuffix("\n") { out += "\n" }
            }
        }
        return out
    }

     
     
     
    @_optimize(speed)
    private static func entries(_ section: UnsafeBufferPointer<UInt8>) -> Int? {
        var start = nextNewline(section, from: 0) + 1
        var indent: Int?
        var listed = false
        var count = 0
        while start < section.count {
            let end = nextNewline(section, from: start)
            var first = start
            while first < end, section[first] == UInt8(ascii: " ") { first += 1 }
            defer { start = end + 1 }
            guard first < end, section[first] != UInt8(ascii: "#"), section[first] != UInt8(ascii: "\r") else { continue }
            let depth = first - start
            if indent == nil {
                indent = depth
                listed = section[first] == UInt8(ascii: "-")
            }
            guard depth == indent else { continue }
            if listed ? section[first] == UInt8(ascii: "-") : true { count += 1 }
        }
        return indent == nil ? nil : count
    }

     
    static let publicationKeyPrefix = "x-clash-"

     
     
     
     
     
     
     
     
    static func withoutPublicationKeys(_ section: String, telling: (Told) -> String) -> String {
        guard section.contains(publicationKeyPrefix) else { return section }
        var lines = section.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var out: [String] = []
        var index = 0
        while index < lines.count {
            guard let (column, key) = keyAt(lines[index]), key.hasPrefix(publicationKeyPrefix) else {
                out.append(lines[index])
                index += 1
                continue
            }
             
             
            var end = index + 1
            while end < lines.count, belongs(lines, end, toKeyAt: column) { end += 1 }
            let lead = String(lines[index].prefix(column))
            let value = ([String(lines[index].dropFirst(column + key.count + 1))] + lines[(index + 1)..<end])
                .joined(separator: "\n")
            switch key {
            case "x-clash-members": out.append(lead + "proxies" + ": # " + telling(.nodes(memberCount(value))))
            case "x-clash-member-group": out.append(lead + "proxies" + ": # " + telling(.nodes(nil)))
            default:
                 
                if lead.contains("-"), end < lines.count, let next = keyAt(lines[end]), next.column == column {
                    lines[end] = lead + lines[end].dropFirst(column)
                }
            }
            index = end
        }
        return out.joined(separator: "\n")
    }

     
     
    private static func keyAt(_ line: String) -> (column: Int, key: String)? {
        let characters = Array(line)
        var at = 0
        while at < characters.count, characters[at] == " " { at += 1 }
        if at + 1 < characters.count, characters[at] == "-", characters[at + 1] == " " {
            at += 2
            while at < characters.count, characters[at] == " " { at += 1 }
        }
        var end = at
        while end < characters.count, characters[end].isLetter || characters[end].isNumber
                || characters[end] == "-" || characters[end] == "_" { end += 1 }
        guard end > at, end < characters.count, characters[end] == ":",
              end + 1 == characters.count || characters[end + 1] == " " else { return nil }
        return (at, String(characters[at..<end]))
    }

     
    private static func belongs(_ lines: [String], _ index: Int, toKeyAt column: Int) -> Bool {
        var probe = index
         
        while probe < lines.count, lines[probe].allSatisfy({ $0 == " " || $0 == "\r" }) { probe += 1 }
        guard probe < lines.count else { return false }
        let line = lines[probe]
        let indent = line.prefix { $0 == " " }.count
        if indent > column { return true }
        return indent == column && (line.dropFirst(indent).hasPrefix("- ") || line.dropFirst(indent) == "-")
    }

     
     
    static func memberCount(_ value: String) -> Int? {
        let runPattern = #""?from"?\s*:\s*(\d+)\s*,?\s*"?to"?\s*:\s*(\d+)"#
        guard let expression = try? NSRegularExpression(pattern: runPattern) else { return nil }
        let runs = expression.matches(in: value, range: NSRange(value.startIndex..., in: value))
        let spans = runs.compactMap { match -> Int? in
            guard let from = Range(match.range(at: 1), in: value).flatMap({ Int(value[$0]) }),
                  let to = Range(match.range(at: 2), in: value).flatMap({ Int(value[$0]) }) else { return nil }
            return max(0, to - from)
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        var items = 0
        if trimmed.hasPrefix("[") {
             
            var depth = 0, quote: Character?, any = false
            for character in trimmed {
                if let open = quote { if character == open { quote = nil }; continue }
                switch character {
                case "\"", "'": quote = character
                case "[", "{": depth += 1
                case "]", "}": depth -= 1
                case "," where depth == 1: items += 1
                default: if depth >= 1, character != " " { any = true }
                }
            }
            if any { items += 1 }
        } else {
            let dashes = value.split(separator: "\n").map { line -> (Int, Bool) in
                let indent = line.prefix { $0 == " " }.count
                let rest = line.dropFirst(indent)
                return (indent, rest.hasPrefix("- ") || rest == "-")
            }.filter(\.1)
            let itemIndent = dashes.map(\.0).min()
            items = dashes.filter { $0.0 == itemIndent }.count
        }
        guard items > 0 else { return nil }
        return items - spans.count + spans.reduce(0, +)
    }

     
    private static func relative(_ text: String, containerPath: String?) -> String {
        guard let containerPath, !containerPath.isEmpty else { return text }
        let path = containerPath.hasSuffix("/") ? String(containerPath.dropLast()) : containerPath
         
        var spellings = [path]
        if path.hasPrefix("/private/") { spellings.append(String(path.dropFirst("/private".count))) }
        else if path.hasPrefix("/var/") { spellings.append("/private" + path) }
        var shown = text
        for spelling in spellings.sorted(by: { $0.count > $1.count }) {
            shown = shown.replacingOccurrences(of: spelling + "/", with: "")
        }
        return shown
    }
}
