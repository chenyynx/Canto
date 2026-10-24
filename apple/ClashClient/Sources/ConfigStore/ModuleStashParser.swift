import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleStashParser {
     
     
     
     
    private static let known: Set<String> = ["name", "desc", "author", "icon", "rules", "http", "cron", "tiles", "script-providers", "rule-providers",
                                             "openUrl", "homepage", "category", "date", "version",
                                             "arguments", "arguments-version"]

     
     
     
     
     
     
     
    struct Arguments {
         
        var defaults: [String: OrderedJSON?] = [:]
         
        var overLimit = false
         
         
        private var bounds: [String: (integer: Bool, maxLength: Int?)] = [:]

        init(_ value: OrderedJSON?) {
            guard case .object(let declared)? = value else { return }
            for (name, declaration) in declared {
                 
                var given: OrderedJSON?
                if case .object(let fields) = declaration { given = fields.first { $0.key == "default" }?.value }
                let size = name.utf8.count + 1 + (given.map { ModuleStashParser.scalar($0) ?? $0.serialized() }?.utf8.count ?? 0)
                guard defaults.count < ModuleParser.maximumArguments, size <= ModuleParser.maximumArgumentBytes else {
                    overLimit = true
                    continue
                }
                guard case .object(let fields) = declaration else {
                    defaults[name] = .some(nil)
                    continue
                }
                let type = ModuleStashParser.scalar(fields.first { $0.key == "type" }?.value)?.lowercased()
                bounds[name] = (ModuleStashParser.scalar(fields.first { $0.key == "value-type" }?.value)?.lowercased() == "integer",
                                ModuleStashParser.scalar(fields.first { $0.key == "max-length" }?.value).flatMap { Int($0) })
                switch fields.first(where: { $0.key == "default" })?.value {
                case .some(.scalar("null")), nil:
                    let fallback: OrderedJSON? = type == "switch" ? .scalar("false") : (type == "input" ? .string("") : nil)
                    defaults[name] = .some(fallback)
                case .some(let given):
                     
                     
                    let text = ModuleStashParser.scalar(given) ?? given.serialized()
                    defaults[name] = text.contains("${args.") || text.contains("{{{") ? .some(nil) : .some(given)
                }
            }
        }

         
         
        func fill(_ value: OrderedJSON) -> Result<OrderedJSON, ModuleIgnoredReason> {
            switch value {
            case .string(let text): return fill(text).map(OrderedJSON.string)
            case .scalar: return .success(value)
            case .array(let items):
                var out: [OrderedJSON] = []
                for item in items {
                    switch fill(item) {
                    case .success(let filled): out.append(filled)
                    case .failure(let reason): return .failure(reason)
                    }
                }
                return .success(.array(out))
            case .object(let pairs):
                var out: [(key: String, value: OrderedJSON)] = []
                for pair in pairs {
                    switch fill(pair.value) {
                    case .success(let filled): out.append((pair.key, filled))
                    case .failure(let reason): return .failure(reason)
                    }
                }
                return .success(.object(out))
            }
        }

         
         
         
         
        mutating func apply(_ values: [String: String]) {
            for (name, value) in values where defaults[name] != nil {
                 
                if let bound = bounds[name], (bound.maxLength.map { value.count > $0 } ?? false) || (bound.integer && Int(value) == nil) {
                    defaults[name] = .some(nil)
                    continue
                }
                let lowered = value.lowercased()
                if case .some(.scalar)? = defaults[name], lowered == "true" || lowered == "false" || Double(value)?.isFinite == true {
                    defaults[name] = .some(.scalar(lowered == "true" || lowered == "false" ? lowered : value))
                } else {
                    defaults[name] = .some(.string(value))
                }
            }
        }

        var declared: [ModuleArgument] {
            defaults.keys.sorted().map { name in
                ModuleArgument(name: name, defaultValue: defaults[name].flatMap { ModuleStashParser.scalar($0) })
            }
        }

        private static let reference = try! NSRegularExpression(pattern: #"\$?\$\{args\.([^{}|\s]+)(\|json)?\}"#)

         
         
         
        func fill(_ text: String) -> Result<String, ModuleIgnoredReason> {
            var out = text
             
             
            var unread = text
            var escaped = 0
            if text.contains("${args.") {
                let whole = NSRange(text.startIndex..., in: text)
                for match in Self.reference.matches(in: text, range: whole).reversed() {
                    if let range = Range(match.range, in: unread) { unread.removeSubrange(range) }
                    guard let range = Range(match.range, in: out), let nameRange = Range(match.range(at: 1), in: text) else { continue }
                    if text[range].hasPrefix("$$") {
                        out.replaceSubrange(range, with: String(text[range].dropFirst()))
                        escaped += 1
                        continue
                    }
                    let name = String(text[nameRange])
                    guard let declared = defaults[name], let value = declared else { return .failure(.missingArgument(name)) }
                    let asJSON = match.range(at: 2).location != NSNotFound
                    let written: String
                    switch value {
                    case .string(let string): written = asJSON ? OrderedJSON.string(string).serialized() : string
                    case .scalar(let token): written = token
                    default: return .failure(.missingArgument(name))
                    }
                    out.replaceSubrange(range, with: written)
                }
            }
            if let open = out.range(of: "{{{") {
                let close = out.range(of: "}}}", range: open.upperBound..<out.endIndex)?.lowerBound ?? out.endIndex
                return .failure(.missingArgument(String(out[open.upperBound..<close])))
            }
             
             
            if let reference = unread.range(of: "${args.") {
                return .failure(.missingArgument(String(unread[reference.upperBound...].prefix { !"}| ".contains($0) })))
            }
             
             
            if out.components(separatedBy: "${args.").count - 1 > escaped, let reference = out.range(of: "${args.") {
                return .failure(.missingArgument(String(out[reference.upperBound...].prefix { !"}| ".contains($0) })))
            }
            return .success(out)
        }
    }

     
    static func parse(_ text: String, manifest base: ModuleManifest, platform: ModulePlatform = .current,
                      argumentValues: [String: String] = [:],
                      check: ModuleRuleMapping.Check = ModuleRuleMapping.kernelCheck) throws -> Result<ModuleIR, ModuleRefusal> {
        let tree: OrderedJSON
        do {
            tree = try OrderedJSON.parse(try ConfigTransforms.yamlToJSON(text))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
             
             
            return .failure(.unreadableYAML(ModuleParser.prefix(error.localizedDescription, bytes: ModuleParser.maximumShownBytes)))
        }
        guard case .object(let root) = tree else { return .failure(.notAModule) }
        func value(_ key: String) -> OrderedJSON? { root.first { $0.key == key }?.value }

        var manifest = base
        manifest.format = .stash
         
         
        var longHeaders: [String] = []
        func header(_ key: String) -> String? {
            guard let text = scalar(value(key)) else { return nil }
            let cut = ModuleParser.prefix(text, bytes: key == "desc" ? ModuleParser.maximumDescriptionBytes
                                                                            : ModuleParser.maximumArgumentBytes)
            if cut.utf8.count < text.utf8.count { longHeaders.append(key) }
            return cut
        }
        manifest.name = header("name")
        manifest.desc = header("desc")
        manifest.author = header("author")
        manifest.icon = header("icon")
         
         
        manifest.category = header("category")
        manifest.openURL = header("openUrl")
        manifest.homepage = header("homepage")
        manifest.date = header("date")
        manifest.version = header("version")
        var arguments = Arguments(value("arguments"))
         
        manifest.arguments = arguments.declared
        arguments.apply(argumentValues)
        var ir = ModuleIR.empty(manifest)
        for key in longHeaders {
            ir.ignored.append(ModuleIgnoredEntry(text: key, reason: .headerOverLimit, origin: ModuleLineOrigin(section: key, line: 0)))
        }
        if arguments.overLimit {
            ir.ignored.append(ModuleIgnoredEntry(text: "arguments", reason: .argumentsOverLimit,
                                                  origin: ModuleLineOrigin(section: "arguments", line: 0)))
        }

         
         
         
         
        var providerNames: Set<String> = []
        if let given = value("rule-providers") {
            let origin = ModuleLineOrigin(section: "rule-providers", line: 0)
            switch arguments.fill(given) {
            case .success(.object(let pairs)):
                for (index, pair) in pairs.enumerated() {
                    let at = ModuleLineOrigin(section: "rule-providers", line: index + 1)
                    switch ModuleRuleSetSyntax.stashProvider(pair.key, pair.value, origin: at) {
                    case .success(let set):
                        ModuleRuleSetSyntax.add(set, to: &ir.ruleSets)
                        providerNames.insert(pair.key)
                    case .failure(let reason):
                        ir.ignored.append(ModuleIgnoredEntry(text: pair.key, reason: reason, origin: at))
                    }
                }
            case .success(let other):
                ir.ignored.append(ModuleIgnoredEntry(text: other.serialized(), reason: .unreadableLine, origin: origin))
            case .failure(let reason):
                ir.ignored.append(ModuleIgnoredEntry(text: "rule-providers", reason: reason, origin: origin))
            }
        }
         
         
         
        let directives = Self.directives(in: text)
        for (key, written) in root where !known.contains(key) {
            let origin = ModuleLineOrigin(section: key, line: 0)
            guard ModuleSettingsMapping.stashKeys.contains(key) || ModuleSettingsMapping.stashMisplacedKeys.contains(key) else {
                ir.ignored.append(ModuleIgnoredEntry(text: key, reason: .sectionNotSupported(key), origin: origin))
                continue
            }
            switch arguments.fill(written) {
            case .success(let filled):
                ModuleSettingsMapping.take(ModuleSettingsMapping.stash(key, value: filled, directives: directives, origin: origin,
                                                                         ruleProviders: providerNames),
                                            written: key, origin: origin, key: key, into: &ir)
            case .failure(let reason):
                ir.ignored.append(ModuleIgnoredEntry(text: key, reason: reason, origin: origin))
            }
        }
         
         
         
         
         
         
         
        let appended = directives[["rules"]] == .append
        if let rules = value("rules") {
            for (index, item) in listItems(rules, section: "rules", into: &ir.ignored).enumerated() {
                let origin = ModuleLineOrigin(section: "rules", line: index + 1)
                guard let written = item.text else {
                    ir.ignored.append(ModuleIgnoredEntry(text: item.shown, reason: .unreadableLine, origin: origin))
                    continue
                }
                let line: String
                switch arguments.fill(written) {
                case .success(let filled): line = filled
                case .failure(let reason):
                    ir.ignored.append(ModuleIgnoredEntry(text: written, reason: reason, origin: origin))
                    continue
                }
                 
                var mapped = try ModuleRuleMapping.map(line, family: .stash, platform: platform, origin: origin, check: check)
                if appended {
                    switch mapped.outcome {
                    case .kernel(var rule):
                        rule.appended = true
                        mapped.outcome = .kernel(rule)
                    case .rewrite, .engine:
                         
                         
                         
                        mapped.outcome = .ignored(.settingNotSupported(#"rules: #!append"#))
                    case .ruleSet, .ignored:
                        break
                    }
                }
                let before = ir.routingRules.count
                ModuleRuleMapping.take(mapped, written: line, origin: origin, into: &ir)
                 
                if appended, case .ruleSet = mapped.outcome {
                    for index in before..<ir.routingRules.count { ir.routingRules[index].appended = true }
                }
            }
        }
         
         
        for index in ir.ruleSets.indices where ir.ruleSets[index].name != nil {
            if let rule = ir.routingRules.first(where: { $0.head == ir.ruleSets[index].reference }) { ir.ruleSets[index].policy = rule.policy }
        }
        var providers: [(key: String, value: OrderedJSON)] = []
        if let given = value("script-providers") {
            if case .object(let pairs) = given {
                providers = pairs
            } else {
                ir.ignored.append(ModuleIgnoredEntry(text: given.serialized(), reason: .unreadableLine,
                                                      origin: ModuleLineOrigin(section: "script-providers", line: 0)))
            }
        }
         
         
        if let given = value("cron") {
            if case .object(let cron) = given {
                for (key, list) in cron {
                    let section = "cron." + key
                    guard key == "script" else {
                        ir.ignored.append(ModuleIgnoredEntry(text: section, reason: .settingNotSupported(section),
                                                             origin: ModuleLineOrigin(section: section, line: 0)))
                        continue
                    }
                    scripts(listItems(list, section: section, into: &ir.ignored), providers: providers, section: section,
                            arguments: arguments, into: &ir)
                }
            } else {
                ir.ignored.append(ModuleIgnoredEntry(text: given.serialized(), reason: .unreadableLine,
                                                     origin: ModuleLineOrigin(section: "cron", line: 0)))
            }
        }
         
         
         
         
        if let given = value("tiles") {
            tiles(listItems(given, section: "tiles", into: &ir.ignored), providers: providers, arguments: arguments, into: &ir)
        }
        if let given = value("http") {
            guard case .object(let http) = given else {
                ir.ignored.append(ModuleIgnoredEntry(text: given.serialized(), reason: .unreadableLine,
                                                      origin: ModuleLineOrigin(section: "http", line: 0)))
                return .success(ir)
            }
            for (key, list) in http {
                let section = "http." + key
                switch key {
                case "mitm", "force-http-engine", "rewrite", "url-rewrite", "header-rewrite", "body-rewrite", "script", "mock":
                    break
                default:
                    ir.ignored.append(ModuleIgnoredEntry(text: section, reason: .settingNotSupported(section),
                                                          origin: ModuleLineOrigin(section: section, line: 0)))
                    continue
                }
                let items = listItems(list, section: section, into: &ir.ignored)
                 
                 
                let directive: ModuleHostListDirective
                switch directives[["http", key]] {
                case .append?: directive = .append
                case .replace?: directive = .replace
                default: directive = .insert
                }
                switch key {
                case "mitm":
                    ir.mitmHostLines.append(hostLine(items, section: section, directive: directive, arguments: arguments,
                                                     ignored: &ir.ignored))
                case "force-http-engine":
                    ir.forceHTTPEngineHostLines.append(hostLine(items, section: section, directive: directive, arguments: arguments,
                                                                ignored: &ir.ignored))
                case "rewrite", "url-rewrite":
                    keep(items, section: section, arguments: arguments, into: &ir, ModuleLineSyntax.urlRewrite)
                case "header-rewrite":
                    keep(items, section: section, arguments: arguments, into: &ir, ModuleLineSyntax.headerRewrite)
                case "body-rewrite":
                    let moduleURL = ir.manifest.sourceURL
                    keepReadings(items, section: section, arguments: arguments, into: &ir) {
                        ModuleLineSyntax.bodyRewriteReading($0, origin: $1, moduleURL: moduleURL)
                    }
                case "mock":
                    mocks(items, section: section, arguments: arguments, into: &ir)
                default:
                    scripts(items, providers: providers, section: section, arguments: arguments, into: &ir)
                }
            }
        }
        return .success(ir)
    }

     
     
    static func scalar(_ value: OrderedJSON?) -> String? {
        switch value {
        case .string(let text): return text
        case .scalar(let token): return token == "null" ? nil : token
        default: return nil
        }
    }

     
    private struct Item {
        var text: String?
        var shown: String
        var json: OrderedJSON
    }

     
     
    private static func listItems(_ value: OrderedJSON, section: String, into ignored: inout [ModuleIgnoredEntry]) -> [Item] {
        guard case .array(let items) = value else {
            ignored.append(ModuleIgnoredEntry(text: value.serialized(), reason: .unreadableLine,
                                               origin: ModuleLineOrigin(section: section, line: 0)))
            return []
        }
        return items.map { Item(text: scalar($0), shown: $0.serialized(), json: $0) }
    }

    private static func hostLine(_ items: [Item], section: String, directive: ModuleHostListDirective, arguments: Arguments,
                                 ignored: inout [ModuleIgnoredEntry]) -> ModuleHostListLine {
        var entries: [ModuleHostEntry] = []
        for (index, item) in items.enumerated() {
            let origin = ModuleLineOrigin(section: section, line: index + 1)
            guard let written = item.text else {
                ignored.append(ModuleIgnoredEntry(text: item.shown, reason: .unreadableLine, origin: origin))
                continue
            }
            let text: String
            switch arguments.fill(written) {
            case .success(let filled): text = filled
            case .failure(let reason):
                ignored.append(ModuleIgnoredEntry(text: written, reason: reason, origin: origin))
                continue
            }
            if let entry = ModuleHostList.entry(text) {
                entries.append(entry)
            } else {
                ignored.append(ModuleIgnoredEntry(text: text, reason: .invalidHost(text), origin: origin))
            }
        }
        return ModuleHostListLine(directive: directive, entries: entries, origin: ModuleLineOrigin(section: section, line: 0))
    }

     
     
     
     
    static func directives(in text: String) -> [[String]: ModuleEditOperation] {
        var out: [[String]: ModuleEditOperation] = [:]
        var stack: [(indent: Int, key: String)] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed == "---" { continue }
            let indent = line.prefix { $0 == " " }.count
            while let last = stack.last, last.indent >= indent { stack.removeLast() }
             
            if trimmed.hasPrefix("-") {
                stack.append((indent, "-"))
                continue
            }
            guard let colon = keyColon(in: trimmed) else { continue }
            var key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
            if key.count >= 2, let first = key.first, first == "\"" || first == "'", key.last == first { key = String(key.dropFirst().dropLast()) }
            stack.append((indent, key))
            let rest = trimmed[trimmed.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if stack.dropLast().contains(where: { $0.key == "-" }) { continue }
            if rest.hasPrefix("#!append") {
                out[stack.map(\.key)] = .append
            } else if rest.hasPrefix("#!replace") {
                out[stack.map(\.key)] = .replace
            }
        }
        return out
    }

     
     
    private static func keyColon(in line: String) -> String.Index? {
        var index = line.startIndex
        var quote: Character?
        if let first = line.first, first == "\"" || first == "'" {
            quote = first
            index = line.index(after: index)
        }
        while index < line.endIndex {
            let character = line[index]
            let next = line.index(after: index)
            if let open = quote {
                if character == open { quote = nil }
            } else if character == ":", next == line.endIndex || line[next] == " " || line[next] == "\t" {
                return index
            }
            index = next
        }
        return nil
    }

    private static func keep(_ items: [Item], section: String, arguments: Arguments, into ir: inout ModuleIR,
                             _ read: (String, ModuleLineOrigin) -> Result<ModuleRewriteRule, ModuleIgnoredReason>) {
        for (index, item) in items.enumerated() {
            let origin = ModuleLineOrigin(section: section, line: index + 1)
            guard let text = item.text else {
                ir.ignored.append(ModuleIgnoredEntry(text: item.shown, reason: .unreadableLine, origin: origin))
                continue
            }
            switch arguments.fill(text).flatMap({ read($0, origin) }) {
            case .success(let rule): ir.rewriteRules.append(rule)
            case .failure(let reason): ir.ignored.append(ModuleIgnoredEntry(text: text, reason: reason, origin: origin))
            }
        }
    }

     
     
    private static func keepReadings(_ items: [Item], section: String, arguments: Arguments, into ir: inout ModuleIR,
                                     _ read: (String, ModuleLineOrigin) -> Result<ModuleLineSyntax.Reading, ModuleIgnoredReason>) {
        for (index, item) in items.enumerated() {
            let origin = ModuleLineOrigin(section: section, line: index + 1)
            guard let text = item.text else {
                ir.ignored.append(ModuleIgnoredEntry(text: item.shown, reason: .unreadableLine, origin: origin))
                continue
            }
            switch arguments.fill(text).flatMap({ read($0, origin) }) {
            case .success(let reading):
                ir.rewriteRules += reading.rules
                ir.answerFiles += reading.files
            case .failure(let reason): ir.ignored.append(ModuleIgnoredEntry(text: text, reason: reason, origin: origin))
            }
        }
    }

     
     
     
    private static func mocks(_ items: [Item], section: String, arguments: Arguments, into ir: inout ModuleIR) {
        for (index, item) in items.enumerated() {
            let origin = ModuleLineOrigin(section: section, line: index + 1)
            var shown = item.shown
            if case .object(let pairs) = item.json, let match = scalar(pairs.first(where: { $0.key == "match" })?.value) { shown = match }
            switch ModuleLocalAnswerSyntax.stashMock(item.json, origin: origin, fill: arguments.fill) {
            case .success(let read):
                ir.rewriteRules.append(read.rule)
                for note in read.notes { ir.ignored.append(ModuleIgnoredEntry(text: shown, reason: note, origin: origin)) }
            case .failure(let reason):
                ir.ignored.append(ModuleIgnoredEntry(text: shown, reason: reason, origin: origin))
            }
        }
    }

     
     
     
     
     
     
     
    private static func tiles(_ items: [Item], providers: [(key: String, value: OrderedJSON)], arguments: Arguments,
                              into ir: inout ModuleIR) {
        for (index, item) in items.enumerated() {
            let origin = ModuleLineOrigin(section: "tiles", line: index + 1)
            guard case .object(let pairs) = item.json else {
                ir.ignored.append(ModuleIgnoredEntry(text: item.shown, reason: .unreadableLine, origin: origin))
                continue
            }
            var unfilled: ModuleIgnoredReason?
            func field(_ key: String) -> String? {
                guard let text = scalar(pairs.first { $0.key == key }?.value) else { return nil }
                switch arguments.fill(text) {
                case .success(let value): return value.isEmpty ? nil : value
                case .failure(let reason):
                    unfilled = unfilled ?? reason
                    return nil
                }
            }
            let name = scalar(pairs.first { $0.key == "name" }?.value) ?? ""
            guard !name.isEmpty else {
                ir.ignored.append(ModuleIgnoredEntry(text: item.shown, reason: .unreadableLine, origin: origin))
                continue
            }
            var panel = ModulePanel(name: name, origin: origin)
            panel.title = field("title")
            panel.content = field("content")
            panel.icon = field("icon").flatMap { $0.contains("://") ? nil : $0 }
            panel.iconColor = field("backgroundColor")
            panel.updateInterval = field("interval").flatMap { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
            var provider: [(key: String, value: OrderedJSON)] = []
            if case .object(let found)? = providers.first(where: { $0.key == name })?.value { provider = found }
            if let path = scalar(provider.first { $0.key == "url" }?.value) {
                var parameters: [(key: String, value: String)] = [(key: "type", value: "generic"), (key: "script-path", value: path)]
                for key in ["timeout", "argument"] {
                    if let value = field(key) { parameters.append((key: key, value: value)) }
                }
                if let interval = scalar(provider.first { $0.key == "interval" }?.value) {
                    parameters.append((key: "script-update-interval", value: interval))
                }
                if unfilled == nil {
                    switch ModuleLineSyntax.script(name: name, parameters: parameters, origin: origin) {
                    case .success(.app(let script)):
                        ir.appScripts.append(script)
                        panel.scriptName = name
                    case .success:
                        ir.ignored.append(ModuleIgnoredEntry(text: name, reason: .unreadableLine, origin: origin))
                        continue
                    case .failure(let reason):
                        ir.ignored.append(ModuleIgnoredEntry(text: name, reason: reason, origin: origin))
                        continue
                    }
                }
            }
            if let unfilled {
                ir.ignored.append(ModuleIgnoredEntry(text: name, reason: unfilled, origin: origin))
                continue
            }
            guard panel.title != nil || panel.content != nil || panel.scriptName != nil else {
                ir.ignored.append(ModuleIgnoredEntry(text: item.shown, reason: .unreadableLine, origin: origin))
                continue
            }
            ir.panels.append(panel)
        }
    }

     
     
     
     
     
    private static func scripts(_ items: [Item], providers: [(key: String, value: OrderedJSON)], section: String,
                                arguments: Arguments, into ir: inout ModuleIR) {
        let scheduled = section == "cron.script"
        for (index, item) in items.enumerated() {
            let origin = ModuleLineOrigin(section: section, line: index + 1)
            guard case .object(let pairs) = item.json else {
                ir.ignored.append(ModuleIgnoredEntry(text: item.shown, reason: .unreadableLine, origin: origin))
                continue
            }
            func field(_ key: String) -> OrderedJSON? { pairs.first { $0.key == key }?.value }
            let name = scalar(field("name")) ?? ""
            var provider: [(key: String, value: OrderedJSON)] = []
            if case .object(let found)? = providers.first(where: { $0.key == name })?.value { provider = found }
            func providerField(_ key: String) -> String? { scalar(provider.first { $0.key == key }?.value) }
            var parameters: [(key: String, value: String)] = scheduled ? [
                (key: "type", value: "cron"),
                (key: "cronexp", value: scalar(field("cron")) ?? ""),
                (key: "script-path", value: providerField("url") ?? ""),
            ] : [
                (key: "type", value: "http-" + (scalar(field("type")) ?? "")),
                (key: "pattern", value: scalar(field("match")) ?? ""),
                (key: "script-path", value: providerField("url") ?? ""),
            ]
             
            for key in ["require-body", "requires-body", "binary-mode", "max-size", "timeout", "argument"] {
                if let value = scalar(field(key)) { parameters.append((key: key, value: value)) }
            }
            if let interval = providerField("interval") {
                parameters.append((key: "script-update-interval", value: interval))
            }
            var filled: [(key: String, value: String)] = []
            var unfilled: ModuleIgnoredReason?
            for parameter in parameters where unfilled == nil {
                switch arguments.fill(parameter.value) {
                case .success(let value): filled.append((key: parameter.key, value: value))
                case .failure(let reason): unfilled = reason
                }
            }
            if let unfilled {
                ir.ignored.append(ModuleIgnoredEntry(text: scalar(field("match")) ?? name, reason: unfilled, origin: origin))
                continue
            }
            switch ModuleLineSyntax.script(name: name, parameters: filled, origin: origin) {
            case .success(.http(let script)) where !scheduled: ir.scripts.append(script)
            case .success(.app(let script)) where scheduled: ir.appScripts.append(script)
            case .success:
                 
                ir.ignored.append(ModuleIgnoredEntry(text: name, reason: .unreadableLine, origin: origin))
            case .failure(let reason):
                ir.ignored.append(ModuleIgnoredEntry(text: scalar(field("match")) ?? name, reason: reason, origin: origin))
            }
        }
    }
}
