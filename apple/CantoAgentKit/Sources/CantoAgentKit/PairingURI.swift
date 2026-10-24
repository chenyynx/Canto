import Foundation

/// 配对口令 URI（对齐 TS pairing.ts / pairing-uri.ts）。
///
/// 格式（pairing.schema.json $defs/pairingURI）：
///   canto://pair?v=1&k=<43 base64url>&s=<22 base64url>&e=<ep1,ep2>&n=<name>&x=<unix 秒>
public struct PairingURI: Equatable {
    public var k: String
    public var secret: String
    public var endpoints: [String]
    public var name: String?
    public var expiresAt: Int64?

    public init(k: String, secret: String, endpoints: [String], name: String? = nil, expiresAt: Int64? = nil) {
        self.k = k
        self.secret = secret
        self.endpoints = endpoints
        self.name = name
        self.expiresAt = expiresAt
    }

    public func encoded() -> String {
        var parts = ["v=1", "k=\(k)", "s=\(secret)"]
        parts.append("e=" + endpoints.map { addingURLEncoding($0) }.joined(separator: ","))
        if let name { parts.append("n=\(addingURLEncoding(name))") }
        if let x = expiresAt { parts.append("x=\(x)") }
        return "canto://pair?" + parts.joined(separator: "&")
    }

    public static func parse(_ uri: String) throws -> PairingURI {
        guard uri.hasPrefix("canto://pair?") else { throw PairingError.notPairingURI }
        let query = String(uri.dropFirst("canto://pair?".count))
        var k: String?
        var s: String?
        var e: String?
        var n: String?
        var x: Int64?
        var v: Int?
        for pair in query.split(separator: "&") {
            let kv = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            let key = String(kv[0])
            let val = String(kv[1]).removingPercentEncoding ?? String(kv[1])
            switch key {
            case "v": v = Int(val)
            case "k": k = val
            case "s": s = val
            case "e": e = val
            case "n": n = val
            case "x": x = Int64(val)
            default: break
            }
        }
        guard v == 1, let kk = k, let ss = s, let ee = e else {
            throw PairingError.missingFields
        }
        return PairingURI(
            k: kk, secret: ss,
            endpoints: ee.split(separator: ",").map(String.init),
            name: n, expiresAt: x
        )
    }

    private func addingURLEncoding(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
}

public enum PairingError: Error, Equatable {
    case notPairingURI
    case missingFields
}
