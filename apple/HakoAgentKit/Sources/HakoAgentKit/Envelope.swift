import Foundation
import Crypto

/// 信封帧（对齐 envelope.schema.json；TS 侧负责 JSON Schema 校验，
/// Swift 侧负责类型化建模 + 关键不变量校验 + JSON 编解码）。
public struct Envelope: Codable, Equatable {
    public var v: Int = 1
    public var t: String            // cmd | res | ack | evt | ping | pong | bye
    public var id: String           // ULID
    public var ref: String?         // res/ack 引用的命令 id
    public var seq: Int?
    public var ch: String?          // app | ext
    public var op: String?
    public var args: [String: JSONValue]?
    public var data: [String: JSONValue]?
    public var ttlMs: Int?
    public var idem: String?
    public var `if`: Precondition?
    public var ok: Bool?
    public var status: String?      // applied | deferred | rejected
    public var err: ErrorBody?
    public var meta: [String: JSONValue]?
    public var reason: String?

    public struct Precondition: Codable, Equatable {
        public var rev: Int?
        public var epoch: Int?
        public init(rev: Int? = nil, epoch: Int? = nil) { self.rev = rev; self.epoch = epoch }
    }

    public struct ErrorBody: Codable, Equatable {
        public var code: String
        public var message: String
        public var retryable: Bool?
        public var hint: String?
        public var action: String?
        public init(code: String, message: String, retryable: Bool? = nil, hint: String? = nil, action: String? = nil) {
            self.code = code; self.message = message; self.retryable = retryable; self.hint = hint; self.action = action
        }
    }

    public init(t: String, id: String) {
        self.t = t
        self.id = id
    }

    enum CodingKeys: String, CodingKey {
        case v, t, id, ref, seq, ch, op, args, data
        case ttlMs = "ttl_ms"
        case idem
        case `if`
        case ok, status, err, meta, reason
    }

    // MARK: 不变量（与 envelope schema 的 allOf 一致）

    public func validate() -> EnvelopeValidationError? {
        if v != 1 { return .badVersion }
        guard AnchorIDs.isUlid(id) else { return .badId }
        if let r = ref, !AnchorIDs.isUlid(r) { return .badRef }
        switch t {
        case "res":
            if ref == nil { return .resNeedsRef }
            if ok == nil { return .resNeedsOk }
            if status == nil { return .resNeedsStatus }
            if let st = status, !["applied", "deferred", "rejected"].contains(st) { return .badStatus }
        case "ack":
            if ref == nil { return .ackNeedsRef }
        case "cmd":
            if (op ?? "").isEmpty { return .cmdNeedsOp }
            if !(ch == "app" || ch == "ext") { return .cmdNeedsChannel }
            let ns = op!.split(separator: ".").first.map(String.init)
            guard let ns, ["app", "core", "device", "evt"].contains(ns) else { return .badOpNamespace }
            if let ttl = ttlMs, !(1000...600000).contains(ttl) { return .badTtl }
        default:
            if !["ack", "evt", "ping", "pong", "bye"].contains(t) { return .badType }
        }
        if let err {
            let known = ["DEVICE_REQUIRED", "DEVICE_OFFLINE", "APP_SUSPENDED", "TUNNEL_DOWN", "TUNNEL_STARTING", "TUNNEL_STOPPED", "NEED_USER_ACTION", "SCOPE_DENIED", "NOT_CONTROLLER", "STALE_REV", "STALE_EPOCH", "USER_RECENT_CHANGE", "INVALID_ARGUMENT", "NOT_FOUND", "UNSUPPORTED", "CONFLICT_BUSY", "TIMEOUT_UNKNOWN", "CORE_ERROR", "RATE_LIMITED", "EXPIRED", "PAIR_KEY_MISMATCH", "UNKNOWN_DEVICE", "REVOKED", "KEY_MISMATCH"]
            if !known.contains(err.code) { return .badErrorCode }
        }
        return nil
    }
}

public enum EnvelopeValidationError: Error, Equatable {
    case badVersion, badId, badRef
    case resNeedsRef, resNeedsOk, resNeedsStatus
    case ackNeedsRef
    case cmdNeedsOp, cmdNeedsChannel, badOpNamespace, badTtl
    case badStatus, badType, badErrorCode
}

/// op 命名空间 → 通道（对齐 TS routeOf）
public func routeOf(_ op: String) -> String? {
    switch op.split(separator: ".").first {
    case "app": return "app"
    case "core": return "ext"
    case "device": return "device"
    case "evt": return "evt"
    default: return nil
    }
}

// MARK: - JSONValue（envelope 允许任意 JSON 的字段）

public enum JSONValue: Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let i = try? c.decode(Int64.self) { self = .int(i) }
        else if let d = try? c.decode(Double.self) { self = .double(d) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let a = try? c.decode([JSONValue].self) { self = .array(a) }
        else if let o = try? c.decode([String: JSONValue].self) { self = .object(o) }
        else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "unsupported JSON") }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let b): try c.encode(b)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .string(let s): try c.encode(s)
        case .array(let a): try c.encode(a)
        case .object(let o): try c.encode(o)
        }
    }

    public var stringValue: String? { if case .string(let s) = self { return s }; return nil }
    public var intValue: Int64? { if case .int(let i) = self { return i }; return nil }
    public var boolValue: Bool? { if case .bool(let b) = self { return b }; return nil }
    public var objectValue: [String: JSONValue]? { if case .object(let o) = self { return o }; return nil }
}
