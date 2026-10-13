import XCTest
@testable import HakoAgentKit
import Crypto

/// Noise 黄金向量互验（vectors-noise.json，TS 侧 gen-noise-vectors.ts 生成）。
final class NoiseVectorTests: XCTestCase {
    nonisolated(unsafe) static let vectors: [String: Any] = {
        let url = Bundle.module.url(forResource: "vectors-noise", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }()

    func testProtocolConstantsMatch() {
        let p = Self.vectors["primitives"] as! [String: Any]
        XCTAssertEqual(AnchorProtocol.protocolName, p["protocol_name"] as! String)
        XCTAssertEqual(NoisePrimitives.h0, Data(hex: p["h0"] as! String))
        XCTAssertEqual(AnchorProtocol.maxPlaintext, 65519)
    }

    /// 原语·DH：RFC 7748 测试密钥共享密钥逐字节一致
    func testDHSharedSecret() throws {
        let d = (Self.vectors["primitives"] as! [String: Any])["dh"] as! [String: Any]
        let alice = DHKey.fromRawPrivate(Data(hex: d["alice_priv"] as! String))
        let bob = DHKey.fromRawPrivate(Data(hex: d["bob_priv"] as! String))
        XCTAssertEqual(alice.pub, Data(hex: d["alice_pub"] as! String), "公钥推导须与 RFC 一致")
        XCTAssertEqual(bob.pub, Data(hex: d["bob_pub"] as! String))
        let s1 = alice.shared(with: bob.pub)
        let s2 = bob.shared(with: alice.pub)
        XCTAssertEqual(s1, s2)
        XCTAssertEqual(s1, Data(hex: d["shared"] as! String))
    }

    /// 原语·HKDF：两段输出逐字节一致
    func testHKDF() throws {
        let h = (Self.vectors["primitives"] as! [String: Any])["hkdf2"] as! [String: Any]
        let outs = NoisePrimitives.hkdf(ck: Data(hex: h["ck"] as! String), ikm: Data(hex: h["ikm"] as! String))
        XCTAssertEqual(outs.count, 2)
        XCTAssertEqual(outs[0], Data(hex: h["t1"] as! String))
        XCTAssertEqual(outs[1], Data(hex: h["t2"] as! String))
    }

    /// 原语·AES-256-GCM：密文逐字节一致（含 16B tag 拼接布局）+ 往返
    func testAESGCM() throws {
        let a = (Self.vectors["primitives"] as! [String: Any])["aes_gcm"] as! [String: Any]
        let key = SymmetricKey(data: Data(hex: a["key"] as! String))
        let nonce = try AES.GCM.Nonce(data: Data(hex: a["nonce"] as! String))
        let ad = Data(hex: a["ad"] as! String)
        let pt = Data(hex: a["plaintext"] as! String)
        let sealed = try AES.GCM.seal(pt, using: key, authenticating: ad, nonce: nonce)
        XCTAssertEqual(sealed.ciphertext + sealed.tag, Data(hex: a["ciphertext"] as! String))
        let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: sealed.ciphertext, tag: sealed.tag)
        XCTAssertEqual(try AES.GCM.open(box, using: key, authenticating: ad), pt)
    }

    /// 原语·nonce 布局（4B 零 + LE 计数）
    func testNonceLayout() {
        XCTAssertEqual(NoisePrimitives.nonce12(0), Data(repeating: 0, count: 12))
        XCTAssertEqual(NoisePrimitives.nonce12(1), Data([0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0]))
        XCTAssertEqual(NoisePrimitives.nonce12(7), Data([0, 0, 0, 0, 7, 0, 0, 0, 0, 0, 0, 0]))
    }

    /// 原语·mixHash
    func testMixHash() throws {
        let m = (Self.vectors["primitives"] as! [String: Any])["mixHash"] as! [String: Any]
        let out = NoisePrimitives.mixHash(NoisePrimitives.h0, Data(hex: m["input"] as! String))
        XCTAssertEqual(out, Data(hex: m["output"] as! String))
    }

    /// 握手往返不变量（m1/m2/m3 尺寸、rs 匹配、载荷完整、传输帧双向互通）
    func testHandshakeRoundTripInvariants() throws {
        let hs = Self.vectors["handshake"] as! [String: Any]
        let agentKey = DHKey.generate()
        let dev = NoiseXX(initiator: true, staticKey: DHKey.generate(), remoteStatic: agentKey.pub)
        let agent = NoiseXX(initiator: false, staticKey: agentKey)

        let m1 = try dev.writeMsg1()
        XCTAssertEqual(m1.count, 32, "m1 = 32B 临时公钥")
        try agent.readMsg1(m1)

        let m2 = try agent.writeMsg2()
        XCTAssertEqual(m2.count, 32 + 48, "m2 = re(32) || ct(rs)(48)（空载荷）")
        let (rs, m2Payload) = try dev.readMsg2(m2)
        XCTAssertEqual(rs, agentKey.pub, "发起方必须验证出 agent 静态公钥")
        XCTAssertEqual(m2Payload.count, 0)

        let payload = Data(hex: hs["m3_payload"] as! String)
        let m3 = try dev.writeMsg3(payload: payload)
        XCTAssertEqual(m3.count, 48 + payload.count + 16, "m3 = ct(s.pub)(48) || ct(payload)")
        let gotPayload = try agent.readMsg3(m3)
        XCTAssertEqual(gotPayload, payload)

        XCTAssertTrue(dev.handshakeComplete && agent.handshakeComplete)
        XCTAssertEqual(dev.remoteStatic, agentKey.pub)

        for t in hs["traffic"] as! [[String: Any]] {
            let dir = t["dir"] as! String
            let expectedPt = Data(hex: t["plaintext"] as! String)
            let expectedFrame = Data(hex: t["frame"] as! String)
            if dir == "d2a" {
                let frame = try dev.send(expectedPt)
                XCTAssertEqual(frame.count, expectedPt.count + 18, "帧 = 2B 长度头 + 明文 + 16B tag")
                XCTAssertEqual(try agent.recv(frame), expectedPt)
                XCTAssertEqual(frame.count, expectedFrame.count)
            } else {
                let frame = try agent.send(expectedPt)
                XCTAssertEqual(try dev.recv(frame), expectedPt)
                XCTAssertEqual(frame.count, expectedFrame.count)
            }
        }
    }

    /// 密钥方向性：四方向独立，自发自收必败
    func testKeyDirectionality() throws {
        let agentKey = DHKey.generate()
        let dev = NoiseXX(initiator: true, staticKey: DHKey.generate(), remoteStatic: agentKey.pub)
        let agent = NoiseXX(initiator: false, staticKey: agentKey)
        try agent.readMsg1(dev.writeMsg1())
        _ = try dev.readMsg2(agent.writeMsg2())
        _ = try agent.readMsg3(dev.writeMsg3())

        let a2b = try dev.send(Data("x".utf8))
        XCTAssertEqual(try agent.recv(a2b), Data("x".utf8))
        let b2a = try agent.send(Data("y".utf8))
        XCTAssertEqual(try dev.recv(b2a), Data("y".utf8))
        XCTAssertThrowsError(try dev.recv(try dev.send(Data("z".utf8))))
        XCTAssertThrowsError(try agent.recv(try agent.send(Data("z".utf8))))
    }

    /// 篡改/截断/错序/越权 全被拒
    func testTamperAndGuards() throws {
        let agentKey = DHKey.generate()
        let dev = NoiseXX(initiator: true, staticKey: DHKey.generate(), remoteStatic: agentKey.pub)
        let agent = NoiseXX(initiator: false, staticKey: agentKey)
        try agent.readMsg1(dev.writeMsg1())
        _ = try dev.readMsg2(agent.writeMsg2())
        _ = try agent.readMsg3(dev.writeMsg3())

        var frame = try dev.send(Data("secret".utf8))
        frame[frame.count - 1] ^= 0x01
        XCTAssertThrowsError(try agent.recv(frame), "篡改密文 → GCM 认证失败")

        let f2 = try dev.send(Data("secret".utf8))
        XCTAssertThrowsError(try agent.recv(f2.prefix(f2.count - 1)), "截断 → 长度不符")

        XCTAssertThrowsError(try dev.send(Data(count: AnchorProtocol.maxPlaintext + 1)), "帧超限")
        XCTAssertEqual(try dev.send(Data(count: AnchorProtocol.maxPlaintext)).count, AnchorProtocol.maxPlaintext + 18)

        let k = DHKey.generate()
        let d2 = NoiseXX(initiator: true, staticKey: k)
        let a2 = NoiseXX(initiator: false, staticKey: k)
        XCTAssertThrowsError(try a2.writeMsg1(), "角色互斥")
        XCTAssertThrowsError(try d2.readMsg1(Data(count: 32)))
        XCTAssertThrowsError(try dev.writeMsg3(), "错序")
        XCTAssertThrowsError(try agent.readMsg3(Data(count: 80)))
        XCTAssertThrowsError(try d2.send(Data("x".utf8)), "握手未完成不能发")
        XCTAssertThrowsError(try a2.recv(Data(repeating: 0, count: 18)), "握手未完成不能收")
    }

    /// ID 派生：与 TS 同法（SHA-256 前 10 字节 → Crockford）
    func testIDDerivation() {
        let pub = Data(hex: "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a")
        let id = AnchorIDs.agentIdFromPub(pub)
        XCTAssertEqual(id.count, 16)
        XCTAssertTrue(AnchorIDs.isAgentId(id))
        XCTAssertEqual(AnchorIDs.agentIdFromPub(pub), id, "同公钥同 id")
        XCTAssertTrue(AnchorIDs.isDeviceId(AnchorIDs.deviceIdFromPub(pub)))
        XCTAssertFalse(AnchorIDs.isDeviceId("dev_short"))
        let u = AnchorIDs.ulid()
        XCTAssertEqual(u.count, 26)
        XCTAssertTrue(AnchorIDs.isUlid(u))
        let a = AnchorIDs.ulid(now: 1_750_000_000_000)
        let b = AnchorIDs.ulid(now: 1_750_000_000_000)
        let c = AnchorIDs.ulid(now: 1_750_000_000_000)
        XCTAssertTrue(a < b && b < c, "同毫秒单调递增：\(a) < \(b) < \(c)")
    }
}

extension Data {
    init(hex: String) {
        self.init()
        var i = hex.startIndex
        while i < hex.endIndex {
            let next = hex.index(i, offsetBy: 2)
            self.append(UInt8(hex[i..<next], radix: 16)!)
            i = next
        }
    }
}
