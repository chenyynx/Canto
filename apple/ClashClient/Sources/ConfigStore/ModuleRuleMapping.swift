import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleRuleMapping {
     
     
     
     
    typealias Check = (String) throws -> String?

     
     
     
    static let kernelCheck: Check = { line in
        let item = String(decoding: try JSONSerialization.data(withJSONObject: line, options: [.fragmentsAllowed]),
                          as: UTF8.self)
        return try ConfigurationTextEditing.check(kind: "rule", itemJSON: item, contextJSON: "{}")
    }

     
     
     
     
     
     
    static func kernelPolicy(_ policy: String) -> String? {
        let upper = policy.uppercased()
        if upper == "DIRECT" { return "DIRECT" }
         
         
        if upper == "REJECT-DROP" || upper.hasPrefix("REJECT-DROP-") { return "REJECT-DROP" }
        return isReject(upper) ? "REJECT" : nil
    }

     
    static func isReject(_ policy: String) -> Bool {
        let upper = policy.uppercased()
        return upper == "REJECT" || (upper.hasPrefix("REJECT-") && upper.count > 7)
    }

     
     
     
     
     
    static func closestReject(_ policy: String) -> String {
        let upper = policy.uppercased()
        if ModuleLineSyntax.rejectAction(upper) != nil || upper == "REJECT-VIDEO" { return upper }
        for member in ["REJECT-DICT", "REJECT-ARRAY", "REJECT-TINYGIF", "REJECT-IMG", "REJECT-VIDEO", "REJECT-200", "REJECT-DROP"]
        where upper.hasPrefix(member + "-") {
            return member
        }
        return "REJECT"
    }

     
     
     
     
     
    static func rejectWord(in name: String) -> String? {
        let words = name.uppercased().split { !($0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-")) }
        return words.map(String.init).first(where: isReject)
    }

     

     
    struct Fields: Equatable {
         
        var type: String
         
         
         
        var payload: [String]
         
         
         
        var policy: String?
         
        var options: [String]
    }

     
     
     
     
    static let knownOptions: Set<String> = ["no-resolve", "src", "extended-matching", "pre-matching", "allow-other-interface",
                                            "no-track", "dns-failed", "requires-resolve", "force-remote-dns"]

     
     
     
     
     
     
     
    static let kernelOptions: Set<String> = ["no-resolve", "src"]

     
     
    static func isOption(_ field: String) -> Bool {
        let lowered = field.lowercased()
        if knownOptions.contains(lowered) { return true }
        guard let equals = lowered.firstIndex(of: "="), equals != lowered.startIndex else { return false }
        let name = lowered[..<equals]
        return name.first.map { $0 >= "a" && $0 <= "z" } == true
            && name.allSatisfy { ($0 >= "a" && $0 <= "z") || ($0 >= "0" && $0 <= "9") || $0 == "-" }
    }

     
     
     
     
     
     
     
     
     
     
     
    static func split(_ line: String, family: ModuleFormat) -> Fields? {
        split(fields(line, unquoting: family != .stash))
    }

    private static func split(_ field: [String]) -> Fields? {
        let type = field[0].uppercased()
        guard !type.isEmpty, field.count >= 2, !field[1].isEmpty else { return nil }
        var rest = Array(field.dropFirst(2))
        var options: [String] = []
        var payload = [field[1]]
        var policy: String?
        if payloadIsRegex(type) {
            while let last = rest.last, last.isEmpty || isOption(last) {
                if !last.isEmpty { options.insert(last, at: 0) }
                rest.removeLast()
            }
            policy = rest.popLast()
            while let last = rest.last, knownOptions.contains(last.lowercased()) {
                options.insert(last, at: 0)
                rest.removeLast()
            }
            payload += rest
        } else {
            options = rest.filter(isOption)
             
            policy = rest.first { !$0.isEmpty && !isOption($0) }
        }
        if policy?.isEmpty == true { policy = nil }
        return Fields(type: type, payload: payload, policy: policy, options: options)
    }

     
     
     
     
    static func isPolicyName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, !"\"'`".unicodeScalars.contains(first), ModuleYAMLText.isOneLine(name),
              !name.contains("\""), !name.contains("`") else { return false }
        var depth: [Character] = []
        let pairs: [Character: Character] = [")": "(", "]": "[", "}": "{"]
        for character in name {
            switch character {
            case "(", "[", "{": depth.append(character)
            case ")", "]", "}":
                guard depth.popLast() == pairs[character] else { return false }
            default: break
            }
        }
        return depth.isEmpty
    }

     
     
     
     
     
     
     
     
    static func policy(_ written: String?, family: ModuleFormat) -> ModuleRulePolicy {
        guard let written, !written.isEmpty else { return .builtIn("DIRECT") }
        if kernelPolicy(written) != nil { return .builtIn(written.uppercased()) }
        if written == "PROXY" { return .moduleChoice }
        return .named(written)
    }

     
     
     
     
     
     
     
     
     
     
     
     
    static func fields(_ line: String, unquoting: Bool = false) -> [String] {
        let lead = line.drop { $0 == " " || $0 == "\t" }
        let type = lead.prefix { $0 != "," }.trimmingCharacters(in: .whitespaces).uppercased()
        let grouped = lead.hasPrefix("(") || ["AND", "OR", "NOT", "SUB-RULE"].contains(type)
        var out: [String] = []
        var current = ""
        var raw = ""
        var depth = 0
        var quote: Character?
        var quoted: String?
        var spoiled = false
        func close() {
            if let quoted, !spoiled {
                out.append(quoted)
            } else {
                out.append((quoted == nil ? current : raw).trimmingCharacters(in: .whitespaces))
            }
            current = ""
            raw = ""
            quoted = nil
            spoiled = false
        }
        for character in line {
            if let open = quote {
                raw.append(character)
                if character == open {
                    quote = nil
                    if depth == 0 {
                        quoted = current
                        current = ""
                        continue
                    }
                }
                current.append(character)
                continue
            }
            if unquoting, character == "\"" || character == "'" {
                let opens = depth == 0
                    ? quoted == nil && current.allSatisfy { $0 == " " || $0 == "\t" }
                    : current.last == "(" || current.last == ","
                if opens {
                    quote = character
                    raw.append(character)
                    if depth == 0 { current = "" } else { current.append(character) }
                    continue
                }
            }
            if quoted != nil, depth == 0, character != ",", character != " ", character != "\t" { spoiled = true }
            switch character {
            case "(" where grouped:
                depth += 1
                current.append(character)
            case ")" where grouped:
                depth -= 1
                current.append(character)
            case "," where depth == 0:
                close()
                continue
            default:
                current.append(character)
            }
            raw.append(character)
        }
        if quote != nil { return fields(line) }
        close()
        return out
    }

     

    enum Outcome: Equatable {
         
        case kernel(ModuleRoutingRule)
         
         
         
         
        case rewrite(pattern: String, action: ModuleRewriteAction, policy: String? = nil)
         
        case engine(ModuleEngineRule)
         
        case ruleSet(ModuleRuleSet)
        case ignored(ModuleIgnoredReason)
    }

     
     
     
     
     
     
    struct Mapped: Equatable {
        var outcome: Outcome
        var setAside: [ModuleIgnoredReason] = []
        var plainHTTPHosts: [ModuleHostEntry] = []
    }

     
     
     
     
     
    static func map(_ line: String, family: ModuleFormat = .surge, platform: ModulePlatform = .current,
                    origin: ModuleLineOrigin = ModuleLineOrigin(section: "Rule", line: 0),
                    check: Check = kernelCheck) throws -> Mapped {
        func ignored(_ reason: ModuleIgnoredReason) -> Mapped { Mapped(outcome: .ignored(reason)) }
        guard isWithinTheBounds(line), ModuleYAMLText.isOneLine(line) else { return ignored(.unreadableLine) }
         
         
         
        let written = family == .stash ? String(line[..<(line.range(of: " //")?.lowerBound ?? line.endIndex)]) : line
        let field = fields(written, unquoting: family != .stash)
        let type = field[0].uppercased()
         
         
        if type == "MATCH" || type == "FINAL" { return ignored(.notApplicable(.catchAllBelongsToTheConfiguration)) }
        if family == .loon, type.hasPrefix("HTTP://") || type.hasPrefix("HTTPS://") {
             
            let named = field.dropFirst().first { !isOption($0) }
            return Mapped(outcome: .ruleSet(ModuleRuleSet(url: field[0], inline: nil, kind: .classical,
                                                           policy: policy(named, family: family), params: [],
                                                           interval: nil, origin: origin)))
        }
        guard let parts = split(field), parts.policy != nil || family == .loon else { return ignored(.unreadableLine) }
         
         
         
         
        if let written = parts.policy, !isPolicyName(written) { return ignored(.unreadableLine) }
         
         
        if type == "RULE-SET" || type == "DOMAIN-SET" {
            switch ModuleRuleSetSyntax.line(parts, family: family, origin: origin) {
            case .success(let set): return Mapped(outcome: .ruleSet(set), setAside: setAside(parts.options))
            case .failure(let reason): return ignored(reason)
            }
        }
         
         
         
         
        if platform != .mac, ModuleActivationStep.carriesUID(written) { return ignored(.platformCannot(.processRules)) }
        let policy = Self.policy(parts.policy, family: family)
        let aside = setAside(parts.options)
        switch type {
        case "URL-REGEX":
            let pattern = parts.payload.joined(separator: ",")
            guard ModuleLineSyntax.isValidPattern(pattern) else { return ignored(.invalidPattern) }
            let hosts = plainHTTPHosts(of: pattern)
             
             
             
            if let reject = rejectNamed(by: policy) {
                let action = ModuleLineSyntax.rejectAction(closestReject(reject)) ?? .reject
                return Mapped(outcome: .rewrite(pattern: pattern, action: action, policy: writtenName(policy)), setAside: aside,
                              plainHTTPHosts: hosts)
            }
            let rule = ModuleEngineRule(condition: .urlRegex(pattern), gatePattern: pattern, decision: decision(policy), origin: origin,
                                         policy: writtenName(policy))
            return Mapped(outcome: .engine(rule), setAside: aside, plainHTTPHosts: hosts)
        case "USER-AGENT":
            guard parts.payload.count == 1, let agent = userAgent(parts.payload[0]) else { return ignored(.unreadableLine) }
            let rule = ModuleEngineRule(condition: .userAgent(agent), gatePattern: "", decision: decision(policy), origin: origin,
                                         policy: writtenName(policy))
            return Mapped(outcome: .engine(rule), setAside: aside)
        default:
            break
        }
        let head: String
        var params: [String] = []
        if logicTypes.contains(type) {
            guard parts.payload.count == 1 else { return ignored(.unreadableLine) }
            let node: Member
            switch members(type, parts.payload[0], family: family, level: 1) {
            case .success(let read): node = read
            case .failure(let reason): return ignored(reason)
            }
            if node.readsTheRequest {
                switch engineCondition(node) {
                case .success(let condition):
                    let rule = ModuleEngineRule(condition: condition, gatePattern: gate(condition), decision: decision(policy), origin: origin,
                                                 policy: writtenName(policy))
                    return Mapped(outcome: .engine(rule), setAside: aside,
                                  plainHTTPHosts: node.urlPatterns.flatMap(plainHTTPHosts(of:)).uniqued())
                case .failure(let reason):
                    return ignored(reason)
                }
            }
            switch kernelText(node, family: family, platform: platform) {
            case .success(let text): head = text
            case .failure(let reason): return ignored(reason)
            }
        } else if payloadIsRegex(type) {
            if processTypes.contains(type), platform != .mac { return ignored(.platformCannot(.processRules)) }
            head = type + "," + parts.payload.joined(separator: ",")
        } else {
            switch translate(type, parts.payload[0], parts.options, family: family, platform: platform) {
            case .success(let condition):
                head = condition.type + "," + condition.payload
                params = condition.params
            case .failure(let reason):
                return ignored(reason)
            }
        }
        let rule = ModuleRoutingRule(head: head, policy: policy, params: params, origin: origin)
         
         
         
        let checked = rule.rendered(policy.kernelName ?? "DIRECT")
         
         
        guard isWithinTheBounds(checked) else { return ignored(.unreadableLine) }
        if let refusal = try check(checked) { return ignored(.ruleRefused(refusal)) }
        return Mapped(outcome: .kernel(rule), setAside: aside)
    }

     
     
     
    static func take(_ mapped: Mapped, written: String, origin: ModuleLineOrigin, into ir: inout ModuleIR) {
        switch mapped.outcome {
        case .kernel(let rule): ir.routingRules.append(rule)
        case .rewrite(let pattern, let action, let policy):
            ir.rewriteRules.append(ModuleRewriteRule(pattern: pattern, actions: [action], origin: origin, policy: policy))
        case .engine(let rule): ir.engineRules.append(rule)
        case .ruleSet(let set):
             
             
             
            if set.isDefinition, !ir.ruleSets.contains(where: { $0.reference == set.reference }) { ir.ruleSets.append(set) }
            ir.routingRules.append(ModuleRoutingRule(head: set.reference, policy: set.policy, params: set.params, origin: origin))
        case .ignored(let reason):
            ir.ignored.append(ModuleIgnoredEntry(text: written, reason: reason, origin: origin))
            return
        }
        for reason in mapped.setAside {
            ir.ignored.append(ModuleIgnoredEntry(text: written, reason: reason, origin: origin))
        }
        let listed = Set(ir.forceHTTPEngineHostLines.flatMap(\.entries))
        let fresh = mapped.plainHTTPHosts.filter { !listed.contains($0) }
        if !fresh.isEmpty {
            ir.forceHTTPEngineHostLines.append(ModuleHostListLine(directive: .append, entries: fresh, origin: origin))
        }
    }

     
     
     
     
     
     
     
     
     
    static func decision(_ policy: ModuleRulePolicy) -> ModuleEngineDecision {
        guard let named = rejectNamed(by: policy) else { return .pass }
        let reject = closestReject(named)
        if let action = ModuleLineSyntax.rejectAction(reject) { return .answer(action) }
        if reject == "REJECT-VIDEO" {
            return .answer(.localAnswer(ModuleLocalAnswer(status: 200, headers: [ModuleHeaderField(name: "Content-Type", value: "video/mp4")],
                                                           body: .emptyVideo)))
        }
        return .answer(.reject)
    }

     
     
     
     
     
     
    static func writtenName(_ policy: ModuleRulePolicy) -> String? {
        if case .named(let name) = policy { return name }
        return nil
    }

     
     
    static func rejectNamed(by policy: ModuleRulePolicy) -> String? {
        switch policy {
        case .builtIn(let name): return isReject(name) ? name.uppercased() : nil
        case .named(let name): return rejectWord(in: name)
        case .moduleChoice: return nil
        }
    }

     
     
     
    static func userAgent(_ written: String) -> String? {
        guard !written.isEmpty else { return nil }
        if written.contains("%"), let decoded = written.removingPercentEncoding, !decoded.isEmpty { return decoded }
        return written
    }

     
     
     
     
     
    private static func setAside(_ options: [String]) -> [ModuleIgnoredReason] {
        let names = options.map { $0.split(separator: "=", maxSplits: 1).first.map { $0.lowercased() } ?? "" }
        var out: [ModuleIgnoredReason] = []
        if names.contains("notification-text") || names.contains("notification-interval") {
            out.append(.settingNotSupported("notification-text"))
        }
        if names.contains("always-capture") { out.append(.notApplicable(.noCaptureSession)) }
        return out
    }

     

     
     
     
     
     
     
     
    static let maximumRuleBytes = 4096
    static let maximumLogicDepth = 10

     
     
     
    static func isWithinTheBounds(_ line: String) -> Bool {
        guard line.utf8.count <= maximumRuleBytes else { return false }
        var depth = 0
        for byte in line.utf8 {
            if byte == UInt8(ascii: "(") {
                depth += 1
                if depth > 2 * maximumLogicDepth + 1 { return false }
            } else if byte == UInt8(ascii: ")") {
                depth -= 1
            }
        }
        return true
    }

     

    private static let addressTypes: Set<String> = ["IP-CIDR", "IP-CIDR6", "IP-SUFFIX", "IP-ASN", "GEOIP"]
    private static let logicTypes: Set<String> = ["AND", "OR", "NOT"]
     
    private static let regexTypes: Set<String> = ["DOMAIN-REGEX", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX"]
    static let processTypes: Set<String> = ["PROCESS-NAME", "PROCESS-PATH", "PROCESS-NAME-REGEX", "PROCESS-PATH-REGEX",
                                            "PROCESS-NAME-WILDCARD", "PROCESS-PATH-WILDCARD"]

    private static func payloadIsRegex(_ type: String) -> Bool { regexTypes.contains(type) || type == "URL-REGEX" }

     
     
     
     
     
     
     
     
     
     
     
     
     
    static func isModuleRule(_ rule: String, policies: Set<String> = [], ruleSets: Set<String> = [],
                             platform: ModulePlatform = .current) -> Bool {
        guard isWithinTheBounds(rule) else { return false }
        let item = kernelFields(rule)
        guard item.count >= 3 else { return false }
        let type = item[0].uppercased()
         
         
        if type == "RULE-SET", ruleSets.contains(item[1]), item.dropFirst(3).allSatisfy({ kernelOptions.contains($0.lowercased()) }) {
            return kernelPolicy(item[2]) == item[2] || policies.contains(item[2])
        }
        if ["MATCH", "FINAL", "RULE-SET", "DOMAIN-SET", "SUB-RULE"].contains(type) { return false }
        guard processRulesAllowed(type, on: platform) else { return false }
        let targetIsLast = logicTypes.contains(type) || regexTypes.contains(type)
        let policy = targetIsLast ? item[item.count - 1] : item[2]
        guard kernelPolicy(policy) == policy || policies.contains(policy) else { return false }
        if logicTypes.contains(type) {
            return logicMembersAreModuleRules(item[1..<(item.count - 1)].joined(separator: ","), level: 1, platform: platform)
        }
        return true
    }

     
     
     
    private static func kernelFields(_ rule: String) -> [String] {
        let space = UInt8(ascii: " ")
        return Array(rule.utf8).split(separator: UInt8(ascii: ","), omittingEmptySubsequences: false).map { field in
            var first = field.startIndex, last = field.endIndex
            while first < last, field[first] == space { first += 1 }
            while last > first, field[last - 1] == space { last -= 1 }
            return String(decoding: field[first..<last], as: UTF8.self)
        }
    }

     
     
     
     
     
     
    private static func logicMembersAreModuleRules(_ payload: String, level: Int, platform: ModulePlatform) -> Bool {
        guard level <= maximumLogicDepth else { return false }
        let bytes = Array(payload.utf8)
        guard bytes.first == UInt8(ascii: "("), bytes.last == UInt8(ascii: ")") else { return false }
        var stack: [Int] = []
        var ranges: [(start: Int, end: Int)] = []
        for (index, byte) in bytes.enumerated() {
            if byte == UInt8(ascii: "(") {
                stack.append(index)
            } else if byte == UInt8(ascii: ")") {
                guard let start = stack.popLast() else { return false }
                ranges.append((start, index))
            }
        }
         
         
         
        guard stack.isEmpty, ranges.contains(where: { $0.start == 0 && $0.end == bytes.count - 1 }) else { return false }
        ranges.sort { $0.start < $1.start }
        var members: [(start: Int, end: Int)] = []
        for range in ranges where !(range.start == 0 && range.end == bytes.count - 1) {
            if members.contains(where: { $0.start < range.start && $0.end > range.end }) { continue }
            members.append(range)
        }
        for member in members {
            let text = String(decoding: bytes[(member.start + 1)..<member.end], as: UTF8.self)
            let item = kernelFields(text)
            let type = item[0].uppercased()
            if ["MATCH", "SUB-RULE", "RULE-SET", "DOMAIN-SET", ""].contains(type) { return false }
            guard processRulesAllowed(type, on: platform) else { return false }
            if logicTypes.contains(type),
               !logicMembersAreModuleRules(item.dropFirst().joined(separator: ","), level: level + 1, platform: platform) { return false }
        }
        return true
    }

     

     
     
    private indirect enum Member {
        case logic(String, [Member])
        case leaf(type: String, fields: [String])

         
        var readsTheRequest: Bool {
            switch self {
            case .logic(_, let members): return members.contains { $0.readsTheRequest }
            case .leaf(let type, _): return type == "URL-REGEX" || type == "USER-AGENT"
            }
        }

         
        var urlPatterns: [String] {
            switch self {
            case .logic(_, let members): return members.flatMap(\.urlPatterns)
            case .leaf(let type, let fields): return type == "URL-REGEX" ? [fields.joined(separator: ",")] : []
            }
        }
    }

     
     
     
    private static func members(_ type: String, _ payload: String, family: ModuleFormat,
                                level: Int) -> Result<Member, ModuleIgnoredReason> {
        guard level <= maximumLogicDepth, payload.hasPrefix("("), payload.hasSuffix(")") else { return .failure(.unreadableLine) }
        var members: [Member] = []
        for sub in fields(String(payload.dropFirst().dropLast()), unquoting: family != .stash) {
            guard sub.hasPrefix("("), sub.hasSuffix(")") else { return .failure(.unreadableLine) }
            let subField = fields(String(sub.dropFirst().dropLast()), unquoting: family != .stash)
            guard subField.count >= 2 else { return .failure(.unreadableLine) }
            let subType = subField[0].uppercased()
            if logicTypes.contains(subType) {
                switch Self.members(subType, subField[1], family: family, level: level + 1) {
                case .success(let member): members.append(member)
                case .failure(let reason): return .failure(reason)
                }
            } else {
                members.append(.leaf(type: subType, fields: Array(subField.dropFirst())))
            }
        }
        guard !members.isEmpty else { return .failure(.unreadableLine) }
        return .success(.logic(type, members))
    }

     
    private static func kernelText(_ node: Member, family: ModuleFormat,
                                   platform: ModulePlatform) -> Result<String, ModuleIgnoredReason> {
        func inner(_ member: Member) -> Result<String, ModuleIgnoredReason> {
            switch member {
            case .logic(let type, let members):
                var parts: [String] = []
                for member in members {
                    switch inner(member) {
                    case .success(let text): parts.append("(" + text + ")")
                    case .failure(let reason): return .failure(reason)
                    }
                }
                return .success(type + ",(" + parts.joined(separator: ",") + ")")
            case .leaf(let type, let fields):
                if regexTypes.contains(type) {
                    if processTypes.contains(type), platform != .mac { return .failure(.platformCannot(.processRules)) }
                    return .success(type + "," + fields.joined(separator: ","))
                }
                switch translate(type, fields[0], Array(fields.dropFirst()), family: family, platform: platform, inSubRule: true) {
                case .success(let condition):
                    return .success(([condition.type, condition.payload] + condition.params).joined(separator: ","))
                case .failure(let reason):
                    return .failure(reason)
                }
            }
        }
        return inner(node)
    }

     
     
     
    private static func engineCondition(_ node: Member) -> Result<ModuleRuleCondition, ModuleIgnoredReason> {
        switch node {
        case .logic(let type, let members):
            var conditions: [ModuleRuleCondition] = []
            for member in members {
                switch engineCondition(member) {
                case .success(let condition): conditions.append(condition)
                case .failure(let reason): return .failure(reason)
                }
            }
            switch type {
            case "AND": return .success(.and(conditions))
            case "OR": return .success(.or(conditions))
            default:
                guard conditions.count == 1 else { return .failure(.unreadableLine) }
                return .success(.not(conditions[0]))
            }
        case .leaf(let type, let fields):
            let value = fields[0]
            switch type {
            case "URL-REGEX":
                let pattern = fields.joined(separator: ",")
                guard ModuleLineSyntax.isValidPattern(pattern) else { return .failure(.invalidPattern) }
                return .success(.urlRegex(pattern))
            case "USER-AGENT":
                guard let agent = userAgent(value) else { return .failure(.unreadableLine) }
                return .success(.userAgent(agent))
            case "DOMAIN": return .success(.domain(value))
            case "DOMAIN-SUFFIX": return .success(.domainSuffix(withoutLeadingDot(value)))
            case "DOMAIN-KEYWORD": return .success(.domainKeyword(value))
            case "DOMAIN-WILDCARD":
                 
                if value.contains("["), let regex = domainRegex(fromGlob: value) { return .success(.domainRegex(regex)) }
                return .success(.domainWildcard(value))
            case "DOMAIN-REGEX":
                let pattern = fields.joined(separator: ",")
                guard ModuleLineSyntax.isValidPattern(pattern) else { return .failure(.invalidPattern) }
                return .success(.domainRegex(pattern))
            case "IP-CIDR", "IP-CIDR6": return .success(.ipCIDR(withPrefixLength(value)))
            case "DST-PORT", "DEST-PORT": return .success(.dstPort(kernelPorts(value)))
            case "NETWORK": return .success(.network(value.lowercased()))
            case "PROTOCOL":
                switch value.uppercased() {
                case "TCP": return .success(.network("tcp"))
                case "UDP": return .success(.network("udp"))
                case "QUIC": return .success(.and([.network("udp"), .dstPort("443")]))
                default: return .failure(.unsupportedRuleType("PROTOCOL," + value))
                }
            default:
                return .failure(.unsupportedRuleType(type))
            }
        }
    }

     
     
     
    private static func gate(_ condition: ModuleRuleCondition) -> String {
        switch condition {
        case .urlRegex(let pattern): return pattern
        case .and(let members):
            for member in members { if case .urlRegex(let pattern) = member { return pattern } }
            return ""
        default: return ""
        }
    }

     

    private struct Condition {
        var type: String
        var payload: String
        var params: [String]
    }

     
     
    private static func translate(_ type: String, _ payload: String, _ written: [String], family: ModuleFormat,
                                  platform: ModulePlatform, inSubRule: Bool = false) -> Result<Condition, ModuleIgnoredReason> {
         
         
         
         
         
        func plain(_ condition: Condition) -> Result<Condition, ModuleIgnoredReason> {
            let splits = [payload].contains { value in
                value.contains(",") || (inSubRule && (value.contains("(") || value.contains(")")))
            }
            return splits ? .failure(.unreadableLine) : .success(condition)
        }
         
         
        var params: [String] = []
        for option in written.map({ $0.lowercased() }) where kernelOptions.contains(option) && !params.contains(option) {
            params.append(option)
        }
        switch type {
        case "IP-CIDR", "IP-CIDR6":
             
            return plain(Condition(type: type, payload: withPrefixLength(payload), params: params))
        case "IP-SUFFIX":
            return plain(Condition(type: type, payload: payload, params: params))
        case "GEOIP", "IP-ASN":
             
             
             
             
            if payload.uppercased() == "UNKNOWN" { return .failure(.unsupportedRuleType(type + ",UNKNOWN")) }
             
            return plain(Condition(type: type, payload: type == "IP-ASN" ? withoutASPrefix(payload) : payload, params: params))
        case "SRC-IP", "SRC-IP-CIDR":
             
            return plain(Condition(type: "SRC-IP-CIDR", payload: withPrefixLength(payload), params: []))
        case "DEST-PORT", "DST-PORT":
            return plain(Condition(type: "DST-PORT", payload: kernelPorts(payload), params: []))
        case "SRC-PORT", "IN-PORT":
            return plain(Condition(type: type, payload: kernelPorts(payload), params: []))
        case "DOMAIN-WILDCARD":
             
             
             
            if payload.contains("["), let regex = domainRegex(fromGlob: payload) {
                return plain(Condition(type: "DOMAIN-REGEX", payload: regex, params: []))
            }
            return plain(Condition(type: type, payload: payload, params: []))
        case "DOMAIN-SUFFIX":
             
             
             
            return plain(Condition(type: type, payload: withoutLeadingDot(payload), params: []))
        case "DOMAIN", "DOMAIN-KEYWORD", "GEOSITE", "NETWORK":
            return plain(Condition(type: type, payload: payload, params: []))
        case "HOSTNAME-TYPE":
             
             
             
             
             
             
            let pattern: ModuleHostPattern
            switch payload.uppercased() {
            case "IPV4": pattern = .ipv4Address
            case "IPV6": pattern = .ipv6Address
            case "SIMPLE": pattern = .simpleHostname
            case "DOMAIN": return .success(Condition(type: "DOMAIN-WILDCARD", payload: "?*", params: []))
            default: return .failure(.unsupportedRuleType("HOSTNAME-TYPE," + payload))
            }
             
            let written = String(ModuleHostListEncoding.hostClause(pattern).simplified.rendered.dropFirst().dropLast())
            guard let comma = written.firstIndex(of: ",") else { return .failure(.unreadableLine) }
            return .success(Condition(type: String(written[..<comma]), payload: String(written[written.index(after: comma)...]), params: []))
        case "PROTOCOL":
            switch payload.uppercased() {
            case "TCP": return plain(Condition(type: "NETWORK", payload: "tcp", params: []))
            case "UDP": return plain(Condition(type: "NETWORK", payload: "udp", params: []))
             
            case "QUIC": return plain(Condition(type: "AND", payload: "((NETWORK,UDP),(DST-PORT,443))", params: []))
             
             
            case "HTTP", "HTTPS", "TLS", "STUN", "MTPROTO":
                return plain(Condition(type: "PROTOCOL", payload: payload.uppercased(), params: []))
            default: return .failure(.unsupportedRuleType("PROTOCOL," + payload))
            }
        case _ where processTypes.contains(type):
             
             
            guard platform == .mac else { return .failure(.platformCannot(.processRules)) }
            if type == "PROCESS-NAME" { return plain(processCondition(payload, family: family)) }
            return plain(Condition(type: type, payload: payload, params: []))
        case "DEVICE-NAME", "MAC-ADDRESS":
            return .failure(.platformCannot(.lanDeviceRules))
        case "CELLULAR-CARRIER":
            return .failure(.platformCannot(.carrierCode))
        case "SUBNET":
            return subnet(payload)
        case "CELLULAR-RADIO":
             
             
            return .failure(.unsupportedRuleType("CELLULAR-RADIO"))
        case "RULE-SET", "DOMAIN-SET":
            return .failure(.ruleListNotSupported)
        case _ where family == .stash && !["URL-REGEX", "USER-AGENT", "SCRIPT"].contains(type):
             
             
            return plain(Condition(type: type, payload: payload, params: params))
        default:
            return .failure(.unsupportedRuleType(type))
        }
    }

     
     
     
     
     
     
     
     
     
     
    private static func subnet(_ payload: String) -> Result<Condition, ModuleIgnoredReason> {
        let expression = payload.trimmingCharacters(in: .whitespaces)
        var kind = "", value = expression
        if let colon = expression.firstIndex(of: ":") {
            let prefix = expression[..<colon].trimmingCharacters(in: .whitespaces).uppercased()
            if ["TYPE", "ROUTER", "SSID", "BSSID", "MCCMNC"].contains(prefix) {
                kind = prefix
                value = expression[expression.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        guard !value.isEmpty, !value.contains(",") else { return .failure(.unreadableLine) }
        switch kind {
        case "TYPE":
            let type = value.uppercased()
            guard ["WIFI", "WIRED", "CELLULAR"].contains(type) else { return .failure(.unreadableLine) }
            return .success(Condition(type: "SUBNET", payload: "TYPE:" + type, params: []))
        case "ROUTER":
            guard ModuleIPLiteral(value) != nil else { return .failure(.unreadableLine) }
            return .success(Condition(type: "SUBNET", payload: "ROUTER:" + value, params: []))
        case "MCCMNC":
            return .failure(.platformCannot(.carrierCode))
        case "SSID", "BSSID":
            return .failure(.unsupportedRuleType("SUBNET," + kind))
        default:
            guard ModuleIPLiteral(value) != nil else { return .failure(.unsupportedRuleType("SUBNET,SSID")) }
            return .success(Condition(type: "SUBNET", payload: "ROUTER:" + value, params: []))
        }
    }

     
    static func withPrefixLength(_ address: String) -> String {
        guard !address.contains("/"), let literal = ModuleIPLiteral(address) else { return address }
        return address + (literal.isIPv6 ? "/128" : "/32")
    }

     
     
    static func withoutLeadingDot(_ suffix: String) -> String {
        guard suffix.hasPrefix("."), suffix.count > 1, !suffix.dropFirst().hasPrefix(".") else { return suffix }
        return String(suffix.dropFirst())
    }

     
    static func withoutASPrefix(_ value: String) -> String {
        guard value.count > 2, value.prefix(2).uppercased() == "AS", value.dropFirst(2).allSatisfy({ $0.isASCII && $0.isNumber })
        else { return value }
        return String(value.dropFirst(2))
    }

     
     
     
     
     
    static func kernelPorts(_ written: String) -> String {
        let text = written.trimmingCharacters(in: .whitespaces)
        for (comparison, range) in [(">=", { (n: Int) in n <= 65_535 ? "\(n)-65535" : nil }),
                                    ("<=", { (n: Int) in n <= 65_535 ? "0-\(n)" : nil }),
                                    (">", { (n: Int) in n < 65_535 ? "\(n + 1)-65535" : nil }),
                                    ("<", { (n: Int) in n > 0 && n <= 65_535 ? "0-\(n - 1)" : nil })] as [(String, (Int) -> String?)] {
            guard text.hasPrefix(comparison) else { continue }
            let digits = text.dropFirst(comparison.count).trimmingCharacters(in: .whitespaces)
            guard !digits.isEmpty, digits.count <= 5, digits.allSatisfy({ $0.isASCII && $0.isNumber }), let port = Int(digits),
                  let translated = range(port) else { return written }
            return translated
        }
        return written
    }

     
     
     
     
     
     
    static func domainRegex(fromGlob glob: String) -> String? {
        globRegex(glob, classes: true)
    }

     

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private static func processCondition(_ value: String, family: ModuleFormat) -> Condition {
        let isPath = value.hasPrefix("/")
        let exact = family == .surge || (family == .loon && isPath) ? "(?-i)" : ""
        if isPath, value.hasSuffix("/") {
            return Condition(type: "PROCESS-PATH-REGEX", payload: exact + "^" + literalRegex(value), params: [])
        }
        let classes = family == .loon
        guard value.contains("*") || value.contains("?") || (classes && value.contains("[")),
              var regex = globRegex(value, classes: classes) ?? globRegex(value, classes: false) else {
            return Condition(type: isPath ? "PROCESS-PATH" : "PROCESS-NAME", payload: value, params: [])
        }
         
        if value.allSatisfy({ $0 == "*" }) { regex = "^.+$" }
        return Condition(type: isPath ? "PROCESS-PATH-REGEX" : "PROCESS-NAME-REGEX", payload: exact + regex, params: [])
    }

     
     
     
    private static func processRulesAllowed(_ type: String, on platform: ModulePlatform) -> Bool {
        platform == .mac || !processTypes.contains(type)
    }

     
    private static func literalRegex(_ text: String) -> String {
        text.map { #"\^$.|+(){}[]*?"#.contains($0) ? "\\" + String($0) : String($0) }.joined()
    }

     
     
     
     
    private static func globRegex(_ glob: String, classes: Bool) -> String? {
        let characters = Array(glob)
        var out = "^"
        var index = 0
        while index < characters.count {
            let character = characters[index]
            switch character {
            case "*": out += ".*"
            case "?": out += "."
            case "[" where classes:
                var start = index + 1
                var negated = false
                if start < characters.count, characters[start] == "!" || characters[start] == "^" {
                    negated = true
                    start += 1
                }
                 
                let search = start < characters.count && characters[start] == "]" ? start + 1 : start
                guard search <= characters.count, let close = characters[search...].firstIndex(of: "]") else { return nil }
                let body = characters[start..<close].map { "\\[]".contains($0) ? "\\" + String($0) : String($0) }.joined()
                out += "[" + (negated ? "^" : "") + body + "]"
                index = close
            default:
                out += "\\^$.|+(){}[]".contains(character) ? "\\" + String(character) : String(character)
            }
            index += 1
        }
        return out + "$"
    }

     

     
     
     
     
     
     
     
     
     
     
     
     
    static func plainHTTPHosts(of pattern: String) -> [ModuleHostEntry] {
        var text = Substring(pattern)
        guard text.hasPrefix("^http:") else { return [] }
        text = text.dropFirst(6)
        if text.hasPrefix(#"\/\/"#) {
            text = text.dropFirst(4)
        } else if text.hasPrefix("//") {
            text = text.dropFirst(2)
        } else {
            return []
        }
        let host = hostPart(text)
        guard !host.isEmpty else { return [] }
        var port = ModuleHostPort.standard
        let after = text.dropFirst(host.count)
        if after.hasPrefix(":") {
            let digits = after.dropFirst().prefix { $0.isASCII && $0.isNumber }
            if let value = UInt16(digits), value != 0, value != ModuleHostList.forceHTTPStandardPort { port = .port(value) }
        }
        if let name = literalHost(host) {
            guard let entry = ModuleHostList.entry(name) else { return [] }
            return [ModuleHostEntry(excluded: false, pattern: entry.pattern, port: port)]
        }
        return hasLiteralLetter(host) ? [] : [ModuleHostEntry(excluded: false, pattern: .ipAddress, port: port)]
    }

     
     
     
     
     
     
     
     
    static func listingPlainHTTPHosts(_ ir: ModuleIR) -> ModuleIR {
        var out = ir
        var listed = Set(ir.forceHTTPEngineHostLines.flatMap(\.entries))
        func list(_ pattern: String, _ origin: ModuleLineOrigin) {
            let fresh = plainHTTPHosts(of: pattern).filter { listed.insert($0).inserted }
            if !fresh.isEmpty { out.forceHTTPEngineHostLines.append(ModuleHostListLine(directive: .append, entries: fresh, origin: origin)) }
        }
        for rule in ir.rewriteRules { list(rule.pattern, rule.origin) }
        for script in ir.scripts { list(script.pattern, script.origin) }
        return out
    }

     
     
     
    private static func hostPart(_ text: Substring) -> Substring {
        let characters = Array(text)
        var depth = 0
        var inClass = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                if !inClass, depth == 0, index + 1 < characters.count, characters[index + 1] == "/" { break }
                index += 2
                continue
            }
            if inClass {
                if character == "]" { inClass = false }
            } else if character == "[" {
                inClass = true
            } else if character == "(" {
                if depth == 0 {
                    let rest = String(characters[(index + 1)...].prefix(4))
                    if rest.hasPrefix(#"?:\/"#) || rest.hasPrefix(#"\/"#) || rest.hasPrefix("/") || rest.hasPrefix("?:/") { break }
                }
                depth += 1
            } else if character == ")" {
                depth -= 1
            } else if depth == 0, character == "/" || character == ":" || character == "$" {
                break
            }
            index += 1
        }
        return text.prefix(index)
    }

     
     
     
    private static func literalHost(_ part: Substring) -> String? {
        var out = ""
        var index = part.startIndex
        while index < part.endIndex {
            let character = part[index]
            if character == "\\" {
                let next = part.index(after: index)
                guard next < part.endIndex, part[next] == "." || part[next] == "-" else { return nil }
                out.append(part[next])
                index = part.index(after: next)
                continue
            }
            guard character.isASCII, character.isLetter || character.isNumber || character == "-" || character == "." else { return nil }
            out.append(character)
            index = part.index(after: index)
        }
        return out.isEmpty ? nil : out.lowercased()
    }

     
     
    private static func hasLiteralLetter(_ part: Substring) -> Bool {
        let characters = Array(part)
        var inClass = false
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character == "\\" {
                index += 2
                continue
            }
            if inClass {
                if character == "]" { inClass = false }
            } else if character == "[" {
                inClass = true
            } else if character.isASCII, character.isLetter {
                return true
            }
            index += 1
        }
        return false
    }
}

 
 
 
 
 
 
 
 
struct ModulePolicyCatalog: Equatable {
     
    var groups: [String] = []
    var groupTypes: [String: String] = [:]
     
    var nodes: Set<String> = []
     
    var matchTarget: String?
     
     
    var ruleProviders: [String] = []
    var proxyProviders: [String] = []
    var subRules: [String] = []



     
    func has(_ name: String) -> Bool { groupTypes[name] != nil || nodes.contains(name) }

     
     
     
     
     
     
    var defaultPolicy: String? {
        if let target = matchTarget, has(target) { return target }
        return groups.first { groupTypes[$0]?.lowercased() == "select" }
    }

     
     
     
     
     
     
    func resolve(_ policy: ModuleRulePolicy, choice: String?) -> String? {
        if let kernel = policy.kernelName { return kernel }
        if case .named(let name) = policy {
            if has(name) { return name }
             
             
            if let word = ModuleRuleMapping.rejectWord(in: name) { return ModuleRuleMapping.kernelPolicy(word) }
        }
        if let choice {
            if has(choice) { return choice }
            if let kernel = ModuleRuleMapping.kernelPolicy(choice), kernel == choice.uppercased() { return kernel }
        }
         
         
        if case .moduleChoice = policy, has("PROXY") { return "PROXY" }
        return defaultPolicy
    }

     
     
     
     
     
     
     
     
     
     
    func checkContext(forTarget target: String) -> String {
        let group = groupTypes[target] != nil
        let object: [String: Any] = ["proxies": !group && nodes.contains(target) ? [target] : [String](),
                                     "groups": group ? [target] : [String](),
                                     "ruleProviders": ruleProviders, "subRules": subRules, "section": "rules"]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

     
     
     
     
    func checkContext(targets: Set<String>) -> String {
        let nodes = targets.filter { groupTypes[$0] == nil && self.nodes.contains($0) }.sorted()
        let object: [String: Any] = ["proxies": nodes, "groups": groups, "proxyProviders": proxyProviders,
                                     "ruleProviders": ruleProviders, "subRules": subRules, "section": "rules"]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

     
     
     
    static func checkContext(_ context: String, place: Int) -> String {
        guard context.hasSuffix("}"), context.count > 2 else { return #"{"index":\#(place)}"# }
        return String(context.dropLast()) + #","index":\#(place)}"#
    }

     
    private static let sectionKeys: Set<String> = ["proxy-groups", "rule-providers", "proxy-providers", "sub-rules"]
     
     
     
    private static let namedSections = ["rule-providers", "proxy-providers", "sub-rules"]

     
     
     
     
     
     
     
     
     
     
    static func read(_ yaml: String, naming names: Set<String>, knownPolicies: Set<String>? = nil) -> ModulePolicyCatalog {
        var catalog = ModulePolicyCatalog()
        var text = yaml
         
         
        let cut = text.withUTF8 { TopLevelYAMLSections.sections(sectionKeys, inBytes: $0) }
        var groupList: [Any]?
        var named: [String: [String]] = [:]
        if let cut {
            if let section = cut.texts["proxy-groups"] {
                groupList = []
                if let json = try? ConfigTransforms.yamlToJSON(section, omitting: []),
                   let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
                    groupList = object["proxy-groups"] as? [Any] ?? []
                }
            } else if !cut.refused.contains("proxy-groups") {
                groupList = []
            }
            for key in namedSections {
                if let section = cut.texts[key] {
                    named[key] = mappingKeys(of: section, key: key)
                } else if !cut.refused.contains(key) {
                    named[key] = []
                }
            }
        }
         
         
         
        if groupList == nil || namedSections.contains(where: { named[$0] == nil }) {
            let omitted = ["proxies", "rules"] + namedSections.filter { named[$0] != nil }
                + (groupList == nil ? [] : ["proxy-groups"])
            let root = ((try? ConfigTransforms.foundationRoot(ofYAML: yaml, omitting: omitted)) ?? nil) ?? [:]
            if groupList == nil { groupList = root["proxy-groups"] as? [Any] ?? [] }
            for key in namedSections where named[key] == nil {
                named[key] = ((root[key] as? [String: Any]) ?? [:]).keys.sorted()
            }
        }
        for case let group as [String: Any] in groupList ?? [] {
            guard let name = (group["name"] as? String) ?? (group["name"] as? NSNumber)?.stringValue, !name.isEmpty,
                  catalog.groupTypes[name] == nil else { continue }
            catalog.groups.append(name)
            catalog.groupTypes[name] = group["type"] as? String ?? ""
        }
        catalog.ruleProviders = named["rule-providers"] ?? []
        catalog.proxyProviders = named["proxy-providers"] ?? []
        catalog.subRules = named["sub-rules"] ?? []
        catalog.matchTarget = cut.map { cut in
            cut.ranges["rules"].flatMap { range in text.withUTF8 { lastMatchTarget(inSection: UnsafeBufferPointer(rebasing: $0[range])) } }
                ?? (ConfigTransforms.ruleIndexPath(in: yaml) != nil ? PublishedRules.summary(ofPublishedText: yaml)?.matchTarget : nil)
        } ?? lastMatchTarget(in: yaml)
         
         
        let builtIns = ProfileRuntimeConfigBuilder.builtinPolicies
        let asked = names.union(catalog.matchTarget.map { [$0] } ?? []).filter {
            catalog.groupTypes[$0] == nil && !builtIns.contains($0) && ModuleRuleMapping.kernelPolicy($0) == nil
        }
        guard !asked.isEmpty else { return catalog }
        if let knownPolicies {
            catalog.nodes = knownPolicies.subtracting(builtIns)
            return catalog
        }
         
         
         
         
         
         
        if let cut, !mightName(asked, nodesIn: cut.ranges["proxies"], of: &text), ConfigTransforms.nodeLibraryPath(in: yaml) == nil {
            return catalog
        }


        if let known = ProfileRuntimeConfigBuilder.knownPolicies(in: yaml) {
            catalog.nodes = known.subtracting(builtIns)
        }
        return catalog
    }

     
     
     
     
     
     
    private static func mappingKeys(of section: String, key: String) -> [String] {
        func parsedWhole() -> [String] {
            guard let json = try? ConfigTransforms.yamlToJSON(section, omitting: []),
                  let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return [] }
            return ((object[key] as? [String: Any]) ?? [:]).keys.sorted()
        }
        var reduced = key + ":\n"
        var indent: Int?
        var first = true
        var whole = false
        section.enumerateLines { line, stop in
            defer { first = false }
            if first {
                 
                let value = line.drop { $0 != ":" }.dropFirst().trimmingCharacters(in: .whitespaces)
                if !value.isEmpty, !value.hasPrefix("#") { whole = true; stop = true }
                return
            }
            let body = line.drop { $0 == " " }
            let depth = line.count - body.count
            if body.isEmpty || body.hasPrefix("#") || body.allSatisfy({ $0 == " " || $0 == "\t" || $0 == "\r" }) { return }
            if indent == nil { indent = depth }
            guard depth == indent else {
                if depth < (indent ?? 0) { whole = true; stop = true }
                return
            }
            guard let keyText = mappingKey(body) else { whole = true; stop = true; return }
            reduced += "  " + keyText + #": null"# + "\n"
        }
        guard !whole, let json = try? ConfigTransforms.yamlToJSON(reduced, omitting: []),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return parsedWhole() }
        return ((object[key] as? [String: Any]) ?? [:]).keys.sorted()
    }

     
     
     
    private static func mappingKey(_ line: Substring) -> String? {
        guard let first = line.first, !"-?\t[{&*!|>%@`".contains(first) else { return nil }
        if first == "\"" || first == "'" {
            var index = line.index(after: line.startIndex)
            while index < line.endIndex {
                let character = line[index]
                if first == "\"", character == "\\" {
                    index = line.index(after: index)
                    if index < line.endIndex { index = line.index(after: index) }
                    continue
                }
                if character == first {
                    let next = line.index(after: index)
                    if first == "'", next < line.endIndex, line[next] == "'" {
                        index = line.index(after: next)
                        continue
                    }
                    let rest = line[next...].drop { $0 == " " }
                    guard rest.first == ":" else { return nil }
                    return String(line[...index])
                }
                index = line.index(after: index)
            }
            return nil
        }
        var index = line.startIndex
        while index < line.endIndex {
            if line[index] == ":" {
                let next = line.index(after: index)
                if next == line.endIndex || line[next] == " " || line[next] == "\r" {
                    let keyText = line[..<index].trimmingCharacters(in: .whitespaces)
                    return keyText.isEmpty || keyText.contains(" #") ? nil : keyText
                }
            }
            index = line.index(after: index)
        }
        return nil
    }

     
     
     
     
     
     
     
    private static func mightName(_ names: Set<String>, nodesIn range: Range<Int>?, of text: inout String) -> Bool {
        guard let range else { return false }
        return text.withUTF8 { whole in
            let section = UnsafeBufferPointer(rebasing: whole[range])
            guard let base = section.baseAddress, !section.isEmpty else { return false }
            func holds(_ needle: [UInt8]) -> Bool {
                guard !needle.isEmpty, needle.count <= section.count else { return false }
                return needle.withUnsafeBytes { memmem(base, section.count, $0.baseAddress, needle.count) != nil }
            }
            if holds(Array(#"\"#.utf8)) || holds(Array("''".utf8)) || holds(Array("<<".utf8)) { return true }
            if TopLevelYAMLSections.mentionsAnchorOrAlias(inBytes: section) { return true }
            return names.contains { holdsFolded(Array($0.utf8), in: section) }
        }
    }

     
     
    private static func holdsFolded(_ name: [UInt8], in section: UnsafeBufferPointer<UInt8>) -> Bool {
        func isBlank(_ byte: UInt8) -> Bool { byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D }
        let words = name.split(whereSeparator: isBlank).map(Array.init)
        guard let head = words.first, let base = section.baseAddress else { return false }
        var from = 0
        while from + head.count <= section.count,
              let hit = head.withUnsafeBytes({ memmem(base + from, section.count - from, $0.baseAddress, head.count) }) {
            let start = UnsafeRawPointer(base).distance(to: UnsafeRawPointer(hit))
            var at = start + head.count
            var matched = true
            for word in words.dropFirst() {
                let blanks = at
                while at < section.count, isBlank(section[at]) { at += 1 }
                guard at > blanks, at + word.count <= section.count,
                      memcmp(base + at, word, word.count) == 0 else { matched = false; break }
                at += word.count
            }
            if matched { return true }
            from = start + 1
        }
        return false
    }

     
     
     
     
    private static func lastMatchTarget(inSection section: UnsafeBufferPointer<UInt8>) -> String? {
        let document: String?
        if let layout = RuleLines.layout(section) {
            var end = layout.afterLastItem
            while end > layout.firstItem, section[end - 1] == 0x0A || section[end - 1] == 0x0D { end -= 1 }
            var start = end
            while start > layout.firstItem, section[start - 1] != 0x0A { start -= 1 }
             
            document = "rules:" + "\n" + String(decoding: UnsafeBufferPointer(rebasing: section[start..<end]), as: UTF8.self) + "\n"
        } else {
            document = section.count <= 4 << 20 ? String(decoding: section, as: UTF8.self) : nil
        }
        return document.flatMap(matchTarget(ofRulesDocument:))
    }

     
     
    private static func lastMatchTarget(in yaml: String) -> String? {
        var text = yaml
        return text.withUTF8 { bytes in
            guard let range = TopLevelYAMLSections.sectionRange("rules", inBytes: bytes) else { return nil }
            return lastMatchTarget(inSection: UnsafeBufferPointer(rebasing: bytes[range]))
        }
    }

    private static func matchTarget(ofRulesDocument document: String) -> String? {
        guard let json = try? ConfigTransforms.yamlToJSON(document, omitting: []),
              let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let rule = (root["rules"] as? [Any])?.last as? String else { return nil }
        let fields = rule.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        guard fields.count >= 2, fields[0].uppercased() == "MATCH", !fields[1].isEmpty else { return nil }
        return fields[1]
    }
}

private extension Array where Element: Hashable {
     
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
