import Foundation

 
 
 
 
 
 
 
 
 
 
public enum ClashLogLineStyler {
    public enum Role: Equatable, Sendable {
         
        case dim
        case level(ClashActivityLogSeverity)
         
        case identity(hash: UInt32)
    }

    public struct Segment: Equatable, Sendable {
        public let range: Range<Int>    
        public let role: Role
        public init(range: Range<Int>, role: Role) { self.range = range; self.role = role }
    }

     
    public static func segments(of line: String, severity: ClashActivityLogSeverity?) -> [Segment] {
        var out: [Segment] = []
        let text = line as NSString
        let full = NSRange(location: 0, length: text.length)

         
         
         
        var cursor = 0
        var tokensSeen = 0
        while tokensSeen < 2, cursor < text.length {
            while cursor < text.length, text.character(at: cursor) == 0x20 { cursor += 1 }
            guard cursor < text.length else { break }
            var end = cursor
            while end < text.length, text.character(at: end) != 0x20 { end += 1 }
            let token = text.substring(with: NSRange(location: cursor, length: end - cursor))
            if let level = levelSeverity(token) {
                out.append(.init(range: cursor..<end, role: .level(level)))
                cursor = end
                break
            }
             
            guard tokensSeen == 0, looksLikeTimestamp(token) else { break }
            out.append(.init(range: cursor..<end, role: .dim))
            tokensSeen += 1
            cursor = end
        }

         
         
         
        let rest = NSRange(location: cursor, length: text.length - cursor)
         
         
        if let msg = text.range(of: "msg=\"", options: [], range: rest).nonEmpty,
           msg.location > cursor, text.character(at: msg.location - 1) == 0x20,
           text.range(of: "time=\"", options: [], range: rest).nonEmpty != nil {
            let frameEnd = msg.location + msg.length
            out.append(.init(range: cursor..<frameEnd, role: .dim))
            cursor = frameEnd
            if text.length > 0, text.character(at: text.length - 1) == 0x22   {
                out.append(.init(range: (text.length - 1)..<text.length, role: .dim))
            }
        }

         
        let messageEnd = out.contains { $0.range.upperBound == text.length && $0.range.count == 1 }
            ? text.length - 1 : text.length
         
         
         
         
         
         
        var bodyStart = cursor
        while bodyStart < messageEnd, text.character(at: bodyStart) == 0x20 { bodyStart += 1 }
        if bodyStart < messageEnd {
            if text.character(at: bodyStart) == 0x5B   {
                let window = NSRange(location: bodyStart, length: min(32, messageEnd - bodyStart))
                if let close = text.range(of: "]", options: [], range: window).nonEmpty {
                    let end = close.location + 1
                    let tag = text.substring(with: NSRange(location: bodyStart, length: end - bodyStart))
                    out.append(.init(range: bodyStart..<end, role: .identity(hash: fnv1a(tag))))
                }
            } else {
                let window = NSRange(location: bodyStart, length: min(25, messageEnd - bodyStart))
                if let colon = text.range(of: ":", options: [], range: window).nonEmpty {
                    let end = colon.location + 1
                    let prefix = text.substring(with: NSRange(location: bodyStart, length: colon.location - bodyStart))
                    let followed = end == messageEnd || text.character(at: end) == 0x20
                    let words = prefix.split(separator: " ", omittingEmptySubsequences: true).count
                    let clean = !prefix.contains { "=\"(/".contains($0) }
                    if followed, !prefix.isEmpty, words <= 3, clean {
                        out.append(.init(range: bodyStart..<end, role: .identity(hash: fnv1a(prefix + ":"))))
                    }
                }
            }
        }
         
        let body = NSRange(location: cursor, length: max(0, messageEnd - cursor))
        if let arrow = text.range(of: " --> ", options: [], range: body).nonEmpty {
            let start = arrow.location + arrow.length
            var end = start
            while end < messageEnd, text.character(at: end) != 0x20 { end += 1 }
            if end > start {
                let host = text.substring(with: NSRange(location: start, length: end - start))
                out.append(.init(range: start..<end, role: .identity(hash: fnv1a(host))))
            }
        }
         
         
         
         
        if let start = wordEnd("using", in: text, within: body), start < messageEnd {
            let node = text.substring(with: NSRange(location: start, length: messageEnd - start))
            out.append(.init(range: start..<messageEnd, role: .identity(hash: fnv1a(node))))
        }
        _ = full
        return out.sorted { $0.range.lowerBound < $1.range.lowerBound }
    }

     
     
    public static func identityColor(hash: UInt32) -> (red: Double, green: Double, blue: Double) {
        var color = Int(UInt8(truncatingIfNeeded: hash)) % 215
        var row = color / 36
        var column = color % 36
        let r = Double(row * 51), g = Double(column / 6 * 51), b = Double(column % 6 * 51)
        let luma = 0.2126 * r + 0.7152 * g + 0.0722 * b
        if luma < 60 {
            row = 5 - row
            column = 35 - column
            color = row * 36 + column
        }
        return (Double(row * 51) / 255.0, Double(column / 6 * 51) / 255.0, Double(column % 6 * 51) / 255.0)
    }

    static func fnv1a(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 { hash ^= UInt32(byte); hash = hash &* 16_777_619 }
        return hash
    }

     
     
     
    private static func wordEnd(_ word: String, in text: NSString, within range: NSRange) -> Int? {
        var search = range
        while search.length > 0, let hit = text.range(of: word, options: [], range: search).nonEmpty {
            let after = hit.location + hit.length
            let spacedBefore = hit.location > 0 && text.character(at: hit.location - 1) == 0x20
            let spacedAfter = after < text.length && text.character(at: after) == 0x20
            if spacedBefore, spacedAfter { return after + 1 }
            let next = after
            guard next < range.location + range.length else { return nil }
            search = NSRange(location: next, length: range.location + range.length - next)
        }
        return nil
    }

    private static func levelSeverity(_ token: String) -> ClashActivityLogSeverity? {
        switch token.uppercased() {
        case "DEBUG", "TRACE": .debug
        case "INFO": .info
        case "WARN", "WARNING": .warning
        case "ERROR", "FATAL", "PANIC": .error
        default: nil
        }
    }

    private static func looksLikeTimestamp(_ token: String) -> Bool {
         
        guard let first = token.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) else { return false }
        let allowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ":-TZ.+"))
        return token.unicodeScalars.allSatisfy(allowed.contains) && token.contains(":") || token.contains("-")
    }
}

private extension NSRange {
    var nonEmpty: NSRange? { location == NSNotFound ? nil : self }
}
