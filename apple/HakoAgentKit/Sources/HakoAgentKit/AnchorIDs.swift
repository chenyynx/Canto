import Foundation
import Crypto

/// Crockford Base32 / ULID / id 派生（对齐 TS src/lib/ids.ts）。
public enum AnchorIDs {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    /// 字节串 → Crockford Base32（大端、无填充、右对齐）
    public static func crockford(_ data: Data) -> String {
        var value: UInt64 = 0
        var bitCount = 0
        var out = ""
        for b in data {
            value = (value << 8) | UInt64(b)
            bitCount += 8
            while bitCount >= 5 {
                bitCount -= 5
                let idx = Int((value >> UInt64(bitCount)) & 31)
                out.append(alphabet[idx])
            }
        }
        if bitCount > 0 {
            let idx = Int((value << UInt64(5 - bitCount)) & 31)
            out.append(alphabet[idx])
        }
        return out
    }

    /// 公钥原文（32B）→ 16 字符 id（SHA-256 前 10 字节）
    public static func idFromPub(_ pubRaw: Data) -> String {
        let digest = SHA256.hash(data: pubRaw)
        return crockford(Data(digest).prefix(10))
    }

    public static func agentIdFromPub(_ pubRaw: Data) -> String { idFromPub(pubRaw) }
    public static func deviceIdFromPub(_ pubRaw: Data) -> String { "dev_" + idFromPub(pubRaw) }

    /// ULID：48 位毫秒时间戳 + 80 位随机 = 26 字符（同毫秒单调递增，与 TS 一致）
    private static let lock = NSLock()
    private static var lastMs: Int64 = -1
    private static var lastRand: UInt64 = 0

    public static func ulid(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> String {
        lock.lock()
        defer { lock.unlock() }
        var rand: UInt64
        if now == lastMs {
            rand = lastRand &+ 1
        } else {
            // SystemRandomNumberGenerator：Apple 平台走 arc4random、Linux 走 getrandom，均 CSPRNG
            var gen = SystemRandomNumberGenerator()
            var bytes = [UInt8](repeating: 0, count: 10)
            for i in 0..<10 { bytes[i] = UInt8.random(in: 0...255, using: &gen) }
            rand = bytes.reduce(0) { ($0 << 8) | UInt64($1) }
        }
        lastMs = now
        lastRand = rand
        var value: UInt128 = (UInt128(UInt64(bitPattern: now)) & ((UInt128(1) << 48) - 1)) << 80
        value |= UInt128(rand & ((UInt64(1) << 80) - 1))
        var chars = [Character](repeating: "0", count: 26)
        for i in stride(from: 25, through: 0, by: -1) {
            chars[i] = alphabet[Int(value & 31)]
            value >>= 5
        }
        return String(chars)
    }

    // 校验（对齐 envelope schema 的 pattern）
    public static func isUlid(_ s: String) -> Bool {
        s.count == 26 && s.allSatisfy { alphabet.contains($0) }
    }
    public static func isAgentId(_ s: String) -> Bool {
        s.count == 16 && s.allSatisfy { alphabet.contains($0) }
    }
    public static func isDeviceId(_ s: String) -> Bool {
        s.hasPrefix("dev_") && isAgentId(String(s.dropFirst(4)))
    }
}
