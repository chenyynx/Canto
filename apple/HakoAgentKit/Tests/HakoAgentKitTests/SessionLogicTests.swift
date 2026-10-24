import XCTest
@testable import HakoAgentKit

/// 会话状态机 / 去重 / 退避（Swift 侧逻辑单测）。
final class SessionLogicTests: XCTestCase {

    func testDeduperRejectsReplay() {
        var d = Deduper()
        let id = "01J9ZK3Q8M2XTR4QK7YF0A1B2C"
        XCTAssertTrue(d.checkAndInsert(id, now: 1_000), "首次应放行")
        XCTAssertFalse(d.checkAndInsert(id, now: 2_000), "重放应被拒")
        XCTAssertFalse(d.checkAndInsert(id, now: 3_000))
    }

    func testDeduperWindowExpiry() {
        var d = Deduper(windowMs: 1_000)
        let id = "01J9ZK3Q8M2XTR4QK7YF0A1B2D"
        XCTAssertTrue(d.checkAndInsert(id, now: 0))
        XCTAssertFalse(d.checkAndInsert(id, now: 500))
        XCTAssertTrue(d.checkAndInsert(id, now: 1_500), "窗口过期后应放行")
    }

    func testDeduperCapacityEviction() {
        var d = Deduper(capacity: 8)
        for i in 0..<10 {
            d.checkAndInsert("id_\(i)", now: 1_000)
        }
        XCTAssertTrue(d.checkAndInsert("id_0", now: 2_000), "最早条目已逐出，可再次插入")
        XCTAssertTrue(d.checkAndInsert("id_1", now: 2_000))
        XCTAssertFalse(d.checkAndInsert("id_9", now: 2_000), "最近条目仍在")
    }

    func testDeduperIdemDefaultsToId() {
        var d = Deduper()
        let id = "01J9ZK3Q8M2XTR4QK7YF0A1B2E"
        XCTAssertTrue(d.checkAndInsert(id, now: 0, idem: nil))
        XCTAssertFalse(d.checkAndInsert(id, now: 1, idem: id))
    }

    func testBackoffExponentialCapped() {
        var b = Backoff(baseMs: 500, maxMs: 8_000)
        XCTAssertEqual(b.next(), 500)
        XCTAssertEqual(b.next(), 1_000)
        XCTAssertEqual(b.next(), 2_000)
        XCTAssertEqual(b.next(), 4_000)
        XCTAssertEqual(b.next(), 8_000)
        XCTAssertEqual(b.next(), 8_000, "触顶后不再增长")
        b.reset()
        XCTAssertEqual(b.next(), 500, "reset 后回到基线")
    }

    func testBackoffJitterRange() {
        var b = Backoff(baseMs: 1_000, maxMs: 60_000, jitterRatio: 0.2)
        for _ in 0..<20 {
            let v = b.next()
            XCTAssertGreaterThanOrEqual(v, 1_000)
            XCTAssertLessThanOrEqual(v, 60_000)
        }
    }

    func testSeqAllocator() {
        var s = SeqAllocator()
        XCTAssertEqual(s.next(), 0)
        XCTAssertEqual(s.next(), 1)
        XCTAssertEqual(s.next(), 2)
        s.reset(to: 5)
        XCTAssertEqual(s.next(), 5)
    }
}
