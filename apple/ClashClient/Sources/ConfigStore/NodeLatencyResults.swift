import Foundation

 
 
 
 
 
 
 
 
 
 
final class NodeLatencyResultStore: @unchecked Sendable {
    struct Reading: Codable, Equatable {
         
        let milliseconds: Int
        let measuredAt: Date
    }

     
     
     
    static let readingsPerProfile = 4_000

    private let fileURL: URL
    private let lock = NSLock()
    private var table: [String: [String: Reading]]?
    private let writer = DispatchQueue(label: "clash.node-latency-results", qos: .utility)

    init(fileURL: URL) {
        self.fileURL = fileURL
    }

    static func live() -> NodeLatencyResultStore? {
        guard let support = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        return NodeLatencyResultStore(
            fileURL: support.appendingPathComponent("node-latency-results.json")
        )
    }

     
    func readings(profile: String) -> [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return (loadedTable()[profile] ?? [:]).mapValues(\.milliseconds)
    }

     
     
    func record(_ results: [String: Int], profile: String, at date: Date = Date()) {
        guard !results.isEmpty else { return }
        lock.lock()
        var all = loadedTable()
        var readings = all[profile] ?? [:]
        for (name, milliseconds) in results {
            readings[name] = Reading(milliseconds: milliseconds > 0 ? milliseconds : -1, measuredAt: date)
        }
        if readings.count > Self.readingsPerProfile {
            let kept = readings.sorted { $0.value.measuredAt > $1.value.measuredAt }
                .prefix(Self.readingsPerProfile)
            readings = Dictionary(uniqueKeysWithValues: kept.map { ($0.key, $0.value) })
        }
        all[profile] = readings
        table = all
        let snapshot = all
        lock.unlock()
        let fileURL = fileURL
        writer.async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try? data.write(to: fileURL, options: .atomic)
        }
    }

     
    func flush() {
        writer.sync {}
    }

     
    private func loadedTable() -> [String: [String: Reading]] {
        if let table { return table }
        let loaded = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode([String: [String: Reading]].self, from: $0) } ?? [:]
        table = loaded
        return loaded
    }
}
