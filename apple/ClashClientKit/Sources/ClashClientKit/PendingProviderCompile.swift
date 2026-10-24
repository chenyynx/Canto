import Foundation

 
 
 
 
 
public struct PendingProviderCompile: Decodable, Equatable, Sendable {
    public let kind: String
    public let name: String
    public let result: ProviderRefreshState.Result?
     
    public let error: String?
    public let countAfter: Int?

    private enum Field: String, CodingKey { case kind, name, result, error, countAfter }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Field.self)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        result = (try? c.decodeIfPresent(String.self, forKey: .result)).flatMap { $0.flatMap(ProviderRefreshState.Result.init(rawValue:)) }
        error = try c.decodeIfPresent(String.self, forKey: .error).flatMap { $0.isEmpty ? nil : $0 }
        countAfter = try c.decodeIfPresent(Int.self, forKey: .countAfter)
    }

     
    public static func decode(_ json: String) throws -> [PendingProviderCompile] {
        try JSONDecoder().decode([PendingProviderCompile].self, from: Data(json.utf8))
    }

     
     
     
    public static func waits(in state: ProviderRefreshState?) -> Bool {
        guard let state, let running = state.running else { return false }
        for (identity, key) in running.providers {
            guard let entry = state.entries[key], entry.result == .pendingApp else { continue }
            let parts = identity.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let taker = state.pendingTaker(kind: String(parts[0]), name: String(parts[1]), reason: entry.waitReason)
            if taker == .appWhenOpen { return true }
        }
        return false
    }
}
