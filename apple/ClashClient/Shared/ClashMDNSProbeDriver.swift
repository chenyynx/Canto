import Foundation

 
 
 
 
 
 
 
 
 
enum ClashMDNSProbeDriver {
    struct Spec: Equatable {
        let names: [String]
        let repeatCount: Int
        let concurrent: Int
         
        let dnsServer: String

        init?(json: String) {
            guard let data = json.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let names = root["names"] as? [String], !names.isEmpty
            else { return nil }
            self.names = names
            repeatCount = max(1, root["repeat"] as? Int ?? 10)
            concurrent = max(1, root["concurrent"] as? Int ?? 40)
            dnsServer = root["dnsServer"] as? String ?? "198.18.0.2"
        }
    }

     
     
    struct Outcome {
        let status: Int?
        let answers: [String]
        let error: String?

        init(replyJSON: String) {
            guard let data = replyJSON.data(using: .utf8),
                  let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            else {
                status = nil; answers = []; error = "unreadable reply"; return
            }
            if let message = root["error"] as? String {
                status = nil; answers = []; error = message; return
            }
            status = (root["Status"] as? NSNumber)?.intValue
            answers = ((root["Answer"] as? [[String: Any]]) ?? []).compactMap { $0["data"] as? String }
            error = nil
        }
    }

    static func line(phase: String, name: String, type: String, outcome: Outcome, milliseconds: Int) -> String {
        var text = "mdns probe: phase=\(phase) name=\(name) type=\(type)"
        if let error = outcome.error {
            text += " error=\(error)"
        } else {
            text += " status=\(outcome.status ?? -1) answers=\(outcome.answers.count)"
            if let first = outcome.answers.first { text += " data=\(first)" }
        }
        return text + " ms=\(milliseconds)"
    }

    static func percentile(_ values: [Int], _ p: Int) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let rank = max(0, min(sorted.count - 1, Int((Double(p) / 100 * Double(sorted.count)).rounded(.up)) - 1))
        return sorted[rank]
    }

     
     
     
     
     
     
     
     
    static func run(
        spec: Spec,
        query: @escaping @Sendable (String, String) async throws -> Data,
        concurrentQuery: (@Sendable (String, String) async throws -> Data)? = nil,
        memory: @escaping @Sendable () async -> Int64?,
        log: @escaping @Sendable (String) -> Void
    ) async {
        let direct = concurrentQuery ?? query
        @Sendable func ask(_ phase: String, _ name: String, _ type: String) async -> (Outcome, Int) {
            let began = Date()
            let outcome: Outcome
            do {
                let reply = try await (phase == "concurrent" ? direct(name, type) : query(name, type))
                outcome = Outcome(replyJSON: String(decoding: reply, as: UTF8.self))
            } catch {
                outcome = Outcome(replyJSON: "{\"error\":\"channel: \(error.localizedDescription)\"}")
            }
            let milliseconds = Int(Date().timeIntervalSince(began) * 1000)
            log(line(phase: phase, name: name, type: type, outcome: outcome, milliseconds: milliseconds))
            return (outcome, milliseconds)
        }

        let memoryBefore = await memory()
        log("mdns probe: started names=\(spec.names.joined(separator: ",")) repeat=\(spec.repeatCount) concurrent=\(spec.concurrent) memoryBefore=\(memoryBefore ?? -1)")
        for name in spec.names {
            for type in ["A", "AAAA"] {
                _ = await ask("single", name, type)
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
         
         
        _ = await ask("again", spec.names[0], "A")

        var latencies: [Int] = []
        for _ in 0..<spec.repeatCount {
            latencies.append(await ask("repeat", spec.names[0], "A").1)
            try? await Task.sleep(nanoseconds: 200_000_000)
        }

         
         
         
         
         
        let target = spec.names[spec.names.count - 1]
        let concurrentOutcomes = await withTaskGroup(of: (Outcome, Int).self, returning: [(Outcome, Int)].self) { group in
            for _ in 0..<spec.concurrent {
                group.addTask { await ask("concurrent", target, "A") }
            }
            var collected: [(Outcome, Int)] = []
            for await outcome in group { collected.append(outcome) }
            return collected
        }
        let refused = concurrentOutcomes.filter { $0.0.error?.contains("too many") == true }.count
        let answered = concurrentOutcomes.filter { $0.0.error == nil }.count
        try? await Task.sleep(nanoseconds: 60_000_000_000)
        let memoryAfter = await memory()
        log("mdns probe: summary repeat=\(latencies.count) p50=\(percentile(latencies, 50)) max=\(percentile(latencies, 100)) concurrent=\(spec.concurrent) answered=\(answered) refused=\(refused) memoryBefore=\(memoryBefore ?? -1) memoryAfter=\(memoryAfter ?? -1)")
    }
}
