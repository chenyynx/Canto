import ClashClientKit
import Foundation

 
 
 
 
 
 
enum ModuleHostMappingSyntax {
     
     
    static let tunnelKnowsTheWiFiName = false

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func line(_ line: String, origin: ModuleLineOrigin) -> Result<ModuleHostMapping, ModuleIgnoredReason> {
        guard let equals = line.firstIndex(of: "=") else { return .failure(.unreadableLine) }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !value.isEmpty, ModuleYAMLText.isOneLine(line) else { return .failure(.unreadableLine) }
         
        while let comma = value.lastIndex(of: ",") {
            let option = value[value.index(after: comma)...].trimmingCharacters(in: .whitespaces).lowercased()
            guard option.hasPrefix("use-in-proxy=") else { break }
            value = value[..<comma].trimmingCharacters(in: .whitespaces)
        }
        let lowered = key.lowercased()
        if lowered.hasPrefix("ssid:") {
            let name = String(key.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty else { return .failure(.unreadableLine) }
            let mapping: ModuleHostMapping
            switch target(value) {
            case .success(.dnsServers(let servers)):
                mapping = ModuleHostMapping(pattern: "ssid:" + name, value: .dnsServers(servers), origin: origin)
            case .success(.systemDNS):
                mapping = ModuleHostMapping(pattern: "ssid:" + name, value: .dnsServers(["system"]), origin: origin)
            default:
                return .failure(.unreadableLine)
            }
            return tunnelKnowsTheWiFiName ? .success(mapping) : .failure(.settingNotSupported("ssid"))
        }
        if lowered.hasPrefix("domain-set:") || lowered.hasPrefix("rule-set:") || isGlob(key) {
             
             
            return setLine(line, origin: origin)?.map { $0.mapping } ?? .failure(.unreadableLine)
        }
        if ModuleIPLiteral(key) != nil || (key.contains(":") && ModuleIPLiteral(key.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))) != nil) {
            return .failure(.noEffectInItsOwnApp(.noEffectThereEither))
        }
        guard let pattern = kernelPattern(key) else { return .failure(.invalidHost(key)) }
        return target(value).map { ModuleHostMapping(pattern: pattern, value: $0, origin: origin) }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func setLine(_ line: String, origin: ModuleLineOrigin) -> Result<(mapping: ModuleHostMapping, set: ModuleRuleSet), ModuleIgnoredReason>? {
        guard let equals = line.firstIndex(of: "=") else { return nil }
        let key = line[..<equals].trimmingCharacters(in: .whitespaces)
        var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        while let comma = value.lastIndex(of: ",") {
            let option = value[value.index(after: comma)...].trimmingCharacters(in: .whitespaces).lowercased()
            guard option.hasPrefix("use-in-proxy=") else { break }
            value = value[..<comma].trimmingCharacters(in: .whitespaces)
        }
        let lowered = key.lowercased()
        var set: ModuleRuleSet
        var isGlobSet = false
        if lowered.hasPrefix("domain-set:") || lowered.hasPrefix("rule-set:") {
            let domainSet = lowered.hasPrefix("domain-set:")
            let address = String(key.dropFirst(domainSet ? "domain-set:".count : "rule-set:".count)).trimmingCharacters(in: .whitespaces)
            guard ModuleRuleSetSyntax.isAddress(address) else {
                return .failure(address.isEmpty ? .unreadableLine : .platformCannot(.remoteRelativeFile))
            }
            set = ModuleRuleSet(url: address, inline: nil, kind: domainSet ? .domainSet : .classical, policy: .builtIn("DIRECT"),
                                 params: [], interval: nil, origin: origin)
        } else if isGlob(key) {
            guard let rule = surgeGlobRule(key) else { return .failure(.invalidHost(key)) }
            isGlobSet = true
            set = ModuleRuleSet(url: nil, inline: [rule], kind: .provider(behavior: "classical", format: "inline"),
                                 policy: .builtIn("DIRECT"), params: [], interval: nil, origin: origin)
        } else {
            return nil
        }
        guard !value.isEmpty else { return .failure(.unreadableLine) }
        let servers: [String]
        switch target(value) {
        case .success(.dnsServers(let written)): servers = written
        case .success(.systemDNS): servers = ["system"]
        case .success:
             
             
            return .failure(.waitingForKernel("hosts"))
        case .failure(let reason):
            return .failure(reason)
        }
         
        if isGlobSet { set.name = globSetName(servers) }
        let mapping = ModuleHostMapping(pattern: "rule-set:" + set.reference,
                                         value: servers == ["system"] ? .systemDNS : .dnsServers(servers), origin: origin)
        return .success((mapping, set))
    }

     
    static func globSetName(_ servers: [String]) -> String {
        "host-" + String(ModuleJSON.sha256(Data(servers.joined(separator: ",").utf8)).prefix(8))
    }

     
     
    static func isGlob(_ key: String) -> Bool {
        let name = key.trimmingCharacters(in: .whitespaces).lowercased()
        guard name.contains("?") || name.contains("*"), !name.contains(":"), !name.contains("/") else { return false }
        return kernelPattern(name) == nil
    }

     
     
     
    static func surgeGlobRule(_ pattern: String) -> String? {
        let name = pattern.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, name.utf8.count <= 253, ModuleYAMLText.isOneLine(name), !name.hasPrefix("."), !name.hasSuffix("."),
              !name.contains(".."), !name.contains("+"),
              name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return "DOMAIN-WILDCARD," + name
    }

     
     
     
     
     
     
    static func stashGlobRule(_ pattern: String) -> String? {
        let name = pattern.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, name.utf8.count <= 253, ModuleYAMLText.isOneLine(name), !name.hasSuffix("."),
              name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        var labels = name.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var head = "^"
        if labels.first == "+" {
            head = "^(?:.+\\.)?"
            labels.removeFirst()
        } else if labels.first == "" {
            head = "^.+\\."
            labels.removeFirst()
        }
        guard !labels.isEmpty, !labels.contains(where: { $0.isEmpty || $0.contains("+") }) else { return nil }
        let body = labels.map { label -> String in
            if label == "*" { return "[^.]+" }
            return label.map { character -> String in
                switch character {
                case "*": return "[^.]*"
                case "?": return "[^.]"
                default: return NSRegularExpression.escapedPattern(for: String(character))
                }
            }.joined()
        }.joined(separator: "\\.")
        return "DOMAIN-REGEX," + head + body + "$"
    }

     
    static func target(_ value: String) -> Result<ModuleHostValue, ModuleIgnoredReason> {
        let lowered = value.lowercased()
         
        if lowered.hasPrefix("script:") { return .failure(.platformCannot(.dnsScripts)) }
        if lowered.hasPrefix("ip-mode:") {
             
             
             
            let mode = lowered.dropFirst(8).trimmingCharacters(in: .whitespaces)
            switch mode {
            case "dual", "ipv4-only", "ipv6-only": return .success(.ipMode(mode))
            case "ipv4-preferred", "ipv6-preferred": return .failure(.notApplicable(.clashCannotDoThis))
            default: return .failure(.unreadableLine)
            }
        }
        if lowered.hasPrefix("server:") {
            let servers = value.dropFirst(7).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            guard !servers.isEmpty else { return .failure(.unreadableLine) }
            if servers.count == 1, ["system", "syslib", "force-syslib"].contains(servers[0].lowercased()) { return .success(.systemDNS) }
            var out: [String] = []
            for server in servers {
                guard let written = ModuleSettingsMapping.dnsServer(server, kind: .any), written != "system" else { return .failure(.invalidHost(server)) }
                out.append(written)
            }
            return .success(.dnsServers(out))
        }
        let items = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard !items.isEmpty else { return .failure(.unreadableLine) }
        if items.allSatisfy({ ModuleIPLiteral($0) != nil }) {
            return .success(.addresses(items.compactMap { ModuleIPLiteral($0)?.canonical }))
        }
        guard items.count == 1, let name = kernelPattern(items[0]), !name.contains("*"), !name.hasPrefix(".") else {
            return .failure(.unreadableLine)
        }
        return .success(.name(name))
    }

     
     
     
     
     
     
     
    static func kernelPattern(_ surgePattern: String) -> String? {
        let name = surgePattern.trimmingCharacters(in: .whitespaces).lowercased()
        guard !name.isEmpty, name.utf8.count <= 253, ModuleYAMLText.isOneLine(name), !name.contains("?"),
              name.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        let pattern = name.hasPrefix("*.") && name.count > 2 ? "." + name.dropFirst(2) : name
        return ModuleSettingsMapping.trieHolds(pattern) ? pattern : nil
    }

    private static let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-_*?+")

     
     
    static func stash(_ name: String, _ target: OrderedJSON, origin: ModuleLineOrigin) -> Result<ModuleHostMapping, ModuleIgnoredReason> {
        let pattern = name.trimmingCharacters(in: .whitespaces).lowercased()
        guard !pattern.isEmpty, ModuleYAMLText.isOneLine(pattern), pattern.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              !pattern.contains("?"), ModuleSettingsMapping.trieHolds(pattern) else {
            return .failure(.invalidHost(name))
        }
        switch target {
        case .string(let text):
            if ModuleIPLiteral(text) != nil { return .success(ModuleHostMapping(pattern: pattern, value: .addresses([text]), origin: origin)) }
            guard let alias = kernelPattern(text), !alias.contains("*") else { return .failure(.unreadableLine) }
            return .success(ModuleHostMapping(pattern: pattern, value: .name(alias), origin: origin))
        case .array(let items):
            let addresses = items.compactMap { item -> String? in
                if case .string(let text) = item, ModuleIPLiteral(text) != nil { return text }
                return nil
            }
            guard !addresses.isEmpty, addresses.count == items.count else { return .failure(.unreadableLine) }
            return .success(ModuleHostMapping(pattern: pattern, value: .addresses(addresses), origin: origin))
        default:
            return .failure(.unreadableLine)
        }
    }
}
