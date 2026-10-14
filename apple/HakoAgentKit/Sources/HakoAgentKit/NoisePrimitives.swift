import Foundation
import Crypto

/// Noise 基础原语（对齐 TS src/protocol/noise.ts 的 hkdf / CipherState / SymmetricState）。
///
/// 原语选型：HKDF-SHA256 手写（RFC 5869）、AES-256-GCM 用 swift-crypto、X25519 用 Curve25519。
/// 黄金向量（vectors-noise.json primitives）保证与 TS 侧逐字节一致。
public enum NoisePrimitives {
    static let protocolName = AnchorProtocol.protocolName

    /// H0 = protocol name 补零到 32 字节
    static let h0: Data = {
        var d = Data(protocolName.utf8)
        precondition(d.count <= 32)
        d.append(Data(repeating: 0, count: 32 - d.count))
        return d
    }()

    /// RFC 5869 HKDF-SHA256（与 TS 的 hkdf() 完全一致：salt = ck（32B），info 为空）
    static func hkdf(ck: Data, ikm: Data, outLen: Int = 2) -> [Data] {
        let prk = HMAC<SHA256>.authenticationCode(for: ikm, using: SymmetricKey(data: ck))
        var outs: [Data] = []
        var prev = Data()
        for i in 1...outLen {
            var input = prev
            input.append(UInt8(i))
            let t = HMAC<SHA256>.authenticationCode(for: input, using: SymmetricKey(data: Data(prk)))
            prev = Data(t)
            outs.append(prev)
        }
        return outs
    }

    static func mixHash(_ h: Data, _ data: Data) -> Data {
        var buf = h
        buf.append(data)
        return Data(SHA256.hash(data: buf))
    }

    static func nonce12(_ n: UInt64) -> Data {
        var d = Data(repeating: 0, count: 12)
        // 与 TS 一致：4 字节零前缀 + 小端 8 字节计数
        d.replaceSubrange(4..<12, with: withUnsafeBytes(of: n.littleEndian) { Data($0) })
        return d
    }

    public static func sha256(_ data: Data) -> Data { Data(SHA256.hash(data: data)) }
}

/// 单密钥 AES-256-GCM 状态（nonce 从 0 单调递增；无密钥时直通=握手明文段）。
struct CipherState {
    private var key: SymmetricKey?
    private var n: UInt64 = 0

    var hasKey: Bool { key != nil }

    mutating func initializeKey(_ k: Data?) {
        key = k.map { SymmetricKey(data: $0) }
        n = 0
    }

    mutating func encryptWithAd(ad: Data, plaintext: Data) throws -> Data {
        guard let key else { return plaintext }
        if n >= UInt64.max - 1 { throw NoiseError.nonceExhausted }
        let sealed = try AES.GCM.seal(plaintext, using: key, nonce: AES.GCM.Nonce(data: NoisePrimitives.nonce12(n)), authenticating: ad)
        n &+= 1
        // TS 布局：ciphertext || tag（16B）
        return sealed.ciphertext + sealed.tag
    }

    mutating func decryptWithAd(ad: Data, ciphertext: Data) throws -> Data {
        guard let key else { return ciphertext }
        guard ciphertext.count >= 16 else { throw NoiseError.frameTooShort }
        let tag = ciphertext.suffix(16)
        let body = ciphertext.prefix(ciphertext.count - 16)
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: NoisePrimitives.nonce12(n)), ciphertext: body, tag: tag)
        let pt = try AES.GCM.open(box, using: key, authenticating: ad)
        n &+= 1
        return pt
    }
}

/// SymmetricState（对齐 TS SymmetricState）
struct SymmetricState {
    var cs = CipherState()
    var ck = Data()
    var h = Data()

    init() {
        h = NoisePrimitives.h0
        ck = h
    }

    mutating func mixKey(_ ikm: Data) {
        let ts = NoisePrimitives.hkdf(ck: ck, ikm: ikm)
        ck = ts[0]
        cs.initializeKey(ts[1])
    }

    mutating func mixHash(_ data: Data) {
        h = NoisePrimitives.mixHash(h, data)
    }

    mutating func encryptAndHash(_ plaintext: Data) throws -> Data {
        let ct = try cs.encryptWithAd(ad: h, plaintext: plaintext)
        mixHash(ct)
        return ct
    }

    mutating func decryptAndHash(_ ciphertext: Data) throws -> Data {
        let pt = try cs.decryptWithAd(ad: h, ciphertext: ciphertext)
        mixHash(ciphertext)
        return pt
    }

    mutating func split() -> (CipherState, CipherState) {
        let ts = NoisePrimitives.hkdf(ck: ck, ikm: Data())
        var c1 = CipherState(), c2 = CipherState()
        c1.initializeKey(ts[0])
        c2.initializeKey(ts[1])
        return (c1, c2)
    }
}

enum NoiseError: Error, Equatable {
    case nonceExhausted
    case frameTooShort
    case frameLengthMismatch
    case handshakeNotComplete
    case wrongRole
    case badStage(String)
    case badMessageLength(String)
    case authenticationFailed
}
