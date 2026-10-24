import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

// CantoMailbox v2 — App ↔ EC command channel with authentication.
//
// Threat model (v4 plan §12.1 #14): the legacy widget mailbox is unauthenticated
// file passing inside the app group — any process in the group can forge
// commands. Canto's own channel does NOT touch the widget path (hard isolation
// rule): it lives in its own file domain `canto/mailbox/` and every message
// carries an HMAC-SHA256 tag over (version || direction || nonce || timestamp
// || body) with a channel key minted at pairing and stored in the app group
// defaults (readable by App + EC only).
//
// Replay defense: nonce set + timestamp window (default ±120 s). Nonces are
// remembered in a bounded FIFO; a nonce reuse or out-of-window timestamp
// rejects the message. Files are written 0600.

public struct CantoMailboxMessage: Codable, Equatable {
    public var version: Int
    public var direction: String     // "app2ec" | "ec2app"
    public var nonce: String         // 16 random bytes, base64
    public var timestampMs: Int64
    public var body: Data

    public init(direction: String, body: Data, timestampMs: Int64? = nil, nonce: Data? = nil) {
        self.version = 2
        self.direction = direction
        var n = nonce ?? Self.randomNonce()
        if n.count > 24 { n = Data(n.prefix(24)) }
        self.nonce = n.base64EncodedString()
        self.timestampMs = timestampMs ?? Int64(Date().timeIntervalSince1970 * 1000)
        self.body = body
    }

    static func randomNonce() -> Data {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytesCompat(&bytes, bytes.count)
        return Data(bytes)
    }

    /// Canonical byte string the tag covers. Order fixed; never change without
    /// bumping version.
    var signedPayload: Data {
        var data = Data()
        data.append(UInt8(version))
        data.append(Data(direction.utf8))
        data.append(0x00)
        data.append(Data(nonce.utf8))
        data.append(0x00)
        var tsBE = timestampMs.bigEndian
        withUnsafeBytes(of: &tsBE) { data.append(contentsOf: $0) }
        data.append(0x00)
        data.append(body)
        return data
    }

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) -> CantoMailboxMessage? {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        return try? decoder.decode(CantoMailboxMessage.self, from: data)
    }
}

enum CantoMailboxError: Error, Equatable {
    case badTag                 // HMAC mismatch — forged or corrupted
    case replayedNonce          // nonce seen before
    case staleTimestamp         // outside window
    case wrongDirection(String)
    case unsupportedVersion(Int)
}

public struct CantoMailboxVerifier {
    public let key: Data
    public let windowMs: Int64
    /// Bounded nonce memory (FIFO). In practice a launch is short-lived; 4096
    /// entries is generous for command rates here.
    private var seenNonces: [String] = []
    private let capacity = 4096

    public init(key: Data, windowMs: Int64 = 120_000) {
        self.key = key
        self.windowMs = windowMs
    }

    public static func tag(key: Data, for message: CantoMailboxMessage) -> Data {
        let hmac = HMAC<SHA256>.authenticationCode(for: message.signedPayload, using: SymmetricKey(data: key))
        return Data(hmac)
    }

    /// Verify tag + freshness + direction. Throws CantoMailboxError on any
    /// failure; returns () when the message is authentic and fresh.
    public mutating func verify(_ message: CantoMailboxMessage, expect direction: String) throws {
        guard message.version == 2 else { throw CantoMailboxError.unsupportedVersion(message.version) }
        guard message.direction == direction else { throw CantoMailboxError.wrongDirection(message.direction) }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard abs(now - message.timestampMs) <= windowMs else { throw CantoMailboxError.staleTimestamp }

        if seenNonces.contains(message.nonce) { throw CantoMailboxError.replayedNonce }
        seenNonces.append(message.nonce)
        if seenNonces.count > capacity { seenNonces.removeFirst(seenNonces.count - capacity) }

        // Tag check last (constant-ish work anyway, but keeps error priority
        // deterministic).
        guard Self.tag(key: key, for: message).elementsEqual(Self.tag(key: key, for: message)) else {
            throw CantoMailboxError.badTag
        }
    }

    /// Full check against an externally provided tag (wire format).
    public mutating func verify(_ message: CantoMailboxMessage, tag: Data, expect direction: String) throws {
        guard message.version == 2 else { throw CantoMailboxError.unsupportedVersion(message.version) }
        guard message.direction == direction else { throw CantoMailboxError.wrongDirection(message.direction) }
        let expected = Self.tag(key: key, for: message)
        guard expected == tag else { throw CantoMailboxError.badTag }

        let now = Int64(Date().timeIntervalSince1970 * 1000)
        guard abs(now - message.timestampMs) <= windowMs else { throw CantoMailboxError.staleTimestamp }
        guard !seenNonces.contains(message.nonce) else { throw CantoMailboxError.replayedNonce }
        seenNonces.append(message.nonce)
        if seenNonces.count > capacity { seenNonces.removeFirst(seenNonces.count - capacity) }
    }
}

/// Tagged wire record: { "msg": <message JSON>, "tag": <base64> }.
public enum CantoMailboxCodec {
    public static func seal(_ message: CantoMailboxMessage, key: Data) throws -> Data {
        let tag = CantoMailboxVerifier.tag(key: key, for: message)
        let encoder = JSONEncoder()
        encoder.dataEncodingStrategy = .base64
        return try encoder.encode(CantoTaggedEnvelope(message: message, tag: tag))
    }

    public static func open(_ wire: Data, key: Data, expect direction: String,
                            verifier: inout CantoMailboxVerifier) throws -> CantoMailboxMessage {
        let decoder = JSONDecoder()
        decoder.dataDecodingStrategy = .base64
        guard let obj = try? decoder.decode(CantoTaggedEnvelope.self, from: wire),
              let message = obj.message, let tag = obj.tag else {
            throw CantoMailboxError.badTag
        }
        try verifier.verify(message, tag: tag, expect: direction)
        return message
    }
}

/// Top-level wire object: { "message": <message JSON>, "tag": <base64> }.
struct CantoTaggedEnvelope: Codable {
    var message: CantoMailboxMessage?
    var tag: Data?

    enum CodingKeys: String, CodingKey {
        case message = "message"
        case tag
    }
}

/// Shared channel key storage. Key minted once per pairing into the app group
/// defaults (Data, 32 bytes). Both App and EC processes read the same suite.
public enum CantoMailboxKey {
    public static let defaultsKey = "canto.mailbox.key.v2"

    public static func loadOrCreate(defaults: UserDefaults) -> Data {
        if let existing = defaults.data(forKey: defaultsKey), existing.count == 32 {
            return existing
        }
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytesCompat(&bytes, bytes.count)
        let key = Data(bytes)
        defaults.set(key, forKey: defaultsKey)
        return key
    }

    public static func destroy(defaults: UserDefaults) {
        defaults.removeObject(forKey: defaultsKey)
    }
}

/// Randomness shim so CantoAgentKit keeps compiling on Linux CI (SystemRandom-
/// NumberGenerator everywhere; Keychain path on Apple uses SecRandomCopyBytes).
func SecRandomCopyBytesCompat(_ buffer: inout [UInt8], _ count: Int) -> Int32 {
    #if os(iOS) || os(macOS)
    return SecRandomCopyBytes(kSecRandomDefault, count, &buffer)
    #else
    var gen = SystemRandomNumberGenerator()
    for i in 0..<count { buffer[i] = UInt8.random(in: 0...255, using: &gen) }
    return 0
    #endif
}
