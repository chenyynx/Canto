import XCTest
@testable import CantoAgentKit

// P3 mailbox v2 unit tests: HMAC tag, replay rejection, timestamp window,
// direction binding, codec round-trip.

final class CantoMailboxTests: XCTestCase {
    private let key = Data((0..<32).map { UInt8($0) })

    func testSealOpenRoundTrip() throws {
        var verifier = CantoMailboxVerifier(key: key)
        let msg = CantoMailboxMessage(direction: "app2ec", body: Data(#"{"cmd":"status"}"#.utf8))
        let wire = try CantoMailboxCodec.seal(msg, key: key)
        let opened = try CantoMailboxCodec.open(wire, key: key, expect: "app2ec", verifier: &verifier)
        XCTAssertEqual(opened.body, msg.body)
        XCTAssertEqual(opened.direction, "app2ec")
    }

    func testForgedTagRejected() throws {
        var verifier = CantoMailboxVerifier(key: key)
        var msg = CantoMailboxMessage(direction: "app2ec", body: Data("x".utf8))
        let wire = try CantoMailboxCodec.seal(msg, key: key)
        // Tamper the body: decode, mutate, re-encode keeping original tag.
        let decoder = JSONDecoder(); decoder.dataDecodingStrategy = .base64
        let encoder = JSONEncoder(); encoder.dataEncodingStrategy = .base64
        var obj = try decoder.decode(CantoTaggedEnvelope.self, from: wire)
        msg.body = Data("evil".utf8)
        obj.message = msg
        let tampered = try encoder.encode(obj)
        XCTAssertThrowsError(try CantoMailboxCodec.open(tampered, key: key, expect: "app2ec", verifier: &verifier)) {
            XCTAssertEqual($0 as? CantoMailboxError, .badTag)
        }
    }

    func testWrongKeyRejected() throws {
        var verifier = CantoMailboxVerifier(key: Data(repeating: 9, count: 32))
        let msg = CantoMailboxMessage(direction: "app2ec", body: Data("x".utf8))
        let wire = try CantoMailboxCodec.seal(msg, key: key)
        XCTAssertThrowsError(try CantoMailboxCodec.open(wire, key: Data(repeating: 1, count: 32), expect: "app2ec", verifier: &verifier)) {
            XCTAssertEqual($0 as? CantoMailboxError, .badTag)
        }
    }

    func testReplayRejected() throws {
        var verifier = CantoMailboxVerifier(key: key)
        let msg = CantoMailboxMessage(direction: "app2ec", body: Data("x".utf8))
        try verifier.verify(msg, expect: "app2ec")
        XCTAssertThrowsError(try verifier.verify(msg, expect: "app2ec")) {
            XCTAssertEqual($0 as? CantoMailboxError, .replayedNonce)
        }
    }

    func testStaleTimestampRejected() throws {
        var verifier = CantoMailboxVerifier(key: key, windowMs: 1_000)
        let old = CantoMailboxMessage(
            direction: "app2ec", body: Data("x".utf8),
            timestampMs: Int64(Date().timeIntervalSince1970 * 1000) - 10_000)
        XCTAssertThrowsError(try verifier.verify(old, expect: "app2ec")) {
            XCTAssertEqual($0 as? CantoMailboxError, .staleTimestamp)
        }
    }

    func testDirectionMismatchRejected() throws {
        var verifier = CantoMailboxVerifier(key: key)
        let msg = CantoMailboxMessage(direction: "ec2app", body: Data("x".utf8))
        XCTAssertThrowsError(try verifier.verify(msg, expect: "app2ec")) {
            XCTAssertEqual($0 as? CantoMailboxError, .wrongDirection("ec2app"))
        }
    }

    func testKeyLoadOrCreateIdempotent() {
        let defaults = UserDefaults(suiteName: "canto.mailbox.tests")!
        defaults.removePersistentDomain(forName: "canto.mailbox.tests")
        let k1 = CantoMailboxKey.loadOrCreate(defaults: defaults)
        let k2 = CantoMailboxKey.loadOrCreate(defaults: defaults)
        XCTAssertEqual(k1, k2)
        XCTAssertEqual(k1.count, 32)
        CantoMailboxKey.destroy(defaults: defaults)
        let k3 = CantoMailboxKey.loadOrCreate(defaults: defaults)
        XCTAssertNotEqual(k1, k3)
    }
}
