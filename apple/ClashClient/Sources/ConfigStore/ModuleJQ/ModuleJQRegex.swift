#if os(iOS) || os(macOS)
import Foundation

 


extension ModuleJQMachine {
     
     
     
     
     
     
     
     
     
     
     
     
     
    func match(_ input: Value, _ regex: Value, _ modifiers: Value, _ test: Value) throws -> Value {
         
         
         
        try autoreleasepool { try matchUnpooled(input, regex, modifiers, test) }
    }

    private func matchUnpooled(_ input: Value, _ regex: Value, _ modifiers: Value, _ test: Value) throws -> Value {
        guard case .string(let subject) = input else { throw typeError(input, "cannot be matched, as it is not a string") }
        guard case .string(let pattern) = regex else { throw typeError(regex, "is not a string") }
        let testing = test == .bool(true)
        var global = false, skipEmpty = false
        var options: NSRegularExpression.Options = [.useUnixLineSeparators]
        switch modifiers {
        case .null:
            break
        case .string(let flags):
            for flag in flags.unicodeScalars {
                switch flag {
                case "g": global = true
                case "i": options.insert(.caseInsensitive)
                case "x": options.insert(.allowCommentsAndWhitespace)
                case "n": skipEmpty = true
                case "s", "l": break
                case "p": options.insert(.dotMatchesLineSeparators)
                default: throw fail("\(flags) is not a valid modifier string")
                }
            }
        default:
            throw typeError(modifiers, "is not a string")
        }
        let cacheKey = "\(options.rawValue)/\(pattern)"
        let compiled: NSRegularExpression
        if let cached = regexes[cacheKey] {
            compiled = cached
        } else {
            do {
                 
                compiled = try NSRegularExpression(pattern: pattern.isEmpty ? "(?:)" : Self.literalBraces(pattern), options: options)
            } catch {
                throw fail("\(pattern) (at offset 0) is not a valid regex: \((error as NSError).localizedDescription)")
            }
            if regexes.count >= 32 { regexes.removeAll() }
            regexes[cacheKey] = compiled
        }
        let text = subject as NSString
        let length = text.length
         
         
        let wide = length != subject.unicodeScalars.count
        try reserve(length * (wide ? 10 : 2))
        let names = Self.groupNames(pattern)
        let offsets = ModuleJQCodePointOffsets(subject)
        var matches: [Value] = []
         
        func grew() throws { try beforeAppend(to: matches) }
        var start = 0
        while start <= length {
            guard let found = try firstMatch(compiled, in: text, from: start) else { break }
            let range = found.range
            if range.length == 0 {
                if !skipEmpty {
                    if testing { return .bool(true) }
                    try grew()
                    matches.append(.object(ModuleJSONObject(uniqueKeys: ["offset", "length", "string", "captures"],
                                                             values: [.number(Double(offsets.codePoints(range.location))),
                                                                      .number(0), .string(""), .emptyArray])))
                }
                if !global && !skipEmpty { break }
                start = range.location + (range.location < length ? Self.characterLength(text, range.location) : 1)
                continue
            }
            if testing { return .bool(true) }
            var captures: [Value] = []
            for group in 1..<max(1, found.numberOfRanges) {
                let groupRange = found.range(at: group)
                let name: Value = names[group].map { .string($0) } ?? .null
                if groupRange.location == NSNotFound {
                    captures.append(.object(ModuleJSONObject(uniqueKeys: ["offset", "string", "length", "name"],
                                                              values: [.number(-1), .null, .number(0), name])))
                } else if groupRange.length == 0 {
                    captures.append(.object(ModuleJSONObject(uniqueKeys: ["offset", "string", "length", "name"],
                                                              values: [.number(Double(offsets.codePoints(groupRange.location))),
                                                                       .string(""), .number(0), name])))
                } else {
                    try produce(groupRange.length * 3)
                    let groupStart = offsets.codePoints(groupRange.location)
                    captures.append(.object(ModuleJSONObject(uniqueKeys: ["offset", "length", "string", "name"], values: [
                        .number(Double(groupStart)),
                        .number(Double(offsets.codePoints(groupRange.location + groupRange.length) - groupStart)),
                        .string(Self.native(text.substring(with: groupRange))), name,
                    ])))
                }
            }
            try produce(range.length * 3)
            let matchStart = offsets.codePoints(range.location)
            try grew()
            matches.append(.object(ModuleJSONObject(uniqueKeys: ["offset", "length", "string", "captures"], values: [
                .number(Double(matchStart)), .number(Double(offsets.codePoints(range.location + range.length) - matchStart)),
                .string(Self.native(text.substring(with: range))), .array(ModuleJSONArray(captures)),
            ])))
            if !global { break }
            start = range.location + range.length
            try tick()
        }
        return testing ? .bool(false) : .array(ModuleJSONArray(matches))
    }

     
     
     
     
     
     
     
    private func firstMatch(_ regex: NSRegularExpression, in text: NSString, from start: Int) throws -> NSTextCheckingResult? {
        var found: NSTextCheckingResult?
        var spent = false
        var grown = false
        let footprintAtStart = ModuleJQMachine.footprint()
        let room = Int64(memoryLeft)
        var lastReading = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        regex.enumerateMatches(in: text as String, options: [.reportProgress, .withTransparentBounds, .withoutAnchoringBounds],
                               range: NSRange(location: start, length: text.length - start)) { result, _, stop in
            if let result {
                found = result
                stop.pointee = true
                return
            }
            let now = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            if now &- lastReading >= 1_000_000 {
                lastReading = now
                if self.budgetIsSpent() {
                    spent = true
                    stop.pointee = true
                } else if ModuleJQMachine.footprint() - footprintAtStart > room {
                    grown = true
                    stop.pointee = true
                }
            }
        }
        if spent { throw budgetStop("a regular expression ran past the request's CPU budget") }
        if grown { throw backstopStop("a regular expression grew past what the run has left of \(memoryLimit >> 20) MiB") }
        return found
    }

     
     
    static func native(_ string: String) -> String {
        var string = string
        string.makeContiguousUTF8()
        return string
    }

     
     
    static func literalBraces(_ pattern: String) -> String {
        let scalars = Array(pattern.unicodeScalars)
        guard scalars.contains("{") || scalars.contains("}") else { return pattern }
        var out = String.UnicodeScalarView()
        var index = 0
        var inClass = false
        var closing = Set<Int>()
        func isDigit(_ at: Int) -> Bool { at < scalars.count && ("0"..."9").contains(scalars[at]) }
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\\" {
                out.append(scalar)
                guard index + 1 < scalars.count else { break }
                let escaped = scalars[index + 1]
                out.append(escaped)
                index += 2
                 
                if "pPxNo".unicodeScalars.contains(escaped), index < scalars.count, scalars[index] == "{" {
                    while index < scalars.count {
                        out.append(scalars[index])
                        index += 1
                        if scalars[index - 1] == "}" { break }
                    }
                }
                continue
            }
            if inClass {
                if scalar == "]" { inClass = false }
                out.append(scalar)
                index += 1
                continue
            }
            if scalar == "[" {
                inClass = true
                out.append(scalar)
                index += 1
                 
                if index < scalars.count, scalars[index] == "^" { out.append(scalars[index]); index += 1 }
                if index < scalars.count, scalars[index] == "]" { out.append(scalars[index]); index += 1 }
                continue
            }
            if scalar == "{" {
                 
                var end = index + 1
                var valid = isDigit(end)
                while isDigit(end) { end += 1 }
                if valid, end < scalars.count, scalars[end] == "," {
                    end += 1
                    while isDigit(end) { end += 1 }
                }
                valid = valid && end < scalars.count && scalars[end] == "}"
                if valid {
                    closing.insert(end)
                    out.append(scalar)
                } else {
                    out.append("\\")
                    out.append(scalar)
                }
                index += 1
                continue
            }
            if scalar == "}", !closing.contains(index) {
                out.append("\\")
                out.append(scalar)
                index += 1
                continue
            }
            out.append(scalar)
            index += 1
        }
        return String(out)
    }

    private static func characterLength(_ text: NSString, _ location: Int) -> Int {
        let unit = text.character(at: location)
        return UTF16.isLeadSurrogate(unit) && location + 1 < text.length ? 2 : 1
    }

     
    static func groupNames(_ pattern: String) -> [Int: String] {
        var names: [Int: String] = [:]
        let scalars = Array(pattern.unicodeScalars)
        var index = 0, group = 0, inClass = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\\" {
                index += 2
                continue
            }
            if inClass > 0 {
                if scalar == "[" { inClass += 1 }
                if scalar == "]" { inClass -= 1 }
                index += 1
                continue
            }
            if scalar == "[" {
                inClass = 1
                index += 1
                if index < scalars.count, scalars[index] == "^" { index += 1 }
                if index < scalars.count, scalars[index] == "]" { index += 1 }
                continue
            }
            if scalar == "(" {
                if index + 1 < scalars.count, scalars[index + 1] == "?" {
                    var nameStart: Int?
                    var close: Unicode.Scalar = ">"
                    if index + 2 < scalars.count, scalars[index + 2] == "<", index + 3 < scalars.count,
                       scalars[index + 3] != "=", scalars[index + 3] != "!" {
                        nameStart = index + 3
                    } else if index + 2 < scalars.count, scalars[index + 2] == "'" {
                        nameStart = index + 3
                        close = "'"
                    } else if index + 3 < scalars.count, scalars[index + 2] == "P", scalars[index + 3] == "<" {
                        nameStart = index + 4
                    }
                    if let nameStart {
                        var end = nameStart
                        while end < scalars.count, scalars[end] != close { end += 1 }
                        group += 1
                        var name = String.UnicodeScalarView()
                        name.append(contentsOf: scalars[nameStart..<min(end, scalars.count)])
                        names[group] = String(name)
                    }
                } else {
                    group += 1
                }
            }
            index += 1
        }
        return names
    }

    func budgetIsSpent() -> Bool { budget.isSpent(since: runStarted) }
}

 
struct ModuleJQCodePointOffsets {
    private let surrogatesBefore: [Int]?

    init(_ text: String) {
        if text.utf16.count == text.unicodeScalars.count {
            surrogatesBefore = nil
        } else {
            var table: [Int] = []
            table.reserveCapacity(text.utf16.count + 1)
            var trailing = 0
            for unit in text.utf16 {
                table.append(trailing)
                if UTF16.isTrailSurrogate(unit) { trailing += 1 }
            }
            table.append(trailing)
            surrogatesBefore = table
        }
    }

    func codePoints(_ utf16Offset: Int) -> Int {
        guard let surrogatesBefore else { return utf16Offset }
        let clamped = min(max(utf16Offset, 0), surrogatesBefore.count - 1)
        return utf16Offset - surrogatesBefore[clamped]
    }
}
#endif
