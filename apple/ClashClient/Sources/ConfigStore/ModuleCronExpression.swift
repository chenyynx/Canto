import Foundation

 
 
 
 
 

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ModuleCronExpression: Equatable, Sendable {
    enum Field: Hashable, Sendable {
        case second, minute, hour, dayOfMonth, month, dayOfWeek, year
    }

     
    enum Failure: Error, Equatable, Sendable {
         
        case empty
         
        case fieldCount(Int)
         
        case unsupportedMacro
         
        case malformed(Field)
         
        case outOfRange(Field)
         
        case reversedRange(Field)
         
        case zeroStep(Field)
         
        case unknownName(Field)
         
        case questionMarkOutsideDays(Field)
         
        case quartzSpecial(Field)
    }

    private var seconds: Bits
    private var minutes: Bits
    private var hours: Bits
    private var daysOfMonth: Bits
    private var months: Bits
     
    private var daysOfWeek: Bits
     
    private var years: Bits?
    private var daysOfMonthRestricted: Bool
    private var daysOfWeekRestricted: Bool
    private var isFixedTime: Bool

     
     
     
    static let searchYears = 41

     
    private static let reach: TimeInterval = 1e11

     

     
     
    static func parse(_ text: String) -> Result<ModuleCronExpression, Failure> {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.count >= 2, let quote = body.first, quote == "\"" || quote == "'", body.last == quote {
            body = String(body.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let words = body.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard !words.isEmpty else { return .failure(.empty) }
        if body.hasPrefix("@") {
            guard words.count == 1, let expanded = macros[body.lowercased()] else { return .failure(.unsupportedMacro) }
            return parse(expanded)
        }
        let fields: [Field]
        switch words.count {
        case 5: fields = [.minute, .hour, .dayOfMonth, .month, .dayOfWeek]
        case 6: fields = [.second, .minute, .hour, .dayOfMonth, .month, .dayOfWeek]
        case 7: fields = [.second, .minute, .hour, .dayOfMonth, .month, .dayOfWeek, .year]
        default: return .failure(.fieldCount(words.count))
        }
        var read: [Field: Bits] = [:]
        for (field, word) in zip(fields, words) {
            switch bits(word, field) {
            case .success(let bits): read[field] = bits
            case .failure(let failure): return .failure(failure)
            }
        }
         
        let written = Dictionary(uniqueKeysWithValues: zip(fields, words))
        func word(_ field: Field) -> String { written[field] ?? "*" }
        var daysOfWeek = read[.dayOfWeek] ?? Bits()
        if daysOfWeek.contains(7) {
            daysOfWeek.remove(7)
            daysOfWeek.insert(0)
        }
        return .success(ModuleCronExpression(
            seconds: read[.second] ?? Bits(0),
            minutes: read[.minute] ?? Bits(),
            hours: read[.hour] ?? Bits(),
            daysOfMonth: read[.dayOfMonth] ?? Bits(),
            months: read[.month] ?? Bits(),
            daysOfWeek: daysOfWeek,
            years: word(.year) == "*" ? nil : read[.year],
            daysOfMonthRestricted: !isWrittenWhole(word(.dayOfMonth)),
            daysOfWeekRestricted: !isWrittenWhole(word(.dayOfWeek)),
            isFixedTime: !isWrittenWhole(word(.minute)) && !isWrittenWhole(word(.hour))
        ))
    }

     
    private static let macros: [String: String] = [
        "@yearly": #"0 0 1 1 *"#, "@annually": #"0 0 1 1 *"#, "@monthly": #"0 0 1 * *"#,
        "@weekly": #"0 0 * * 0"#, "@daily": #"0 0 * * *"#, "@midnight": #"0 0 * * *"#, "@hourly": #"0 * * * *"#,
    ]

     
    private static func isWrittenWhole(_ word: String) -> Bool {
        if word.hasPrefix("*") || word.hasPrefix("?") { return true }
        let term = word.prefix { $0 != "," }
        return term.contains("/") && !term.contains("-")
    }

    private static func values(_ field: Field) -> ClosedRange<Int> {
        switch field {
        case .second, .minute: return 0...59
        case .hour: return 0...23
        case .dayOfMonth: return 1...31
        case .month: return 1...12
        case .dayOfWeek: return 0...7
        case .year: return 1970...2099
        }
    }

    private static let monthNames = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
    private static let dayNames = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]

     
    private static func bits(_ word: String, _ field: Field) -> Result<Bits, Failure> {
        let span = values(field)
        let isDay = field == .dayOfMonth || field == .dayOfWeek
        let terms = word.split(separator: ",", omittingEmptySubsequences: false)
        var bits = Bits()
        for term in terms {
            if term == "?" {
                guard isDay else { return .failure(.questionMarkOutsideDays(field)) }
                guard terms.count == 1 else { return .failure(.malformed(field)) }
                for value in span { bits.insert(value) }
                continue
            }
            if isDay, isQuartzSpecial(term) { return .failure(.quartzSpecial(field)) }
            guard !term.isEmpty, term.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "*-/".contains($0)) }) else {
                return .failure(.malformed(field))
            }
            let parts = term.split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count <= 2 else { return .failure(.malformed(field)) }
            var step = 1
            if parts.count == 2 {
                guard let number = number(parts[1]) else { return .failure(.malformed(field)) }
                guard number > 0 else { return .failure(.zeroStep(field)) }
                step = number
            }
            let low: Int
            let high: Int
            if parts[0] == "*" {
                low = span.lowerBound
                high = span.upperBound
            } else {
                let ends = parts[0].split(separator: "-", omittingEmptySubsequences: false)
                guard ends.count <= 2 else { return .failure(.malformed(field)) }
                switch value(ends[0], field) {
                case .success(let value): low = value
                case .failure(let failure): return .failure(failure)
                }
                if ends.count == 2 {
                    switch value(ends[1], field) {
                    case .success(let value): high = value
                    case .failure(let failure): return .failure(failure)
                    }
                    guard low <= high else { return .failure(.reversedRange(field)) }
                } else {
                    high = parts.count == 2 ? span.upperBound : low
                }
            }
            var value = low
            while value <= high {
                bits.insert(field == .year ? value - 1970 : value)
                value += step
            }
        }
        return .success(bits)
    }

     
    private static func value(_ text: Substring, _ field: Field) -> Result<Int, Failure> {
        if let number = number(text) {
            return values(field).contains(number) ? .success(number) : .failure(.outOfRange(field))
        }
        guard !text.isEmpty, text.allSatisfy(\.isLetter) else { return .failure(.malformed(field)) }
        let names = field == .month ? monthNames : field == .dayOfWeek ? dayNames : []
        guard let index = names.firstIndex(of: text.lowercased()) else { return .failure(.unknownName(field)) }
        return .success(field == .month ? index + 1 : index)
    }

     
    private static func number(_ text: Substring) -> Int? {
        guard !text.isEmpty, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        var number = 0
        for digit in text.utf8 {
            number = min(number * 10 + Int(digit - 48), 1_000_000)
        }
        return number
    }

     
    private static func isQuartzSpecial(_ term: Substring) -> Bool {
        if term.contains("#") { return true }
        let letters = term.uppercased().filter { !$0.isNumber && $0 != "-" }
        return letters == "L" || letters == "W" || letters == "LW"
    }

     

     
     
     
     
     
     
     
     
    func nextFire(after date: Date, in timeZone: TimeZone) -> Date? {
        let since1970 = date.timeIntervalSince1970
        guard since1970.isFinite, abs(since1970) < Self.reach else { return nil }
        var instant = Int64(since1970.rounded(.down)) + 1
        var offset = Self.offset(timeZone, at: instant)
        var earliest = instant + offset
        guard let limit = searchLimit(fromWall: earliest) else { return nil }

         
        if let last = Self.lastTransition(timeZone, atOrBefore: instant) {
            let before = Self.offset(timeZone, at: last - 1)
            let after = Self.offset(timeZone, at: last)
            if isFixedTime, after < before { earliest = max(earliest, last + before) }
            if isFixedTime, after > before, last == instant,
               nextWall(atOrAfter: last + before, before: last + after) != nil {
                return Self.date(instant)
            }
        }

        var wall = nextWall(atOrAfter: earliest, before: limit)
        while let found = wall {
            let candidate = found - offset
            guard let transition = Self.transition(timeZone, after: instant, offset: offset, upTo: candidate) else {
                return Self.date(candidate)
            }
             
            let next = Self.offset(timeZone, at: transition)
            if next > offset, found < transition + next {
                 
                if isFixedTime { return Self.date(transition) }
                wall = nextWall(atOrAfter: transition + next, before: limit)
            } else if next < offset, !isFixedTime {
                 
                wall = nextWall(atOrAfter: transition + next, before: limit)
            }
            instant = transition
            offset = next
        }
        return nil
    }

     
     
    private func searchLimit(fromWall wall: Int64) -> Int64? {
        let year = Self.civil(Self.floorDivide(wall, 86_400)).year
        var first = year
        if let years {
            guard let allowed = years.first(atOrAfter: year - 1970) else { return nil }
            first = max(year, allowed + 1970)
        }
        return Self.days(year: first + Self.searchYears, month: 1, day: 1) * 86_400
    }

     
     
    private func nextWall(atOrAfter start: Int64, before limit: Int64) -> Int64? {
        let startDay = Self.floorDivide(start, 86_400)
        var (year, month, day) = Self.civil(startDay)
        let secondOfDay = Int(start - startDay * 86_400)
        var hour = secondOfDay / 3_600
        var minute = secondOfDay / 60 % 60
        var second = secondOfDay % 60

        func nextMonth() {
            month += 1
            if month > 12 { month = 1; year += 1 }
            day = 1; hour = 0; minute = 0; second = 0
        }

        while true {
            if let years, !years.contains(year - 1970) {
                guard let allowed = years.first(atOrAfter: year - 1970 + 1) else { return nil }
                year = allowed + 1970
                month = 1; day = 1; hour = 0; minute = 0; second = 0
            }
            if !months.contains(month) {
                if let allowed = months.first(atOrAfter: month + 1) {
                    month = allowed
                } else {
                    year += 1
                    month = months.first(atOrAfter: 1) ?? 1
                }
                day = 1; hour = 0; minute = 0; second = 0
                continue
            }
            let firstOfMonth = Self.days(year: year, month: month, day: 1)
            guard (firstOfMonth + Int64(day - 1)) * 86_400 < limit else { return nil }
            let length = Self.length(year: year, month: month)
            if day > length { nextMonth(); continue }
            var weekday = Int(Self.floorModulo(firstOfMonth + Int64(day - 1) + 4, 7))  
            var matching = day
            while matching <= length, !dayMatches(matching, weekday: weekday) {
                matching += 1
                weekday = (weekday + 1) % 7
            }
            if matching > length { nextMonth(); continue }
            if matching != day { day = matching; hour = 0; minute = 0; second = 0 }
            guard let allowedHour = hours.first(atOrAfter: hour) else {
                day += 1; hour = 0; minute = 0; second = 0
                continue
            }
            if allowedHour != hour { hour = allowedHour; minute = 0; second = 0 }
            guard let allowedMinute = minutes.first(atOrAfter: minute) else {
                hour += 1; minute = 0; second = 0
                continue
            }
            if allowedMinute != minute { minute = allowedMinute; second = 0 }
            guard let allowedSecond = seconds.first(atOrAfter: second) else {
                minute += 1; second = 0
                continue
            }
            second = allowedSecond
            let wall = (firstOfMonth + Int64(day - 1)) * 86_400 + Int64(hour * 3_600 + minute * 60 + second)
            return wall < limit ? wall : nil
        }
    }

     
    private func dayMatches(_ day: Int, weekday: Int) -> Bool {
        let byMonth = daysOfMonth.contains(day)
        let byWeek = daysOfWeek.contains(weekday)
        return daysOfMonthRestricted && daysOfWeekRestricted ? byMonth || byWeek : byMonth && byWeek
    }

     

    private static func date(_ seconds: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(seconds))
    }

    private static func offset(_ zone: TimeZone, at instant: Int64) -> Int64 {
        Int64(zone.secondsFromGMT(for: date(instant)))
    }

    private static func reportedTransition(_ zone: TimeZone, after instant: Int64) -> Int64? {
        zone.nextDaylightSavingTimeTransition(after: date(instant)).map { Int64($0.timeIntervalSince1970.rounded()) }
    }

     
     
     
    private static func transition(_ zone: TimeZone, after instant: Int64, offset: Int64, upTo bound: Int64) -> Int64? {
        if let reported = reportedTransition(zone, after: instant), reported > instant, reported <= bound {
            return reported
        }
        guard bound > instant, self.offset(zone, at: bound) != offset else { return nil }
        var low = instant
        var high = bound
        while high - low > 1 {
            let middle = low + (high - low) / 2
            if self.offset(zone, at: middle) == offset { low = middle } else { high = middle }
        }
        return high
    }

     
     
    private static func lastTransition(_ zone: TimeZone, atOrBefore instant: Int64) -> Int64? {
        var last: Int64?
        var probe = instant - 2 * 86_400
        while let next = reportedTransition(zone, after: probe), next > probe, next <= instant {
            last = next
            probe = next
        }
        return last
    }

     

    private static func floorDivide(_ value: Int64, _ divisor: Int64) -> Int64 {
        let quotient = value / divisor
        return value % divisor < 0 ? quotient - 1 : quotient
    }

    private static func floorModulo(_ value: Int64, _ divisor: Int64) -> Int64 {
        value - floorDivide(value, divisor) * divisor
    }

     
    private static func days(year: Int, month: Int, day: Int) -> Int64 {
        let y = Int64(month <= 2 ? year - 1 : year)
        let era = floorDivide(y, 400)
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * Int64(month > 2 ? month - 3 : month + 9) + 2) / 5 + Int64(day) - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }

    private static func civil(_ days: Int64) -> (year: Int, month: Int, day: Int) {
        let shifted = days + 719_468
        let era = floorDivide(shifted, 146_097)
        let dayOfEra = shifted - era * 146_097
        let yearOfEra = (dayOfEra - dayOfEra / 1_460 + dayOfEra / 36_524 - dayOfEra / 146_096) / 365
        let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
        let shiftedMonth = (5 * dayOfYear + 2) / 153
        let day = Int(dayOfYear - (153 * shiftedMonth + 2) / 5 + 1)
        let month = Int(shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9)
        return (Int(yearOfEra + era * 400) + (month <= 2 ? 1 : 0), month, day)
    }

    private static func length(year: Int, month: Int) -> Int {
        switch month {
        case 2: return year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }
}

extension ModuleCronExpression {
     
    private struct Bits: Equatable, Sendable {
        private var low: UInt64 = 0
        private var middle: UInt64 = 0
        private var high: UInt64 = 0

        init() {}

        init(_ value: Int) { insert(value) }

        private func word(_ index: Int) -> UInt64 {
            index == 0 ? low : index == 1 ? middle : high
        }

        func contains(_ value: Int) -> Bool {
            guard (0..<192).contains(value) else { return false }
            return word(value >> 6) & (1 << UInt64(value & 63)) != 0
        }

        mutating func insert(_ value: Int) {
            guard (0..<192).contains(value) else { return }
            let bit: UInt64 = 1 << UInt64(value & 63)
            switch value >> 6 {
            case 0: low |= bit
            case 1: middle |= bit
            default: high |= bit
            }
        }

        mutating func remove(_ value: Int) {
            guard (0..<192).contains(value) else { return }
            let bit: UInt64 = ~(1 << UInt64(value & 63))
            switch value >> 6 {
            case 0: low &= bit
            case 1: middle &= bit
            default: high &= bit
            }
        }

         
        func first(atOrAfter value: Int) -> Int? {
            var index = max(0, value)
            while index < 192 {
                let shifted = word(index >> 6) >> UInt64(index & 63)
                if shifted != 0 { return index + shifted.trailingZeroBitCount }
                index = (index >> 6 + 1) << 6
            }
            return nil
        }
    }
}
