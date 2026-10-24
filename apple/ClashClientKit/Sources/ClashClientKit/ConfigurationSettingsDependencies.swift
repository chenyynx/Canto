import Foundation

 
 
enum ConfigurationSettingsDependencies {
    static func names(settings: OrderedJSON, dns: OrderedJSON?) -> Set<String> {
        var result = Set<String>()
        func prefix(_ text: String) {
            guard text.lowercased().hasPrefix("rule-set:") else { return }
            result.formUnion(text.dropFirst(9).split(separator: ",").map(String.init))
        }
        func strings(_ value: OrderedJSON?) -> [String] {
            guard case .array(let values) = value else { return [] }
            return values.compactMap { if case .string(let text) = $0 { return text }; return nil }
        }
        let dns = dns ?? settings.topLevelValue("dns")
        for key in ["nameserver-policy", "proxy-server-nameserver-policy"] {
            if case .object(let entries) = dns?.topLevelValue(key) { entries.forEach { prefix($0.key) } }
        }
        for line in strings(dns?.topLevelValue("fake-ip-filter")) {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, parts[0] == "RULE-SET" { result.insert(parts[1]) }
        }
        for key in ["force-domain", "skip-domain", "skip-src-address", "skip-dst-address"] {
            strings(settings.topLevelValue("sniffer")?.topLevelValue(key)).forEach(prefix)
        }
        return result
    }
}
