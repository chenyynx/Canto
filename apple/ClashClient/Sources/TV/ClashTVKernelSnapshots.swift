import Foundation
import ClashClientKit
import CoreFoundation

 
 
 
 
 
 
 
 
 
 
 
 
 
enum ClashTVKernelSnapshots {
     
     
     
     
     
     
     
    static func urlTestDelay(from reply: Data?) throws -> Int {
        guard let reply,
              let object = try JSONSerialization.jsonObject(with: reply) as? [String: Any],
              let delay = object["delay"] as? Int
        else { return -1 }
        return delay
    }

    enum DecodingError: LocalizedError {
        case notAnObject(String)
        case kernelError(String)

        var errorDescription: String? {
            switch self {
            case .notAnObject(let what): "The tunnel's \(what) reply was not in the expected shape."
            case .kernelError(let message): message
            }
        }
    }

    struct Proxies: Equatable {
        let groups: [ClashProxyGroupSnapshot]
         
         
         
         
         
        let hiddenGroups: [ClashProxyGroupSnapshot]
        let latency: [String: ClashProxyLatencyState]
         
        let nodeCount: Int
         
         
        let configuredNodes: Set<String>
         
         
        let selections: [String: GroupSelection]
         
         
         
        let easyTierPlaceholders: Set<String>
         
         
        var readingURLs: [String: String] = [:]
    }

    struct Traffic: Equatable {
        let up: Int64
        let down: Int64
        let upTotal: Int64
        let downTotal: Int64
        let memory: Int64
        var hasTotals: Bool = true
        var hasRates: Bool = true
    }

    struct Status: Equatable {
        let status: String
        let mode: String
    }

    private static func object(_ data: Data, what: String) throws -> [String: Any] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DecodingError.notAnObject(what)
        }
        if root.count == 1 || root["errorKey"] != nil, let refusal = refusal(in: root) {
            throw DecodingError.kernelError(refusal.text)
        }
        return root
    }

     
     
     
    static func readerFacing(_ reply: Data) -> Data {
        guard var root = try? JSONSerialization.jsonObject(with: reply) as? [String: Any],
              root["errorKey"] != nil, let refusal = refusal(in: root) else { return reply }
        root["error"] = refusal.text
        root["errorKey"] = nil
        root["errorArguments"] = nil
        return (try? JSONSerialization.data(withJSONObject: root)) ?? reply
    }

     
     
     
    static func refusal(in root: [String: Any]) -> AuthoredText? {
        guard let error = root["error"] as? String else { return nil }
        if let key = root["errorKey"] as? String, !key.isEmpty {
            return .app(key, arguments: root["errorArguments"] as? [String] ?? [])
        }
        return .verbatim(error)
    }

     
    struct ProxyDelays: Equatable {
         
         
         
        let revision: String?
         
         
        let selections: [String: GroupSelection]
        let latency: [String: ClashProxyLatencyState]

         
         
         
         
        func mark(shown: [String: GroupSelection], after previous: DocumentMark?) -> DocumentMark {
            .init(revision: revision, selections: selections, shown: shown,
                  rechecked: previous.map {
                      $0.revision == revision && $0.selections == selections && $0.shown != $0.selections
                  } ?? false)
        }

         
         
         
         
         
         
         
         
        func needsDocument(since mark: DocumentMark?) -> Bool {
            guard let mark else { return true }
            if mark.revision != revision || mark.selections != selections { return true }
            return mark.shown != selections && !mark.rechecked
        }
    }

    struct GroupSelection: Equatable {
        let now: String?
        let fixed: String?
    }

    struct DocumentMark: Equatable {
         
        let revision: String?
        let selections: [String: GroupSelection]
         
        let shown: [String: GroupSelection]
        let rechecked: Bool
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func proxyDelays(from data: Data, configured: Set<String> = []) throws -> ProxyDelays {
        let root = try object(data, what: "proxy delays")
        guard let configuredRecords = root["proxies"] as? [String: [String: Any]],
              let providers = root["providers"] as? [String: [String: [String: Any]]] else {
            throw DecodingError.notAnObject("proxy delays")
        }
        let groups = root["groups"] as? [String: [String: Any]] ?? [:]
        func reading(_ record: [String: Any]) -> ClashProxyLatencyState? {
            guard let delay = (record["delay"] as? NSNumber)?.intValue else { return nil }
            return delay > 0 ? .measured(milliseconds: delay) : .failed
        }
         
         
         
        var newest: [String: (time: String?, state: ClashProxyLatencyState)] = [:]
        for name in providers.keys.sorted() {
            for (node, record) in providers[name] ?? [:] {
                guard let state = reading(record) else { continue }
                let time = record["time"] as? String
                if let held = newest[node] {
                    guard let time, let next = RecordTime(time) else { continue }
                    if let last = held.time.flatMap(RecordTime.init), !(next > last) { continue }
                }
                newest[node] = (time, state)
            }
        }
        var latency = newest.mapValues(\.state)
        for name in configured.union(groups.keys) { latency[name] = nil }
        for (node, record) in configuredRecords { latency[node] = reading(record) }
        for (group, record) in groups { latency[group] = reading(record) }
        return ProxyDelays(
            revision: root["revision"] as? String,
            selections: groups.mapValues { .init(now: $0["now"] as? String, fixed: $0["fixed"] as? String) },
            latency: latency
        )
    }

     

     
     
     
    struct DelayPage: Equatable {
        let revision: String?
        let now: Int64?
        let next: String?
        let selections: [String: GroupSelection]
         
         
        let configured: [String: ClashProxyLatencyState?]
         
         
        var configuredURLs: [String: [String: ClashProxyLatencyState?]] = [:]
         
        let groups: [String: ClashProxyLatencyState?]
         
        let providers: [String: [String: DelayRecord]]
    }

    struct DelayRecord: Equatable {
        let time: String?
        let state: ClashProxyLatencyState?
         
        var urls: [String: DelayRecord] = [:]
    }

    static func proxyDelaysPage(from data: Data) throws -> DelayPage {
        let root = try object(data, what: "proxy delays")
        guard let configuredRecords = root["proxies"] as? [String: [String: Any]],
              let providers = root["providers"] as? [String: [String: [String: Any]]] else {
            throw DecodingError.notAnObject("proxy delays")
        }
        let groups = root["groups"] as? [String: [String: Any]] ?? [:]
        return DelayPage(
            revision: root["revision"] as? String,
            now: (root["now"] as? NSNumber)?.int64Value,
            next: (root["next"] as? String).flatMap { $0.isEmpty ? nil : $0 },
             
             
            selections: groups.mapValues { .init(now: nonEmpty($0["now"]), fixed: nonEmpty($0["fixed"])) },
            configured: configuredRecords.mapValues(reading),
            configuredURLs: configuredRecords.compactMapValues { urlRecords($0)?.mapValues(\.state) },
            groups: groups.mapValues(reading),
            providers: providers.mapValues {
                $0.mapValues { DelayRecord(time: $0["time"] as? String, state: reading($0), urls: urlRecords($0) ?? [:]) }
            }
        )
    }

     
     
    private static func urlRecords(_ record: [String: Any]) -> [String: DelayRecord]? {
        guard let extra = record["extra"] as? [String: [String: Any]], !extra.isEmpty else { return nil }
        return extra.mapValues { DelayRecord(time: $0["time"] as? String, state: reading($0)) }
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        (value as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

     
     
     
    private static func reading(_ record: [String: Any]) -> ClashProxyLatencyState? {
        guard let delay = (record["delay"] as? NSNumber)?.intValue else { return nil }
        return delay > 0 ? .measured(milliseconds: delay) : .failed
    }

     

     
     
    static let kernelDefaultTestURL = "https://www.gstatic.com/generate_204"

     
     
     
     
     
     
     
     
     
     
    static func readingURL(type: String, testURL: String?) -> String? {
        let kind = type.lowercased().filter { $0 != "-" && $0 != "_" && $0 != " " }
        guard ["urltest", "fallback", "loadbalance"].contains(kind) else { return nil }
        return testURL.flatMap { $0.isEmpty ? nil : $0 } ?? kernelDefaultTestURL
    }

     
     
    static func latencyKey(_ name: String, readingURL: String?) -> String {
        guard let readingURL else { return name }
        return urlRecordMark + readingURL + urlRecordMark + name
    }

     
    static func urlRecord(of key: String) -> (url: String, name: String)? {
        guard key.hasPrefix(urlRecordMark) else { return nil }
        let rest = key.dropFirst()
        guard let mark = rest.firstIndex(of: Character(urlRecordMark)) else { return nil }
        return (String(rest[..<mark]), String(rest[rest.index(after: mark)...]))
    }

     
    private static let urlRecordMark = "\u{1F}"

     
     
     
     
     
     
     
     
     
     
     
     
     
    struct DelayBook: Equatable {
        private(set) var revision: String?
        private(set) var selections: [String: GroupSelection] = [:]
        private(set) var latency: [String: ClashProxyLatencyState] = [:]
        private var configured: [String: ClashProxyLatencyState] = [:]
        private var groups: [String: ClashProxyLatencyState?] = [:]
        private var providers: [String: [String: DelayRecord]] = [:]
        private(set) var configuredNames: Set<String> = []
         
         
        private(set) var readingURLs: Set<String> = []
        private var configuredURLs: [String: [String: ClashProxyLatencyState?]] = [:]

         
         
        mutating func reset(revision: String?) {
            let urls = readingURLs
            self = DelayBook()
            self.revision = revision
            readingURLs = urls
        }

         
         
         
         
        @discardableResult
        mutating func follow(urls: Set<String>) -> Set<String> {
            let gone = readingURLs.subtracting(urls)
            readingURLs = urls
            guard !gone.isEmpty else { return [] }
            configuredURLs = configuredURLs.mapValues { $0.filter { urls.contains($0.key) } }
            providers = providers.mapValues { $0.mapValues { record in
                var kept = record
                kept.urls = record.urls.filter { urls.contains($0.key) }
                return kept
            } }
            let moved = Set(latency.keys.filter { key in urlRecord(of: key).map { gone.contains($0.url) } ?? false })
            recompute(moved)
            return moved
        }

         
        private func keys(of name: String) -> [String] {
            [name] + readingURLs.map { latencyKey(name, readingURL: $0) }
        }

         
        @discardableResult
        mutating func absorb(_ page: DelayPage) -> Set<String> {
            if page.revision != revision { reset(revision: page.revision) }
            selections = page.selections
            var touched = Set<String>()
             
             
             
             
            for (name, state) in page.configured {
                configured[name] = state
                configuredURLs[name] = page.configuredURLs[name]?.filter { readingURLs.contains($0.key) }
                touched.formUnion(keys(of: name))
            }
             
             
            touched.formUnion(Set(groups.keys).subtracting(page.groups.keys))
            groups = page.groups
            touched.formUnion(page.groups.keys)
            for (provider, records) in page.providers {
                for (name, record) in records {
                    var kept = record
                    kept.urls = record.urls.filter { readingURLs.contains($0.key) }
                    providers[provider, default: [:]][name] = kept
                    touched.formUnion(keys(of: name))
                }
            }
            recompute(touched)
            return touched
        }

         
         
        @discardableResult
        mutating func name(configured names: Set<String>) -> Set<String> {
            let moved = Set(names.symmetricDifference(configuredNames).flatMap(keys(of:)))
            configuredNames = names
            recompute(moved)
            return moved
        }

        private mutating func recompute(_ keys: Set<String>) {
            for key in keys {
                if let record = urlRecord(of: key) {
                    latency[key] = reading(of: record.name, url: record.url)
                } else {
                    latency[key] = reading(of: key)
                }
            }
        }

         
         
        private func reading(of name: String, url: String? = nil) -> ClashProxyLatencyState? {
            if let url {
                if groups[name] != nil { return nil }
                if configured[name] != nil { return configuredURLs[name]?[url] ?? nil }
            } else {
                if let group = groups[name] { return group }
                if let state = configured[name] { return state }
            }
            if configuredNames.contains(name) { return nil }
            var newest: DelayRecord?
            for provider in providers.keys.sorted() {
                guard let found = providers[provider]?[name] else { continue }
                let candidate = url == nil ? found : url.flatMap { found.urls[$0] }
                guard let record = candidate, record.state != nil else { continue }
                if let held = newest {
                    guard let time = record.time, let next = RecordTime(time) else { continue }
                    if let last = held.time.flatMap(RecordTime.init), !(next > last) { continue }
                }
                newest = record
            }
            return newest?.state ?? nil
        }

         
        var delays: ProxyDelays { ProxyDelays(revision: revision, selections: selections, latency: latency) }
    }

     
     
     
    typealias Summary = NodeSummary
    typealias Member = NodeMember
    typealias MembersPage = GroupMembersPage

    static func summary(from data: Data) throws -> Summary {
        let root = try object(data, what: "proxies summary")
        guard root["groups"] is [String: Any] else { throw DecodingError.notAnObject("proxies summary") }
        return try NodeSummary.decode(data)
    }

    static func membersPage(from data: Data) throws -> MembersPage {
        let root = try object(data, what: "group members")
        guard root["members"] is [Any], root["total"] is NSNumber else { throw DecodingError.notAnObject("group members") }
        return try JSONDecoder().decode(GroupMembersPage.self, from: data)
    }

     
     
     
     
    static func proxies(summary: Summary, members: [String: [Member]], groupOrder: [String]) -> Proxies {
        let entries = summary.groups
        func isGroup(_ name: String) -> Bool { entries[name] != nil }
        func resolve(_ selection: String) -> String {
            var current = selection
            var visited = Set<String>()
            while isGroup(current), visited.insert(current).inserted,
                  let next = entries[current]?.now, !next.isEmpty {
                current = next
            }
            return current
        }
        let hiddenNames = entries.keys.filter { entries[$0]?.hidden == true }
        let groupNames = entries.keys.filter { entries[$0]?.hidden != true }
        let ordered = groupOrder.filter { groupNames.contains($0) }
            + groupNames.filter { !groupOrder.contains($0) && $0 != "GLOBAL" }.sorted()
            + (groupNames.contains("GLOBAL") ? ["GLOBAL"] : [])
        func snapshot(_ name: String) -> ClashProxyGroupSnapshot? {
            guard let entry = entries[name] else { return nil }
            let read = members[name] ?? []
            return ClashProxyGroupSnapshot(
                name: name,
                type: entry.type,
                members: read.map { ClashProxyMemberSnapshot(name: $0.name, type: $0.type, isGroup: isGroup($0.name)) },
                configuredSelection: entry.fixed,
                runtimeSelection: entry.now,
                resolvedRuntimeRoute: entry.now.map(resolve),
                emptyFallback: entry.emptyFallback,
                memberTotal: read.count < entry.total ? entry.total : nil
            )
        }
        let read = members.values.joined()
        var built = Proxies(
            groups: ordered.compactMap(snapshot),
            hiddenGroups: hiddenNames.sorted().compactMap(snapshot),
            latency: [:],
            nodeCount: summary.nodes,
            configuredNodes: Set(read.filter { $0.inline && !isGroup($0.name) }.map(\.name)),
            selections: entries.mapValues { GroupSelection(now: $0.now, fixed: $0.fixed) },
            easyTierPlaceholders: Set(read.filter { $0.placeholderType?.lowercased() == "easytier" }.map(\.name))
        )
        built.readingURLs = entries.compactMapValues { readingURL(type: $0.type, testURL: $0.testURL) }
        return built
    }

     
     
     
     
    fileprivate struct RecordTime: Comparable {
        let second: Date
        let nanoseconds: Int

        init?(_ text: String) {
            var whole = text
            var nanoseconds = 0
            if let clock = text.firstIndex(of: "T"), let dot = text[clock...].firstIndex(of: ".") {
                let digits = text[text.index(after: dot)...].prefix { $0.isASCII && $0.isNumber }
                guard !digits.isEmpty, digits.count <= 9, let value = Int(digits) else { return nil }
                nanoseconds = value * Int(pow(10, Double(9 - digits.count)))
                whole = String(text[..<dot]) + text[text.index(dot, offsetBy: digits.count + 1)...]
            }
            guard let second = Self.formatter.date(from: whole) else { return nil }
            self.second = second
            self.nanoseconds = nanoseconds
        }

        static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.second, lhs.nanoseconds) < (rhs.second, rhs.nanoseconds)
        }
        private static let formatter = ISO8601DateFormatter()
    }

     
     
     
     
     
     
     
     
    static func proxies(from data: Data, groupOrder: [String]) throws -> Proxies {
        let root = try object(data, what: "proxies")
        guard let entries = root["proxies"] as? [String: [String: Any]] else {
            throw DecodingError.notAnObject("proxies")
        }
        func isGroup(_ name: String) -> Bool { entries[name]?["all"] is [Any] }
        func type(of name: String) -> String { entries[name]?["type"] as? String ?? "" }
         
         
         
         
         
        func resolve(_ selection: String) -> String {
            var current = selection
            var visited = Set<String>()
            while isGroup(current), visited.insert(current).inserted,
                  let next = entries[current]?["now"] as? String, !next.isEmpty {
                current = next
            }
            return current
        }

        var latency: [String: ClashProxyLatencyState] = [:]
        for (name, entry) in entries {
            guard let history = entry["history"] as? [[String: Any]], let last = history.last else { continue }
            let delay = (last["delay"] as? NSNumber)?.intValue ?? 0
            latency[name] = delay > 0 ? .measured(milliseconds: delay) : .failed
        }

        let hiddenNames = entries.keys.filter { isGroup($0) && entries[$0]?["hidden"] as? Bool == true }
        let groupNames = entries.keys.filter { isGroup($0) && !hiddenNames.contains($0) }
        let ordered = groupOrder.filter { groupNames.contains($0) }
            + groupNames.filter { !groupOrder.contains($0) && $0 != "GLOBAL" }.sorted()
            + (groupNames.contains("GLOBAL") ? ["GLOBAL"] : [])
        func snapshot(_ name: String) -> ClashProxyGroupSnapshot? {
            guard let entry = entries[name], let all = entry["all"] as? [String] else { return nil }
            let members = all.map { member in
                ClashProxyMemberSnapshot(name: member, type: type(of: member), isGroup: isGroup(member))
            }
            let now = entry["now"] as? String
             
             
             
             
             
             
             
             
             
             
             
             
            return ClashProxyGroupSnapshot(
                name: name,
                type: entry["type"] as? String ?? "",
                members: members,
                configuredSelection: entry["fixed"] as? String,
                runtimeSelection: now,
                resolvedRuntimeRoute: now.map(resolve),
                emptyFallback: entry["emptyFallback"] as? String
            )
        }
        let groups = ordered.compactMap(snapshot)
        let hiddenGroups = hiddenNames.sorted().compactMap(snapshot)
         
         
         
        let builtIn: Set<String> = ["DIRECT", "REJECT", "REJECT-DROP", "PASS", "PASS-RULE", "COMPATIBLE"]
        let nodeCount = entries.keys.filter { !isGroup($0) && !builtIn.contains($0) }.count
        let placeholders = Set(entries.compactMap { name, entry -> String? in
            (entry["placeholderType"] as? String)?.lowercased() == "easytier" ? name : nil
        })
        return Proxies(
            groups: groups, hiddenGroups: hiddenGroups, latency: latency,
            nodeCount: nodeCount, configuredNodes: Set(entries.keys.filter { !isGroup($0) }),
            selections: entries.filter { isGroup($0.key) }.mapValues {
                GroupSelection(now: $0["now"] as? String, fixed: $0["fixed"] as? String)
            },
            easyTierPlaceholders: placeholders
        )
    }

     
     
     
     
     
    struct ConnectionRead {
        let rows: [ClashActivityConnectionSnapshot]
        let isComplete: Bool
    }

    static func connections(from data: Data) throws -> [ClashActivityConnectionSnapshot] {
        try connectionRead(from: data).rows
    }

    static func connectionRead(from data: Data) throws -> ConnectionRead {
        let root = try object(data, what: "connections")
         
         
         
        let list: [[String: Any]]
        if let array = root["connections"] as? [[String: Any]] {
            list = array
        } else if root["connections"] is NSNull {
            list = []
        } else {
            throw DecodingError.notAnObject("connections")
        }
        let rows: [ClashActivityConnectionSnapshot] = list.compactMap { entry in
            guard let id = entry["id"] as? String, !id.isEmpty else { return nil }
            let metadata = entry["metadata"] as? [String: Any] ?? [:]
            let host = metadata["host"] as? String ?? ""
            let destinationIP = metadata["destinationIP"] as? String ?? ""
            let destinationPort = metadata["destinationPort"] as? String ?? ""
            let sourceIP = metadata["sourceIP"] as? String ?? ""
            let sourcePort = metadata["sourcePort"] as? String ?? ""
            let network = (metadata["network"] as? String ?? "").uppercased()
            let chains = entry["chains"] as? [String] ?? []
            let destination = Self.endpoint(host.isEmpty ? destinationIP : host, port: destinationPort)
            let source = Self.endpoint(sourceIP, port: sourcePort)
            return ClashActivityConnectionSnapshot(
                id: id,
                destination: destination,
                source: source,
                network: network,
                route: chains.joined(separator: " → "),
                rule: entry["rule"] as? String ?? "",
                upload: (entry["upload"] as? NSNumber)?.int64Value ?? 0,
                download: (entry["download"] as? NSNumber)?.int64Value ?? 0,
                start: (entry["start"] as? String).flatMap(Self.date(from:)),
                host: host,
                sourceIP: sourceIP,
                sourcePort: sourcePort,
                destinationIP: destinationIP,
                destinationPort: destinationPort,
                dnsMode: metadata["dnsMode"] as? String ?? "",
                chains: chains,
                rulePayload: entry["rulePayload"] as? String ?? ""
            )
        }
        let ids = Set(rows.map(\.id))
        return ConnectionRead(rows: rows, isComplete: rows.count == list.count && ids.count == rows.count)
    }

    static func traffic(from data: Data) throws -> Traffic {
        let root = try object(data, what: "traffic")
        let up = nonnegativeInteger(root["up"])
        let down = nonnegativeInteger(root["down"])
        let upTotal = nonnegativeInteger(root["upTotal"])
        let downTotal = nonnegativeInteger(root["downTotal"])
        let validTotals = upTotal != nil && downTotal != nil
            && !(upTotal ?? 0).addingReportingOverflow(downTotal ?? 0).overflow
        return Traffic(
            up: up ?? 0,
            down: down ?? 0,
            upTotal: upTotal ?? 0,
            downTotal: downTotal ?? 0,
            memory: nonnegativeInteger(root["memory"]) ?? 0,
            hasTotals: validTotals,
            hasRates: up != nil && down != nil
        )
    }

     
     
    private static func nonnegativeInteger(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              var decimal = Decimal(string: number.stringValue, locale: Locale(identifier: "en_US_POSIX")),
              decimal >= 0, decimal <= Decimal(Int64.max) else { return nil }
        var integral = Decimal()
        NSDecimalRound(&integral, &decimal, 0, .down)
        guard integral == decimal else { return nil }
        return NSDecimalNumber(decimal: integral).int64Value
    }

    struct RuleProvider: Equatable {
        let loaded: Bool
        let contentHash: String
        let updatedAt: Date?
    }

    static func ruleProviders(from data: Data) throws -> [String: RuleProvider] {
        let root = try object(data, what: "rule providers")
        guard let providers = root["providers"] as? [String: [String: Any]] else {
            throw DecodingError.notAnObject("rule providers")
        }
        let dates = ISO8601DateFormatter()
        dates.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try providers.mapValues { value in
            if value["vehicleType"] as? String == "Inline", value["loaded"] as? Bool == true {
                return RuleProvider(loaded: true, contentHash: "", updatedAt: nil)
            }
            guard let loaded = value["loaded"] as? Bool,
                  let hash = value["contentHash"] as? String,
                  value["algorithm"] as? String == "md5",
                  !loaded || (hash.count == 32 && hash.allSatisfy { $0.isHexDigit }) else {
                throw DecodingError.notAnObject("rule provider")
            }
            let date = (value["updatedAt"] as? String).flatMap { dates.date(from: $0) ?? ISO8601DateFormatter().date(from: $0) }
            return RuleProvider(loaded: loaded, contentHash: hash.lowercased(), updatedAt: date)
        }
    }

    static func status(from data: Data) throws -> Status {
        let root = try object(data, what: "status")
        guard let status = root["status"] as? String else { throw DecodingError.notAnObject("status") }
        return Status(status: status, mode: root["mode"] as? String ?? "")
    }

     
     
    static func endpoint(_ host: String, port: String) -> String {
        guard !port.isEmpty else { return host }
        let needsBrackets = host.contains(":") && !host.hasPrefix("[")
        return needsBrackets ? "[\(host)]:\(port)" : "\(host):\(port)"
    }

     
    private static let fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let whole = ISO8601DateFormatter()

    static func date(from text: String) -> Date? {
        fractional.date(from: text) ?? whole.date(from: text)
    }
}
