import XCTest
@testable import CantoAgentKit

/// 信封 + 路由 + 配对 URI：对 vectors.json（与 TS 契约测试同一套）。
final class EnvelopeVectorTests: XCTestCase {
    nonisolated(unsafe) static let vectors: [String: Any] = {
        let url = Bundle.module.url(forResource: "vectors", withExtension: "json")!
        let data = try! Data(contentsOf: url)
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        // vectors.json 有顶层 {vectors:{...}} 包裹；vectors-noise.json 顶层即内容
        return (obj["vectors"] as? [String: Any]) ?? obj
    }()

    // MARK: envelope 合法向量

    func testEnvelopeValidVectors() throws {
        let list = Self.vectors["envelopeValid"] as! [[String: Any]]
        XCTAssertGreaterThanOrEqual(list.count, 9)
        for v in list {
            let json = try JSONSerialization.data(withJSONObject: v["data"] as! [String: Any])
            let e = try JSONDecoder().decode(Envelope.self, from: json)
            XCTAssertNil(e.validate(), "向量 \(v["name"] as? String ?? "?") 应通过不变量校验")
        }
    }

    func testEnvelopeInvalidVectors() throws {
        let list = Self.vectors["envelopeInvalid"] as! [[String: Any]]
        XCTAssertGreaterThanOrEqual(list.count, 7)
        var rejected = 0
        for v in list {
            guard let data = v["data"] as? [String: Any] else { continue }
            let json = try JSONSerialization.data(withJSONObject: data)
            if let e = try? JSONDecoder().decode(Envelope.self, from: json) {
                if e.validate() != nil { rejected += 1 }
            } else {
                rejected += 1
            }
        }
        XCTAssertEqual(rejected, list.count, "全部非法向量都应被拒")
    }

    /// 附加字段向后兼容（未知字段忽略而非拒绝）
    func testForwardCompatible() throws {
        var base = (Self.vectors["envelopeValid"] as! [[String: Any]])[0]["data"] as! [String: Any]
        base["futureField"] = ["anything": true]
        let json = try JSONSerialization.data(withJSONObject: base)
        let e = try JSONDecoder().decode(Envelope.self, from: json)
        XCTAssertNil(e.validate())
    }

    /// ttl 边界（1000..600000）
    func testTtlBounds() throws {
        func make(_ ttl: Int) throws -> Envelope {
            var base = (Self.vectors["envelopeValid"] as! [[String: Any]])[0]["data"] as! [String: Any]
            base["ttl_ms"] = ttl
            return try JSONDecoder().decode(Envelope.self, from: JSONSerialization.data(withJSONObject: base))
        }
        XCTAssertNil(try make(1000).validate())
        XCTAssertNil(try make(600000).validate())
        XCTAssertEqual(try make(999).validate(), .badTtl)
        XCTAssertEqual(try make(600001).validate(), .badTtl)
    }

    // MARK: 路由向量

    func testRoutingVectors() throws {
        let routes = Self.vectors["routing"] as! [[String: Any]]
        for r in routes {
            XCTAssertEqual(routeOf(r["op"] as! String), r["expectCh"] as? String, "\(r["op"] as! String)")
        }
        XCTAssertEqual(routeOf("app.unknown"), "app", "未知 app.* 仍属 app 通道")
        XCTAssertEqual(routeOf("bogus"), nil)
    }

    // MARK: 配对 URI 向量

    func testPairingURIVectors() throws {
        let p = Self.vectors["pairing"] as! [String: Any]
        for uri in p["uriValid"] as! [String] {
            let parsed = try PairingURI.parse(uri)
            XCTAssertEqual(parsed.k.count, 43, "k 应为 43 base64url 字符")
            XCTAssertEqual(parsed.secret.count, 22)
            XCTAssertTrue(parsed.endpoints.count >= 1)
            let re = try PairingURI.parse(parsed.encoded())
            XCTAssertEqual(re.k, parsed.k)
            XCTAssertEqual(re.secret, parsed.secret)
            XCTAssertEqual(re.endpoints, parsed.endpoints)
        }
        for uri in p["uriInvalid"] as! [String] {
            XCTAssertThrowsError(try PairingURI.parse(uri), "应拒绝：\(uri)")
        }
    }

    // MARK: 配对 payload 向量

    func testPairingPayloadVectors() throws {
        let p = Self.vectors["pairing"] as! [String: Any]
        let helloExt = p["helloExt"] as! [String: Any]
        XCTAssertNotNil(helloExt["session_epoch"], "ext hello 必须带 epoch")
        let helloApp = p["helloApp"] as! [String: Any]
        XCTAssertNil(helloApp["session_epoch"], "app hello 不应带 epoch")
        let degraded = p["helloResDegradedA"] as! [String: Any]
        let dg = degraded["degraded"] as? [String: Any]
        XCTAssertEqual(dg?["level"] as? String, "A")
        let revoked = p["helloResRevoked"] as? [String: Any]
        XCTAssertEqual(revoked?["ok"] as? Bool, false)
        XCTAssertEqual(revoked?["reason"] as? String, "REVOKED")
    }

    // MARK: ops 向量（Swift 侧轻校验，Schema 全量校验以 TS/Ajv 为准）

    func testOpsVectors() throws {
        let valid = Self.vectors["opsValid"] as! [[String: Any]]
        XCTAssertGreaterThanOrEqual(valid.count, 20)
        for v in valid {
            XCTAssertEqual(routeOf(v["op"] as! String), v["ch"] as? String, "\(v["op"] as! String)")
        }
        let invalid = Self.vectors["opsInvalid"] as! [[String: Any]]
        XCTAssertGreaterThanOrEqual(invalid.count, 7)
    }
}
