#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 

 
struct ModuleMessageView {
    var urls: ModuleRequestURLs
    var method: String
    var requestHeaders: ModuleHTTPHeaders
    var responseStatus: Int?
    var responseHeaders: ModuleHTTPHeaders?

    init(urls: ModuleRequestURLs, method: String, requestHeaders: ModuleHTTPHeaders = ModuleHTTPHeaders(),
         responseStatus: Int? = nil, responseHeaders: ModuleHTTPHeaders? = nil) {
        self.urls = urls
        self.method = method
        self.requestHeaders = requestHeaders
        self.responseStatus = responseStatus
        self.responseHeaders = responseHeaders
    }

     
     
     
    static func value(_ name: String, in headers: ModuleHTTPHeaders?) -> String? {
        guard let values = headers?.values(name), !values.isEmpty else { return nil }
        return values.joined(separator: ", ")
    }

     
     
     
     
    static func head(method: String, url: String, headers: ModuleHTTPHeaders) -> String {
        head(method: method, target: target(of: url), headers: headers)
    }

     
    static func head(method: String, target: String, headers: ModuleHTTPHeaders) -> String {
        var text = "\(method) \(target) HTTP/1.1\r\n"
        for field in headers.fields { text += "\(field.name): \(field.value)\r\n" }
        return text
    }

     
    static func target(of url: String) -> String {
        guard let scheme = url.range(of: "://") else { return "/" }
        let rest = url[scheme.upperBound...].prefix { $0 != "#" }
        guard let start = rest.firstIndex(where: { $0 == "/" || $0 == "?" }) else { return "/" }
        return rest[start] == "?" ? "/" + rest[start...] : String(rest[start...])
    }

     
     
     
    static func readHead(_ text: String) -> (method: String, target: String, fields: [ModuleHTTPField])? {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)[...]
        guard let first = lines.popFirst() else { return nil }
        let request = first.split(separator: " ", omittingEmptySubsequences: false)
        guard request.count == 3, request[2].hasPrefix("HTTP/"), !request[0].isEmpty,
              request[0].allSatisfy(ModuleHTTPParser.isTokenCharacter), request[1].hasPrefix("/") || request[1] == "*" else { return nil }
        var fields: [ModuleHTTPField] = []
        for line in lines where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = String(line[..<colon]), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, name.allSatisfy(ModuleHTTPParser.isTokenCharacter), ModuleHTTPParser.isValidFieldText(value) else { return nil }
            fields.append(ModuleHTTPField(name: name, value: value))
        }
        return (String(request[0]), String(request[1]), fields)
    }
}

enum ModuleConditionEvaluation {
     
     
    struct Captures: Equatable {
        var named: [String: [String]] = [:]
    }

     
     
    indirect enum Compiled {
        case all([Compiled])
        case any([Compiled])
         
         
        case gate(capture: String?)
        case regex(ModuleConditionVariable, NSRegularExpression, capture: String?)
        case equals(ModuleConditionVariable, ModuleConditionValue)
    }

     
    struct Refusal: Error {
        let reason: String
    }

     
     
     
    static func compile(_ condition: ModuleCondition, gate: String?,
                        compile: (String) throws -> NSRegularExpression) throws -> Compiled {
        switch condition {
        case .all(let parts): return .all(try parts.map { try self.compile($0, gate: gate, compile: compile) })
        case .any(let parts): return .any(try parts.map { try self.compile($0, gate: gate, compile: compile) })
        case .match(let variable, .regexSearch, .regex(let pattern), let capture):
            if variable == .url, let gate, !gate.isEmpty, pattern == gate { return .gate(capture: capture) }
            return .regex(variable, try compile(pattern), capture: capture)
        case .match(let variable, .regexSearch, let value, let capture):
             
            guard case .string(let text) = value else { throw Refusal(reason: "a `~=` against \(value) is no regex") }
            return .regex(variable, try compile(NSRegularExpression.escapedPattern(for: text)), capture: capture)
        case .match(let variable, .equals, let value, _):
            return .equals(variable, value)
        }
    }

     
    static func regexCount(_ compiled: Compiled) -> Int {
        switch compiled {
        case .all(let parts), .any(let parts): return parts.reduce(0) { $0 + regexCount($1) }
        case .regex: return 1
        case .gate, .equals: return 0
        }
    }

     
     
    static func readsRequestHeaders(_ compiled: Compiled) -> Bool {
        switch compiled {
        case .all(let parts), .any(let parts): return parts.contains { readsRequestHeaders($0) }
        case .regex(.requestHeader, _, _), .equals(.requestHeader, _), .regex(.requestHead, _, _), .equals(.requestHead, _): return true
        case .gate, .regex, .equals: return false
        }
    }

     
     
    struct GateMatch {
        let url: String
        let match: NSTextCheckingResult
    }

     
    enum Outcome: Equatable {
        case holds(Captures)
        case fails
         
         
        case budgetSpent
         
         
        case timedOut
    }

     
     
     
     
    static func evaluate(_ condition: Compiled, in view: ModuleMessageView, gate: GateMatch?,
                         budget: inout ModuleRequestBudget) -> Outcome {
        var captures = Captures()
        let outcome = evaluate(condition, view, gate, &captures, &budget)
        switch outcome {
        case .holds: return .holds(captures)
        default: return outcome
        }
    }

    private static func evaluate(_ condition: Compiled, _ view: ModuleMessageView, _ gate: GateMatch?, _ captures: inout Captures,
                                 _ budget: inout ModuleRequestBudget) -> Outcome {
        switch condition {
        case .all(let parts):
            for part in parts {
                let outcome = evaluate(part, view, gate, &captures, &budget)
                guard case .holds = outcome else { return outcome }
            }
            return .holds(captures)
        case .any(let parts):
            var stopped: Outcome?
            for part in parts {
                 
                var branch = captures
                switch evaluate(part, view, gate, &branch, &budget) {
                case .holds:
                    captures = branch
                    return .holds(captures)
                case .fails: continue
                case let other: stopped = stopped ?? other
                }
            }
            return stopped ?? .fails
        case .gate(let capture):
            guard let gate else { return .fails }
            if let capture { captures.named[capture] = groups(of: gate.match, in: gate.url) }
            return .holds(captures)
        case .regex(let variable, let regex, let capture):
            guard let subject = text(of: variable, in: view, url: gate?.url) else { return .fails }
            guard !budget.isSpent else {
                budget.noteStop()
                return .budgetSpent
            }
            let allowed = min(ModuleGatedMatcher.evaluationDeadline, budget.remainingSeconds)
            let started = ModuleRequestBudget.threadNanoseconds()
            let evaluation = ModuleGatedMatcher.evaluate(regex, on: subject, deadline: allowed)
            budget.charge(ModuleRequestBudget.threadNanoseconds() &- started)
            switch evaluation {
            case .match(let match):
                if let capture { captures.named[capture] = groups(of: match, in: subject) }
                return .holds(captures)
            case .noMatch:
                return .fails
            case .timedOut where allowed < ModuleGatedMatcher.evaluationDeadline:
                budget.noteStop()
                return .budgetSpent
            case .timedOut:
                return .timedOut
            }
        case .equals(let variable, let value):
            return equals(variable, value, view, url: gate?.url) ? .holds(captures) : .fails
        }
    }

     
     
    static func text(of variable: ModuleConditionVariable, in view: ModuleMessageView, url: String?) -> String? {
        switch variable {
        case .url: return url ?? view.urls.primary
        case .requestMethod: return view.method
        case .requestHeader(let name): return ModuleMessageView.value(name, in: view.requestHeaders)
        case .responseStatus: return view.responseStatus.map(String.init)
        case .responseHeader(let name): return ModuleMessageView.value(name, in: view.responseHeaders)
        case .requestHead: return ModuleMessageView.head(method: view.method, url: url ?? view.urls.primary, headers: view.requestHeaders)
        }
    }

     
     
     
     
    private static func equals(_ variable: ModuleConditionVariable, _ value: ModuleConditionValue, _ view: ModuleMessageView,
                               url: String?) -> Bool {
        let subject = text(of: variable, in: view, url: url)
        switch value {
        case .null:
            return subject == nil
        case .string(let text):
            return subject == text
        case .number(let number):
            if case .responseStatus = variable, let status = view.responseStatus { return Double(status) == number }
            guard let subject, let read = Double(subject.trimmingCharacters(in: .whitespaces)) else { return false }
            return read == number
        case .regex(let pattern):
             
            return subject == pattern
        }
    }

     
    static func groups(of match: NSTextCheckingResult, in text: String) -> [String] {
        let source = text as NSString
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? "" : source.substring(with: range)
        }
    }

     
     
     
     
     
     
    static func holds(_ condition: ModuleCondition, in view: ModuleMessageView,
                      deadline: TimeInterval = ModuleGatedMatcher.evaluationDeadline) -> Captures? {
        guard let compiled = try? compile(condition, gate: nil, compile: { try NSRegularExpression(pattern: $0) }) else { return nil }
        var budget = ModuleRequestBudget(seconds: max(deadline, 0) * Double(max(1, regexCount(compiled))))
        if case .holds(let captures) = evaluate(compiled, in: view, gate: nil, budget: &budget) { return captures }
        return nil
    }
}
#endif
