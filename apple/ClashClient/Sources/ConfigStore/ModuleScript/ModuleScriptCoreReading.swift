#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
enum ModuleScriptCoreReading {
     
    static let builtins = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "COMPATIBLE"]

    private static func object(_ json: String) -> [String: Any]? {
        (try? JSONSerialization.jsonObject(with: Data(json.utf8))) as? [String: Any]
    }

     
    static func groups(summary: String) -> [String] {
        (object(summary)?["groupOrder"] as? [String] ?? []).filter { $0 != "GLOBAL" }
    }

     
    static func groupTypes(summary: String) -> [String: String] {
        guard let groups = object(summary)?["groups"] as? [String: Any] else { return [:] }
        return groups.compactMapValues { ($0 as? [String: Any])?["type"] as? String }
    }

     
    static func selected(summary: String, group: String) -> String? {
        guard let groups = object(summary)?["groups"] as? [String: Any], let entry = groups[group] as? [String: Any],
              let now = entry["now"] as? String, !now.isEmpty else { return nil }
        return now
    }

     
    static func selected(widget: String) -> String? {
        guard let now = object(widget)?["now"] as? String, !now.isEmpty else { return nil }
        return now
    }

     
    static func members(page: String) -> [ModuleScriptPolicy]? {
        guard let reply = object(page), reply["error"] == nil, let members = reply["members"] as? [[String: Any]] else { return nil }
        return members.compactMap { member in
            (member["name"] as? String).map { ModuleScriptPolicy(name: $0, kind: kind(of: member["type"] as? String ?? "")) }
        }
    }

     
    static func final(rulesPage: String) -> String? {
        guard let rules = object(rulesPage)?["rules"] as? [[String: Any]], let policy = rules.first?["proxy"] as? String,
              !policy.isEmpty else { return nil }
        return policy
    }

     
    static func mode(configs: String) -> String? {
        guard let mode = object(configs)?["mode"] as? String, !mode.isEmpty else { return nil }
        return mode.lowercased()
    }

     
    static func kind(of type: String) -> String {
        switch type {
        case "Selector", "URLTest", "Fallback", "LoadBalance", "Relay", "Smart": return "group"
        case "Direct", "Reject", "RejectDrop", "Pass", "Compatible", "Dns": return "buildin"
        default: return "node"
        }
    }

     
    static func recordType(_ type: Int) -> String {
        [1: "A", 2: "NS", 5: "CNAME", 6: "SOA", 12: "PTR", 15: "MX", 16: "TXT", 28: "AAAA", 33: "SRV", 64: "SVCB", 65: "HTTPS"][type]
            ?? String(type)
    }

     
     
     
    static func dnsResult(domain: String, replies: [String]) -> Result<ModuleScriptDNSResult, ModuleScriptDNSFailure> {
        var answers: [ModuleScriptDNSRecord] = []
        var failures: [String] = []
        for reply in replies {
            guard let object = object(reply) else { continue }
            if let error = object["error"] as? String {
                failures.append(error)
                continue
            }
            for record in object["Answer"] as? [[String: Any]] ?? [] {
                guard let name = record["name"] as? String, let data = record["data"] as? String else { continue }
                answers.append(ModuleScriptDNSRecord(name: name, type: recordType(record["type"] as? Int ?? 0), value: data,
                                                     ttl: record["TTL"] as? Int ?? 0))
            }
        }
        if !answers.isEmpty {
            return .success(ModuleScriptDNSResult(domain: domain, protocolName: "auto", server: "", fromCache: false, answers: answers))
        }
        if !replies.isEmpty, failures.count == replies.count {
            return .failure(ModuleScriptDNSFailure(code: "QUERY_FAILED", message: failures.joined(separator: "; ")))
        }
        return .failure(ModuleScriptDNSFailure(code: "NO_ANSWER", message: #"\#(domain) has no A or AAAA record"#))
    }

     
     
    static func asksTheResolver(_ query: ModuleScriptDNSQuery) -> Bool {
        if let named = query.protocolName { return named == "auto" }
        return query.server.map { $0.caseInsensitiveCompare("system") == .orderedSame } ?? true
    }

     
     
     
     
    static func scriptDNSRequest(_ query: ModuleScriptDNSQuery) -> String {
        var request: [String: Any] = ["domain": query.domain, "timeoutMilliseconds": query.timeoutMilliseconds]
        if let named = query.protocolName { request["protocol"] = named }
        if let server = query.server { request["server"] = server }
        let data = (try? JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

     
     
     
     
    static func scriptDNSResult(_ reply: String) -> Result<ModuleScriptDNSResult, ModuleScriptDNSFailure> {
        guard let object = object(reply) else {
            return .failure(ModuleScriptDNSFailure(code: "QUERY_FAILED", message: #"Clash answered what is not JSON: \#(reply)"#))
        }
        if let error = object["error"] as? [String: Any] {
            return .failure(ModuleScriptDNSFailure(code: error["code"] as? String ?? "QUERY_FAILED",
                                                   message: error["message"] as? String ?? ""))
        }
        guard let domain = object["domain"] as? String, let records = object["answers"] as? [[String: Any]] else {
            return .failure(ModuleScriptDNSFailure(code: "QUERY_FAILED", message: #"Clash's answer has no domain or answers: \#(reply)"#))
        }
        let answers = records.compactMap { record -> ModuleScriptDNSRecord? in
            guard let name = record["name"] as? String, let type = record["type"] as? String,
                  let value = record["value"] as? String else { return nil }
            return ModuleScriptDNSRecord(name: name, type: type, value: value, ttl: record["ttl"] as? Int ?? 0)
        }
        return .success(ModuleScriptDNSResult(domain: domain, protocolName: object["protocol"] as? String ?? "",
                                              server: object["server"] as? String ?? "",
                                              fromCache: object["fromCache"] as? Bool ?? false, answers: answers))
    }
}
#endif
