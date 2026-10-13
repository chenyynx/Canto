import XCTest
@testable import HakoAgentKit

// P3 mailbox v2 unit tests: HMAC tag, replay rejection, timestamp window,
// direction binding, codec round-trip.

final class AnchorMailboxTests: XCTestCase {
    private let key = Data((0..<32).map { UInt8($0) })

    func testSealOpenRoundTrip() throws {
        var verifier = AnchorMailboxVerifier(key: key)
        let msg = AnchorMailboxMessage(direction: "app2ec", body: Data(#"{"cmd":"status"}"#.utf8))
        let wire = try AnchorMailboxCodec.seal(msg, key: key)
        let opened = try AnchorMailboxCodec.open(wire, key: key, expect: "app2ec", verifier: &verifier)
        XCTAssertEqual(opened.body, msg.body)
        XCTAssertEqual(opened.direction, "app2ec")
    }

    func testForgedTagRejected() throws {
        var verifier = AnchorMailboxVerifier(key: key)
        var msg = AnchorMailboxMessage(direction: "app2ec", body: Data("x".utf8))
        let wire = try AnchorMailboxCodec.seal(msg, key: key)
        // Tamper the body: decode, mutate, re-encode keeping original tag.
        let decoder = JSONDecoder(); decoder.dataDecodingStrategy = .base64
        let encoder = JSONEncoder(); encoder.dataEncodingStrategy = .base64
        var obj = try decoder.decode([String: AnchorTaggedMessage].self, from: wire)
        msg.body = Data("evil".utf8)
        obj["msg"] = AnchorTaggedMessage(message: msg, tag: obj["msg"]!.tag)
        let tampered = try encoder.encode(obj)
        XCTAssertThrowsError(try AnchorMailboxCodec.open(tampered, key: key, expect: "app2ec", verifier: &verifier)) {
            XCTAssertEqual($0 as? AnchorMailboxError, .badTag)
        }
    }

    func testWrongKeyRejected() throws {
        var verifier = AnchorMailboxVerifier(key: Data(repeating: 9, count: 32))
        let msg = AnchorMailboxMessage(direction: "app2ec", body: Data("x".utf8))
        let wire = try AnchorMailboxCodec.seal(msg, key: key)
        XCTAssertThrowsError(try AnchorMailboxCodec.open(wire, key: Data(repeating: 1, count: 32), expect: "app2ec", verifier: &verifier)) {
            XCTAssertEqual($0 as? AnchorMailboxError, .badTag)
        }
    }

    func testReplayRejected() throws {
        var verifier = AnchorMailboxVerifier(key: key)
        let msg = AnchorMailboxMessage(direction: "app2ec", body: Data("x".utf8))
        try verifier.verify(msg, expect: "app2ec")
        XCTAssertThrowsError(try verifier.verify(msg, expect: "app2ec")) {
            XCTAssertEqual($0 as? AnchorMailboxError, .replayedNonce)
        }
    }

    func testStaleTimestampRejected() throws {
        var verifier = AnchorMailboxVerifier(key: key, windowMs: 1_000)
        let old = AnchorMailboxMessage(
            direction: "app2ec", body: Data("x".utf8),
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000) - 10_000)
        XCTAssertThrowsError(try verifier.verify(old, expect: "app2ec")) {
            XCTAssertEqual($0 as? AnchorMailboxError, .staleTimestamp)
        }
    }

    func testDirectionMismatchRejected() throws {
        var verifier = AnchorMailboxVerifier(key: key)
        let msg = AnchorMailboxMessage(direction: "ec2app", body: Data("x".utf8))
        XCTAssertThrowsError(try verifier.verify(msg, expect: "app2ec")) {
            XCTAssertEqual($0 as? AnchorMailboxError, .wrongDirection("ec2app"))
        }
    }

    func testKeyLoadOrCreateIdempotent() {
        let defaults = UserDefaults(suiteName: "anchor.mailbox.tests")!
        defaults.removePersistentDomain(forName: "anchor.mailbox.tests")
        let k1 = AnchorMailboxKey.loadOrCreate(defaults: defaults)
        let k2 = AnchorMailboxKey.loadOrCreate(defaults: defaults)
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1.count, 32)
        AnchorMailboxKey.destroy(defaults: defaults)
        let k3 = AnchorMailboxKey.loadOrCreate(defaults: defaults)
        XCTAssertNotEqual(k1, k3)
    }
}
