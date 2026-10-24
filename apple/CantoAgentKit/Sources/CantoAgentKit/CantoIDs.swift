import Foundation
#if canImport(CryptoKit)
import CryptoKit
#else
import Crypto
#endif

/// Crockford Base32 / ULID / id 派生（对齐 TS src/lib/ids.ts）。
public enum CantoIDs {
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
    private static let monotonic = ULIDMonotonic()

    public static func ulid(now: Int64 = Int64(Date().timeIntervalSince1970 * 1000)) -> String {
        // 130-bit ULID：高 48 bit = 毫秒时间戳，低 80 bit = 随机。
        // 位流 = 值 << 6 的 136-bit 大端（前 6 bit 零），随后 26×5bit 逐组取字符。
        let rand = monotonic.randomFor(now: now)
        let ts = UInt64(bitPattern: now) & 0xFFFF_FFFF_FFFF

        var buf = [UInt8](repeating: 0, count: 17)
        buf[0] = UInt8((ts >> 42) & 0x3f)                       // ts 高 6 位
        buf[1] = UInt8((ts >> 34) & 0xff)
        buf[2] = UInt8((ts >> 26) & 0xff)
        buf[3] = UInt8((ts >> 18) & 0xff)
        buf[4] = UInt8((ts >> 10) & 0xff)
        buf[5] = UInt8((ts >> 2) & 0xff)
        buf[6] = UInt8((ts << 6) & 0xff) | UInt8((rand >> 74) & 0x3f)
        buf[7] = UInt8((rand >> 66) & 0xff)
        buf[8] = UInt8((rand >> 58) & 0xff)
        buf[9] = UInt8((rand >> 50) & 0xff)
        buf[10] = UInt8((rand >> 42) & 0xff)
        buf[11] = UInt8((rand >> 34) & 0xff)
        buf[12] = UInt8((rand >> 26) & 0xff)
        buf[13] = UInt8((rand >> 18) & 0xff)
        buf[14] = UInt8((rand >> 10) & 0xff)
        buf[15] = UInt8((rand >> 2) & 0xff)
        buf[16] = UInt8((rand << 6) & 0xff)

        var acc: UInt64 = 0
        var accBits = 0
        var chars = [Character](repeating: "0", count: 26)
        var idx = 0
        for b in buf {
            acc = (acc << 8) | UInt64(b)
            accBits += 8
            while accBits >= 5, idx < 26 {
                accBits -= 5
                chars[idx] = alphabet[Int((acc >> UInt64(accBits)) & 31)]
                idx += 1
            }
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

/// ULID 单调状态（Swift 6 严格并发：可变全局状态收进锁保护的类）。
private final class ULIDMonotonic: @unchecked Sendable {
    private let lock = NSLock()
    private var lastMs: Int64 = -1
    private var lastRand: UInt64 = 0

    func randomFor(now: Int64) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        if now == lastMs {
            lastRand &+= 1
            return lastRand
        }
        var gen = SystemRandomNumberGenerator()
        var bytes = [UInt8](repeating: 0, count: 10)
        for i in 0..<10 { bytes[i] = UInt8.random(in: 0...255, using: &gen) }
        lastMs = now
        lastRand = bytes.reduce(0) { ($0 << 8) | UInt64($1) }
        return lastRand
    }
}
