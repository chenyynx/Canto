import Foundation
import Crypto

/// X25519 密钥工具（对齐 TS 的 generateDH / dhRaw / rawPublic / fromRawPublic）。
public struct DHKey {
    public let priv: Curve25519.KeyAgreement.PrivateKey
    public let pub: Data

    public static func generate() -> DHKey {
        let k = try! Curve25519.KeyAgreement.PrivateKey.init()
        return DHKey(priv: k, pub: k.publicKey.rawRepresentation)
    }

    /// 从原始 32 字节私钥构造（测试向量用）
    public static func fromRawPrivate(_ raw: Data) -> DHKey {
        let k = try! Curve25519.KeyAgreement.PrivateKey(rawRepresentation: raw)
        return DHKey(priv: k, pub: k.publicKey.rawRepresentation)
    }

    /// DH运算：返回共享密钥原文（32B）
    public func shared(with peerPubRaw: Data) -> Data {
        let peer = try! Curve25519.KeyAgreement.PublicKey(rawRepresentation: peerPubRaw)
        let s = try! priv.sharedSecretFromKeyAgreement(with: peer)
        return s.withUnsafeBytes { Data($0) }
    }
}

/// Noise_XX 握手 + 传输加密（对齐 TS NoiseXX，逐方法对应）。
///
/// XX 三消息：-> e / <- e,ee,s,es / -> s,se
/// 发起方 = 设备（持有 agent 静态公钥），响应方 = agent。
public final class NoiseXX {
    private var ss = SymmetricState()
    private let initiator: Bool
    private let s: DHKey
    private var e: DHKey?
    private var re: Data?
    private var rs: Data?
    private var stage = 0
    private var sendCS: CipherState?
    private var recvCS: CipherState?

    public init(initiator: Bool, staticKey: DHKey, remoteStatic: Data? = nil) {
        self.initiator = initiator
        self.s = staticKey
        if initiator, let rs = remoteStatic { self.rs = rs }
    }

    public var remoteStatic: Data? { rs }
    public var handshakeComplete: Bool { stage >= 3 }

    // MARK: 发起方

    public func writeMsg1() throws -> Data {
        try assertInitiator()
        guard stage == 0 else { throw NoiseError.badStage("msg1 只能是第一条") }
        let e = DHKey.generate()
        self.e = e
        ss.mixHash(e.pub)
        stage = 1
        return e.pub
    }

    /// 返回（对端静态公钥, msg2 载荷）
    public func readMsg2(_ msg: Data) throws -> (rs: Data, payload: Data) {
        try assertInitiator()
        guard stage == 1 else { throw NoiseError.badStage("期待写 msg1") }
        guard msg.count >= AnchorProtocol.dhLen else { throw NoiseError.badMessageLength("msg2 太短") }
        let re = msg.prefix(AnchorProtocol.dhLen)
        self.re = re
        ss.mixHash(re)
        // ee
        ss.mixKey(e!.shared(with: re))
        // s, es：msg2 = re(32) || ct(rs)(48) || ct(payload)
        let rsCt = msg.dropFirst(AnchorProtocol.dhLen).prefix(AnchorProtocol.dhLen + 16)
        let rs = try ss.decryptAndHash(Data(rsCt))
        self.rs = rs
        ss.mixKey(e!.shared(with: rs))
        let payload = try ss.decryptAndHash(Data(msg.dropFirst(AnchorProtocol.dhLen * 2 + 16)))
        stage = 2
        return (rs, payload)
    }

    public func writeMsg3(payload: Data = Data()) throws -> Data {
        try assertInitiator()
        guard stage == 2 else { throw NoiseError.badStage("期待读 msg2") }
        let ct = try ss.encryptAndHash(s.pub)
        // se
        ss.mixKey(s.shared(with: re!))
        let payloadCt = try ss.encryptAndHash(payload)
        let (c1, c2) = ss.split()
        sendCS = c1
        recvCS = c2
        stage = 3
        return ct + payloadCt
    }

    // MARK: 响应方

    public func readMsg1(_ msg: Data) throws {
        try assertResponder()
        guard stage == 0 else { throw NoiseError.badStage("msg1 只能是第一条") }
        guard msg.count == AnchorProtocol.dhLen else { throw NoiseError.badMessageLength("msg1 应为 32 字节") }
        re = msg
        ss.mixHash(msg)
        stage = 1
    }

    public func writeMsg2(payload: Data = Data()) throws -> Data {
        try assertResponder()
        guard stage == 1 else { throw NoiseError.badStage("期待读 msg1") }
        let e = DHKey.generate()
        self.e = e
        ss.mixHash(e.pub)
        // ee
        ss.mixKey(e.shared(with: re!))
        // s, es
        let ct = try ss.encryptAndHash(s.pub)
        ss.mixKey(s.shared(with: re!))
        let payloadCt = try ss.encryptAndHash(payload)
        stage = 2
        return e.pub + ct + payloadCt
    }

    public func readMsg3(_ msg: Data) throws -> Data {
        try assertResponder()
        guard stage == 2 else { throw NoiseError.badStage("期待写 msg2") }
        guard msg.count >= AnchorProtocol.dhLen + 16 else { throw NoiseError.badMessageLength("msg3 太短") }
        let sCt = msg.prefix(AnchorProtocol.dhLen + 16)
        rs = try ss.decryptAndHash(Data(sCt))
        // se = DH(本方临时 e_priv, 对方静态 s_pub)
        ss.mixKey(e!.shared(with: rs!))
        let payload = try ss.decryptAndHash(Data(msg.dropFirst(AnchorProtocol.dhLen + 16)))
        let (c1, c2) = ss.split()
        recvCS = c1
        sendCS = c2
        stage = 3
        return payload
    }

    // MARK: 传输阶段

    public func send(_ plaintext: Data) throws -> Data {
        guard handshakeComplete, let cs = sendCS else { throw NoiseError.handshakeNotComplete }
        guard plaintext.count <= AnchorProtocol.maxPlaintext else { throw NoiseError.frameLengthMismatch }
        let ct = try cs.encryptWithAd(ad: Data(), plaintext: plaintext)
        var len = Data(count: 2)
        len[0] = UInt8((ct.count >> 8) & 0xff)
        len[1] = UInt8(ct.count & 0xff)
        return len + ct
    }

    public func recv(_ frame: Data) throws -> Data {
        guard handshakeComplete, let cs = recvCS else { throw NoiseError.handshakeNotComplete }
        guard frame.count >= 2 else { throw NoiseError.frameTooShort }
        let len = (Int(frame[0]) << 8) | Int(frame[1])
        guard frame.count - 2 == len else { throw NoiseError.frameLengthMismatch }
        return try cs.decryptWithAd(ad: Data(), ciphertext: frame.suffix(from: 2))
    }

    private func assertInitiator() throws { if !initiator { throw NoiseError.wrongRole } }
    private func assertResponder() throws { if initiator { throw NoiseError.wrongRole } }
}
