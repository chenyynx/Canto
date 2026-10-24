import Foundation

/// 接收方去重表（对齐 envelope 语义：保留最近 N 条 / 窗口内）。
public struct Deduper {
    private let capacity: Int
    private let windowMs: Int64
    /// FIFO 逐出
    private var entries: [Entry] = []
    private var index: Set<String> = []

    private struct Entry {
        let idem: String
        let at: Int64
    }

    public init(capacity: Int = 256, windowMs: Int64 = 600_000) {
        self.capacity = capacity
        self.windowMs = windowMs
    }

    /// 放行 = true（并记录）；重复 = false
    public mutating func checkAndInsert(_ id: String, now: Int64, idem: String? = nil) -> Bool {
        let key = idem ?? id
        entries = entries.filter { now - $0.at <= windowMs }
        index = Set(entries.map(\.idem))
        if index.contains(key) { return false }
        entries.append(Entry(idem: key, at: now))
        index.insert(key)
        while entries.count > capacity {
            let evicted = entries.removeFirst()
            index.remove(evicted.idem)
        }
        return true
    }

    public var count: Int { entries.count }
}

/// 重连退避：指数增长 + 上限 + 可选比例抖动。
public struct Backoff {
    private let baseMs: Int
    private let maxMs: Int
    private let jitterRatio: Double
    private(set) var attempt: Int = 0

    public init(baseMs: Int = 500, maxMs: Int = 30_000, jitterRatio: Double = 0) {
        precondition(baseMs > 0 && maxMs >= baseMs)
        precondition((0.0...1.0).contains(jitterRatio))
        self.baseMs = baseMs
        self.maxMs = maxMs
        self.jitterRatio = jitterRatio
    }

    public mutating func next() -> Int {
        let nominal = min(baseMs << min(attempt, 30), maxMs)
        attempt += 1
        guard jitterRatio > 0 else { return nominal }
        let span = Int(Double(nominal) * jitterRatio)
        return min(nominal + Int.random(in: 0...max(span, 0)), maxMs)
    }

    public mutating func reset() {
        attempt = 0
    }
}

/// 每通道发送序号分配（envelope.seq 语义：单调递增从 0）。
public struct SeqAllocator {
    private(set) var current: Int = -1
    public init() {}
    public mutating func next() -> Int {
        current += 1
        return current
    }
    public mutating func reset(to v: Int) { current = v - 1 }
}
