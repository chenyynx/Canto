import Foundation
import ClashClientKit

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public extension ConfigurationFieldCopy {
     
    struct CopyGroup: Equatable, Sendable {
        public struct Row: Equatable, Sendable {
            public let key: String
            public let title: [String: String]
            public let isToggle: Bool
        }

         
        public let place: String
        public let header: [String: String]
        public let footer: [String: String]
        public let rows: [Row]
    }

     
     
    func copyGroups(in catalog: ConfigurationFieldCatalog) -> [CopyGroup] {
        var kinds: [String: Set<ConfigurationFieldKind>] = [:]
        var children: [String: [String: String]] = [:]
        for field in catalog.fields {
            kinds[Self.sharedPath(field.path), default: []].insert(field.kind)
            let parts = ConfigurationFieldCatalog.catalogComponents(field.path)
            guard parts.count >= 2 else { continue }
            let parent = parts.dropLast().joined(separator: ".")
            for owner in [parent, Self.sharedPath(parent)] where children[owner]?[parts[parts.count - 1]] == nil {
                children[owner, default: [:]][parts[parts.count - 1]] = field.path
            }
        }
        let sharedKeys = Dictionary(grouping: records.keys.sorted(), by: Self.sharedPath)
        func words(_ path: String) -> Record? {
            record(forPath: path) ?? sharedKeys[Self.sharedPath(path)]?.first.flatMap { records[$0] }
        }
        func row(_ key: String, _ path: String) -> CopyGroup.Row {
            CopyGroup.Row(key: key, title: words(path)?.title ?? [:], isToggle: kinds[Self.sharedPath(path)] == [.toggle])
        }
        var groups: [CopyGroup] = []
        for path in layouts.keys.sorted() {
            let known = children[path] ?? [:]
            for section in layouts[path] ?? [] {
                let rows = section.keys.filter { $0 != "*" && known[$0] != nil }.map { row($0, path + "." + $0) }
                groups.append(CopyGroup(place: "\(path) §\(section.id)", header: section.title ?? [:],
                                        footer: section.footer ?? [:], rows: rows))
            }
        }
        var seen: Set<String> = []
        for field in catalog.fields where field.kind == .object {
            let shared = Self.sharedPath(field.path)
            guard layouts[field.path] == nil, layouts[shared] == nil, seen.insert(shared).inserted,
                  let kids = children[shared], !kids.isEmpty else { continue }
            let record = words(field.path)
            groups.append(CopyGroup(place: shared, header: record?.title ?? [:], footer: record?.summary ?? [:],
                                    rows: kids.keys.sorted().map { row($0, kids[$0] ?? $0) }))
        }
        return groups
    }

     
    func groupProblems(in catalog: ConfigurationFieldCatalog) -> [String] {
        var problems: Set<String> = []
        for group in copyGroups(in: catalog) {
            for language in Language.allCases {
                let lang = language.rawValue
                guard let header = group.header[lang], !header.isEmpty else { continue }
                let named = group.rows.compactMap { row -> (key: String, title: String, isToggle: Bool)? in
                    guard let title = row.title[lang], !title.isEmpty,
                          !ConfigurationFieldCatalog.switchKeys.contains(row.key) else { return nil }
                    return (row.key, title, row.isToggle)
                }
                for row in named {
                    if GroupWords.normalized(GroupWords.bare(row.title)) == GroupWords.normalized(header) {
                        problems.insert("\(group.place): \(lang): row \(row.key) says its header «\(header)»")
                    } else if !row.isToggle, GroupWords.setOff(row.title, header, language) {
                        problems.insert("\(group.place): \(lang): row \(row.key) «\(row.title)» repeats its header «\(header)»")
                    } else if named.count == 1, GroupWords.holdsWhole(GroupWords.bare(row.title), header) {
                        problems.insert("\(group.place): \(lang): its only row \(row.key) «\(row.title)» repeats its header «\(header)»")
                    }
                }
                if named.count >= 2 {
                    for phrase in GroupWords.phrases(of: header, language) where named.allSatisfy({ GroupWords.holds($0.title, phrase, language) }) {
                        problems.insert("\(group.place): \(lang): every row repeats «\(phrase)» from its header «\(header)»")
                    }
                }
                for token in GroupWords.tokens(header, allowing: "") {
                    let letters = token.filter(\.isLetter)
                    if letters.count >= 2, letters == letters.uppercased(), !GroupWords.capitalsAllowed.contains(token) {
                        problems.insert("\(group.place): \(lang): header «\(header)» spells \(token) in capitals")
                    }
                }
                if let footer = group.footer[lang], !footer.isEmpty,
                   GroupWords.novelty(footer, header, group.rows.map { $0.title[lang] ?? "" }, language) < (language == .en ? 3 : 4) {
                    problems.insert("\(group.place): \(lang): footer «\(footer)» only restates its header and rows")
                }
            }
        }
        return problems.sorted()
    }
}

 
enum GroupWords {
     
     
    static let capitalsAllowed: Set<String> = [
        "AEAD", "ALPN", "API", "ASN", "BBR", "CIDR", "CORS", "DNS", "ECH", "HTTP", "HTTPS", "IP", "JLS", "KCP", "LAN",
        "MMDB", "MTU", "NAT", "NTP", "QUIC", "REALITY", "SNI", "SOCKS", "SOCKS5", "SS", "SSH", "TCP", "TLS", "TUIC",
        "TUN", "UDP", "URL", "UUID", "VLESS", "VMESS", "VPN", "XHTTP", "XMUX",
    ]
    static let englishStopWords: Set<String> = [
        "a", "an", "and", "any", "are", "as", "at", "be", "by", "can", "each", "for", "from", "how", "in", "is", "it",
        "its", "more", "of", "on", "option", "options", "or", "other", "setting", "settings", "that", "the", "these",
        "this", "those", "to", "what", "when", "which", "with", "you", "all",
    ]
    static let chineseFunctionCharacters = Set("的和与或及了是在对把被让从里中等各这那些哪个之其也都就会可能要用做为以于所有没不每一将并而且即时后前跟它们")
     
     
    static let chineseGenericWords = ["设置", "設定", "选项", "選項", "配置", "参数", "參數"]

    static func isCJK(_ character: Character) -> Bool {
        character.unicodeScalars.contains { (0x3400...0x9FFF).contains($0.value) || (0xF900...0xFAFF).contains($0.value) }
    }

    private static func isASCIILetter(_ character: Character) -> Bool {
        character.isASCII && character.isLetter
    }

    private static func isASCIIAlphanumeric(_ character: Character) -> Bool {
        character.isASCII && (character.isLetter || character.isNumber)
    }

     
     
    static func tokens(_ text: String, allowing extra: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        for character in text {
            if current.isEmpty ? isASCIILetter(character) : (isASCIIAlphanumeric(character) || extra.contains(character)) {
                current.append(character)
            } else {
                if !current.isEmpty { tokens.append(current) }
                current = isASCIILetter(character) ? String(character) : ""
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

     
    static func heading(_ header: String, _ language: ConfigurationFieldCopy.Language) -> String {
        let trimmed = header.trimmingCharacters(in: .whitespaces)
        guard language != .en else { return trimmed }
        for word in chineseGenericWords where trimmed.hasSuffix(word) && trimmed.count > word.count {
            return String(trimmed.dropLast(word.count)).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }

     
    static func englishWords(_ text: String) -> [String] {
        tokens(text, allowing: "'-").compactMap { word in
            let lower = word.lowercased()
            guard !englishStopWords.contains(lower), word.count >= 2 else { return nil }
            return lower.count > 3 && lower.hasSuffix("s") && !lower.hasSuffix("ss") ? String(lower.dropLast()) : lower
        }
    }

    static func asciiWords(_ text: String) -> [String] {
        tokens(text, allowing: "-").map { $0.lowercased() }
    }

    static func normalized(_ text: String) -> String {
        text.lowercased().filter { !$0.isWhitespace && !"-_·/".contains($0) }
    }

     
    static func bare(_ title: String) -> String {
        var result = ""
        var closing: Character?
        for character in title {
            if let end = closing {
                if character == end { closing = nil }
            } else if character == "（" {
                closing = "）"
            } else if character == "(" {
                closing = ")"
            } else {
                result.append(character)
            }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }

     
     
    static func holdsWhole(_ title: String, _ header: String) -> Bool {
        let whole = Array(normalized(header)), text = Array(normalized(title))
        guard whole.count >= 2, whole != text, text.count >= whole.count else { return false }
        let checksStart = whole.first.map(isASCIIAlphanumeric) ?? false
        let checksEnd = whole.last.map(isASCIIAlphanumeric) ?? false
        for start in 0...(text.count - whole.count) where Array(text[start..<start + whole.count]) == whole {
            if checksStart, start > 0, isASCIIAlphanumeric(text[start - 1]) { continue }
            if checksEnd, start + whole.count < text.count, isASCIIAlphanumeric(text[start + whole.count]) { continue }
            return true
        }
        return false
    }

     
    static func phrases(of header: String, _ language: ConfigurationFieldCopy.Language) -> [String] {
        if language == .en { return Array(Set(englishWords(header).filter { $0.count >= 3 })).sorted() }
        let parts = heading(header, language).split { $0.isWhitespace || "与和及、&（）()/".contains($0) }.map(String.init)
        return Array(Set(parts.filter { $0.count >= 2 && !chineseGenericWords.contains($0) }.map { $0.lowercased() })).sorted()
    }

    static func holds(_ title: String, _ phrase: String, _ language: ConfigurationFieldCopy.Language) -> Bool {
        if language == .en { return englishWords(title).contains(phrase) }
        if phrase.allSatisfy({ isASCIIAlphanumeric($0) || $0 == "-" }) { return asciiWords(title).contains(phrase) }
        return title.lowercased().contains(phrase)
    }

     
     
     
    static func setOff(_ title: String, _ header: String, _ language: ConfigurationFieldCopy.Language) -> Bool {
        let text = bare(title)
        if language == .en {
            let head = englishWords(header), words = englishWords(text)
            guard !head.isEmpty, words.count > head.count else { return false }
            return Array(words.prefix(head.count)) == head || Array(words.suffix(head.count)) == head
        }
        let head = heading(header, language).lowercased(), lower = text.lowercased()
        guard !head.isEmpty, lower != head else { return false }
        return lower.hasPrefix(head + " ") || lower.hasSuffix(" " + head)
    }

     
    static func novelty(_ footer: String, _ header: String, _ rows: [String], _ language: ConfigurationFieldCopy.Language) -> Int {
        if language == .en {
            let known = Set(englishWords(header) + rows.flatMap(englishWords))
            return Set(englishWords(footer).filter { !known.contains($0) && $0.count >= 3 }).count
        }
        let knownCharacters = Set(header).union(rows.flatMap { Array($0) })
        let knownWords = Set(asciiWords(header) + rows.flatMap(asciiWords))
        let characters = footer.filter { isCJK($0) && !knownCharacters.contains($0) && !chineseFunctionCharacters.contains($0) }
        let words = Set(asciiWords(footer)).subtracting(knownWords)
        return characters.count + 2 * words.count
    }
}
