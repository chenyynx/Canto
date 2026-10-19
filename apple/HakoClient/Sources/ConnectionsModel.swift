import Combine
import Foundation
import Hako
import HakoClientUI

typealias HakoConnection = HakoActivityConnectionSnapshot

enum ConnectionsParser {
     
     
    static func parse(_ text: String) -> [HakoConnection] {
        decode(text, requiresCompleteSnapshot: false) ?? []
    }

    static func parseValid(_ text: String) -> [HakoConnection]? {
        decode(text, requiresCompleteSnapshot: true)
    }

    private static func decode(_ text: String, requiresCompleteSnapshot: Bool) -> [HakoConnection]? {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let rows: [[String: Any]]
         
        if root["connections"] is NSNull { rows = [] }
        else if let array = root["connections"] as? [[String: Any]] { rows = array }
        else { return nil }
        if requiresCompleteSnapshot {
            guard rows.allSatisfy({ ($0["id"] as? String)?.isEmpty == false }) else { return nil }
        }

         
         
         
         
         
         
         

        var seen = Set<String>()
        let parsed = rows.compactMap { row -> HakoConnection? in
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            guard seen.insert(id).inserted else { return nil }
            return connection(row)
        }
        return attributed(parsed)
    }

     
    static var attributesProcesses: Bool {
#if os(macOS)
        return true
#else
        return false
#endif
    }

     
     
    static func attributed(_ rows: [HakoConnection]) -> [HakoConnection] {
#if os(macOS)
        return HakoMacProcessAttribution.shared.fill(rows)
#else
        return rows
#endif
    }

     
     
    static func connection(_ row: [String: Any]) -> HakoConnection? {
            guard let id = row["id"] as? String, !id.isEmpty else { return nil }
            let metadata = row["metadata"] as? [String: Any] ?? [:]
            let host = string(metadata["host"])
            let ip = string(metadata["destinationIP"])
            let port = string(metadata["destinationPort"])
            let sourceIP = string(metadata["sourceIP"])
            let sourcePort = string(metadata["sourcePort"])
            let destination = address(host.isEmpty ? ip : host, port)
            let source = address(sourceIP, sourcePort)
            let chains = row["chains"] as? [String] ?? []
            let startText = string(row["start"])

            return HakoConnection(
                id: id,
                destination: destination.isEmpty ? "Unknown destination" : destination,
                source: source,
                network: string(metadata["network"]).uppercased(),
                route: chains.joined(separator: " → "),
                rule: string(row["rule"]),
                upload: number(row["upload"]),
                download: number(row["download"]),
                start: HakoInstant.parse(startText),
                uid: signedNumber(metadata["uid"]),
                host: host,
                sourceIP: sourceIP,
                sourcePort: sourcePort,
                destinationIP: ip,
                destinationPort: port,
                dnsMode: string(metadata["dnsMode"]),
                process: string(metadata["process"]),
                processPath: string(metadata["processPath"]),
                remoteDestination: string(metadata["remoteDestination"]),
                sourceGeoIP: strings(metadata["sourceGeoIP"]),
                destinationGeoIP: strings(metadata["destinationGeoIP"]),
                destinationIPASN: string(metadata["destinationIPASN"]),
                sourceIPASN: string(metadata["sourceIPASN"]),
                specialRules: string(metadata["specialRules"]),
                specialProxy: string(metadata["specialProxy"]),
                chains: chains,
                rulePayload: string(row["rulePayload"]),
                uploadSpeed: optionalNumber(row["uploadSpeed"]),
                downloadSpeed: optionalNumber(row["downloadSpeed"])
            )
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return ""
    }

    static func number(_ value: Any?) -> Int64 {
        if let value = value as? NSNumber { return max(value.int64Value, 0) }
        return max(Int64(string(value)) ?? 0, 0)
    }

    private static func signedNumber(_ value: Any?) -> Int64 {
        if let value = value as? NSNumber { return value.int64Value }
        return Int64(string(value)) ?? 0
    }

    private static func optionalNumber(_ value: Any?) -> Int64? {
        guard value != nil, !(value is NSNull) else { return nil }
        return number(value)
    }

    private static func strings(_ value: Any?) -> [String] {
        guard let values = value as? [Any] else { return [] }
        return values.map(string).filter { !$0.isEmpty }
    }

    private static func address(_ host: String, _ port: String) -> String {
        guard !host.isEmpty else { return "" }
        guard !port.isEmpty, port != "0" else { return host }
        if host.hasPrefix("["), host.hasSuffix("]") { return "\(host):\(port)" }
        return host.contains(":") ? "[\(host)]:\(port)" : "\(host):\(port)"
    }
}

 
 
struct ClosedConnection: Equatable {
    let connection: HakoConnection
    let closedAt: Date
     
     
    var stamp: UInt64 = 0
}

 
 
 
 
 
 
 
 
 
final class ConnectionClosedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [(cursor: UInt64, closed: ClosedConnection)] = []
     
    private var stamped = 0
    private var last: UInt64 = 0
     
     
     
    let capacity: Int

    init(capacity: Int = 4_096) { self.capacity = max(1, capacity) }

     
    var cursor: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return last
    }

    func append(_ closed: [ClosedConnection]) {
        guard !closed.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        for item in closed {
            last &+= 1
            entries.append((last, item))
        }
        if entries.count > capacity {
            let drop = entries.count - capacity
            entries.removeFirst(drop)
            stamped = max(0, stamped - drop)
        }
    }

     
     
     
    func stamp(_ sequence: UInt64) {
        lock.lock(); defer { lock.unlock() }
        while stamped < entries.count {
            entries[stamped].closed.stamp = sequence
            stamped += 1
        }
    }

     
     
    func closes(after cursor: UInt64) -> ([ClosedConnection], UInt64) {
        lock.lock(); defer { lock.unlock() }
        let ready = entries[..<stamped].filter { $0.cursor > cursor }
        return (ready.map(\.closed), ready.last?.cursor ?? cursor)
    }
}

 
 
 
 
 
 
 
 
 
final class ConnectionEventTable {
    private let lock = NSLock()
    private var order: [String] = []
    private var rows: [String: HakoConnection] = [:]
     
     
     
     
    private var attributionTries: [String: Int] = [:]
    private static let attributionLimit = 4
    let closedLog: ConnectionClosedLog

    init(closedLog: ConnectionClosedLog = ConnectionClosedLog()) { self.closedLog = closedLog }

     
    func apply(_ text: String) -> [HakoConnection]? {
        lock.lock(); defer { lock.unlock() }
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let events = root["events"] as? [[String: Any]] else { return nil }
        var closed: [ClosedConnection] = []
        var closedIDs = Set<String>()
        if root["reset"] as? Bool == true {
             
             
             
             
             
            order = []
            rows = [:]
            attributionTries = [:]
        }
        var added: [HakoConnection] = []
        var addedIndex: [String: Int] = [:]
        for event in events {
            guard let id = event["id"] as? String, !id.isEmpty else { continue }
            switch event["type"] as? String {
            case "new":
                guard rows[id] == nil, addedIndex[id] == nil, !closedIDs.contains(id),
                      let row = event["connection"] as? [String: Any],
                      let connection = ConnectionsParser.connection(row) else { continue }
                addedIndex[id] = added.count
                added.append(connection)
            case "update":
                let upload = ConnectionsParser.number(event["upload"])
                let download = ConnectionsParser.number(event["download"])
                let up = ConnectionsParser.number(event["up"])
                let down = ConnectionsParser.number(event["down"])
                if let current = rows[id] {
                    rows[id] = current.withTraffic(upload: upload, download: download,
                                                   uploadSpeed: up, downloadSpeed: down)
                } else if let index = addedIndex[id] {
                    added[index] = added[index].withTraffic(upload: upload, download: download,
                                                            uploadSpeed: up, downloadSpeed: down)
                }
                 
            case "closed":
                guard closedIDs.insert(id).inserted else { continue }
                let last: HakoConnection?
                attributionTries[id] = nil
                if let row = rows.removeValue(forKey: id) {
                    order.removeAll { $0 == id }
                    last = row
                } else if let index = addedIndex.removeValue(forKey: id) {
                    last = added[index]
                } else {
                    last = nil
                }
                 
                 
                 
                 
                 
                var connection: HakoConnection
                if let final = (event["connection"] as? [String: Any]).flatMap(ConnectionsParser.connection) {
                    connection = final
                    if final.process.isEmpty, let last, !last.process.isEmpty {
                        connection = final.attributed(process: last.process, processPath: last.processPath,
                                                      uid: last.uid)
                    }
                } else if let last {
                    connection = last
                } else {
                    continue
                }
                connection = connection.withTraffic(upload: connection.upload, download: connection.download,
                                                    uploadSpeed: 0, downloadSpeed: 0)
                let closedAt = HakoInstant.parse(event["closedAt"] as? String) ?? Date()
                closed.append(ClosedConnection(connection: connection, closedAt: closedAt))
            default:
                continue
            }
        }
        let opened = added.enumerated().filter { addedIndex[$0.element.id] == $0.offset }.map(\.element)
        for connection in ConnectionsParser.attributed(opened) where rows[connection.id] == nil {
            rows[connection.id] = connection
            order.append(connection.id)
            if ConnectionsParser.attributesProcesses, connection.process.isEmpty {
                attributionTries[connection.id] = 1
            }
        }
        let openedIDs = Set(opened.map(\.id))
        let unnamed = attributionTries.keys.filter { !openedIDs.contains($0) }.compactMap { rows[$0] }
        if !unnamed.isEmpty {
            for connection in ConnectionsParser.attributed(unnamed) {
                if !connection.process.isEmpty {
                    rows[connection.id] = connection
                    attributionTries[connection.id] = nil
                } else {
                    let tries = (attributionTries[connection.id] ?? 0) + 1
                    attributionTries[connection.id] = tries < Self.attributionLimit ? tries : nil
                }
            }
        }
        closedLog.append(closed)
        return order.compactMap { rows[$0] }
    }
}

extension HakoActivityConnectionSnapshot {
     
    func withTraffic(upload: Int64, download: Int64, uploadSpeed: Int64, downloadSpeed: Int64) -> Self {
        Self(
            id: id, destination: destination, source: source, network: network,
            route: route, rule: rule, upload: upload, download: download,
            start: start, uid: uid, host: host, sourceIP: sourceIP,
            sourcePort: sourcePort, destinationIP: destinationIP,
            destinationPort: destinationPort, dnsMode: dnsMode, process: process,
            processPath: processPath, remoteDestination: remoteDestination,
            sourceGeoIP: sourceGeoIP, destinationGeoIP: destinationGeoIP,
            destinationIPASN: destinationIPASN, sourceIPASN: sourceIPASN,
            specialRules: specialRules, specialProxy: specialProxy, chains: chains,
            rulePayload: rulePayload, uploadSpeed: uploadSpeed, downloadSpeed: downloadSpeed
        )
    }
}

 
 
 
 
 
 
 
 
 
 
enum ConnectionsRecordingPolicy {
     
     
    static func shouldRecord(
        isForeground: Bool,
        isConnected: Bool
    ) -> Bool {
        isForeground && isConnected
    }
}

protocol ConnectionsClient: ConnectionSourceTransport {
    func connect() throws
    func close()
    func getConnections() throws -> String
    func closeConnection(_ id: String) throws
    func closeConnections() throws
}

extension ConnectionsClient {
    func snapshot() throws -> String { try getConnections() }
}

typealias ConnectionsClientFactory = (
    _ socketPath: String,
    _ handler: HakoClashAPIClientHandlerProtocol
) throws -> ConnectionsClient

private final class NativeConnectionsClient: ConnectionsClient {
    private let client: HakoClashAPIClient

    init(socketPath: String, handler: HakoClashAPIClientHandlerProtocol) throws {
        let options = HakoClashAPIClientOptions()
         
         
         
         
        options.statusInterval = 1000
        options.addCommand(HakoCommandConnectionEvents)

        var error: NSError?
        guard let client = HakoNewClashAPIClientWithOptions(
            socketPath,
            handler,
            options,
            &error
        ) else {
            throw error ?? NSError(
                domain: "Clash.Connections",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Connections API unavailable"]
            )
        }
        self.client = client
         
        if let writer = handler as? HakoConnectionEventsWriterProtocol {
            client.setConnectionEventsWriter(writer)
        }
    }

    func connect() throws {
        try client.connect()
    }

    func close() {
        client.close()
    }

    func getConnections() throws -> String {
        var error: NSError?
        let value = client.getConnections(&error)
        if let error { throw error }
        return value
    }

    func closeConnection(_ id: String) throws {
        try client.closeConnection(id)
    }

    func closeConnections() throws {
        try client.closeConnections()
    }
}

func defaultConnectionsSocketPath() -> String? {
    HakoAppIdentifiers.appGroupContainer?
    .appendingPathComponent("clash.sock")
    .path
}

func makeNativeConnectionsClient(
    socketPath: String,
    handler: HakoClashAPIClientHandlerProtocol
) throws -> ConnectionsClient {
    try NativeConnectionsClient(socketPath: socketPath, handler: handler)
}

@MainActor
final class ConnectionsModel: ObservableObject {
    @Published private(set) var activityConnections:
        [HakoConnection]
    @Published private(set) var connected = false
    @Published private(set) var loading = false
    @Published private(set) var error = ""
    @Published private(set) var closing: Set<String> = []
    @Published private(set) var closingAll = false
     
    @Published private(set) var requestLog: [ConnectionHistory.Entry] = []

     
     
    var activeConnectionCount: Int {
        activityConnections.count
    }

    var totalCount: Int { activityConnections.count }

    private var history = ConnectionHistory()
     
    private var closedCursor: UInt64 = 0
     
     
    private var historyFloor: UInt64 = 0
     
     
    private var locallyClosed = Set<String>()

    private let source: ConnectionObservationSource<[HakoConnection]>
    private var lease: ConnectionSourceLease?
    private var generation: UInt64 = 0
     
     
     
    private var confirmationRetry: Task<Void, Never>?
    private var confirmationRetryID = 0
    private let confirmationRetryNanoseconds: UInt64
    private var framesSinceStart = 0
    private var observedRuntimeIdentity: String?
    private(set) var lastObservation: ConnectionObservation<[HakoConnection]>?
    private let usesFixtureFeed: Bool



    init(
        seed: [HakoConnection] = [],
        connected: Bool = false,
        loading: Bool = false,
        error: String = "",
        recordsInitialSeed: Bool = false,
        usesFixtureFeed: Bool = false,
        socketPath: (() -> String?)? = nil,
        clientFactory: ConnectionsClientFactory? = nil,
        observationSource: ConnectionObservationSource<[HakoConnection]>? = nil,
        confirmationRetryNanoseconds: UInt64 = 1_000_000_000
    ) {
        self.confirmationRetryNanoseconds = confirmationRetryNanoseconds
        let initialSeed: [HakoConnection]

            initialSeed = seed

        activityConnections = initialSeed
        self.connected =
            false || usesFixtureFeed || connected
        self.loading = loading
        self.error = error
        self.usesFixtureFeed = usesFixtureFeed
        source = observationSource ?? {
            if socketPath != nil || clientFactory != nil {
                return ConnectionRuntimeFeed.makeSource(
                    socketPath: socketPath ?? defaultConnectionsSocketPath,
                    clientFactory: clientFactory ?? makeNativeConnectionsClient
                )
            }
            return ConnectionRuntimeFeed.shared.source
        }()
        closedCursor = source.closedLog?.cursor ?? 0
        if false || recordsInitialSeed {
            history.record(initialSeed, at: Date())
            requestLog = history.entries
        }
    }

    private var usesStaticFixtureFeed: Bool {
        false || usesFixtureFeed
    }

     
     
    static var inspectorFixtureSeed: [HakoConnection] {
        [
            HakoConnection(
                id: "ui-1",
                destination: "api.example.test:443",
                source: "10.0.0.2:51842",
                network: "TCP",
                route: "PROXY → Singapore 01",
                rule: "DOMAIN-SUFFIX,example.test",
                upload: 42_128,
                download: 1_802_240,
                start: Date(),
                chains: ["PROXY", "Singapore 01"]
            ),
            HakoConnection(
                id: "ui-2",
                destination: "dns.example.test:53",
                source: "10.0.0.2:53418",
                network: "UDP",
                route: "DIRECT",
                rule: "MATCH",
                upload: 512,
                download: 1_024,
                start: Date().addingTimeInterval(-45),
                chains: ["DIRECT"]
            ),
             
             
             
            HakoConnection(
                id: "ui-3",
                destination: "cdn.example.test:443",
                source: "10.0.0.2:51903",
                network: "TCP",
                route: "PROXY → Tokyo 02",
                rule: "DOMAIN-KEYWORD,cdn",
                upload: 8_940,
                download: 24_500_000,
                start: Date().addingTimeInterval(-182),
                chains: ["PROXY", "Tokyo 02"]
            ),
            HakoConnection(
                id: "ui-4",
                destination: "push.example.test:5223",
                source: "10.0.0.2:52011",
                network: "TCP",
                route: "DIRECT",
                rule: "IP-CIDR,17.0.0.0/8",
                upload: 2_048,
                download: 3_120,
                start: Date().addingTimeInterval(-620),
                chains: ["DIRECT"]
            ),
            HakoConnection(
                id: "ui-5",
                destination: "analytics.example.test:443",
                source: "10.0.0.2:52140",
                network: "TCP",
                route: "REJECT",
                rule: "GEOSITE,ads",
                upload: 0,
                download: 0,
                start: Date().addingTimeInterval(-8),
                chains: ["REJECT"]
            ),
            HakoConnection(
                id: "ui-6",
                destination: "video.example.test:443",
                source: "10.0.0.2:52288",
                network: "TCP",
                route: "PROXY → Silicon Valley 01",
                rule: "DOMAIN-SUFFIX,video.example.test",
                upload: 61_400,
                download: 92_800_000,
                start: Date().addingTimeInterval(-1_450),
                chains: ["PROXY", "Silicon Valley 01"]
            ),
        ]
    }

    func start(commandConnected: Bool) {
        if usesStaticFixtureFeed {
            connected = commandConnected
            loading = false
            error = ""
            return
        }
        guard commandConnected, lease == nil else { return }
        generation &+= 1
        let token = generation
         
         
        loading = activityConnections.isEmpty
        error = ""
        framesSinceStart = 0
        lease = source.acquire { [weak self] event in
            guard let self, token == self.generation else { return }
            switch event {
            case let .frame(frame):
                self.apply(frame)
            case let .state(connected, message):
                self.connected = connected
                if !message.isEmpty { self.loading = false; self.error = message }
            case let .gap(_, reason, kind):
                 
                 
                 
                 
                if kind == .decoder { self.error = reason }
                else { self.scheduleConfirmationRetry() }
            case .runtimeChanged:
                self.adoptRuntime(self.source.runtimeIdentity)
                self.locallyClosed = []
                self.activityConnections = []
            }
        }
         
         
         
         
         
         
         
        if framesSinceStart == 0 { scheduleConfirmationRetry(immediately: !activityConnections.isEmpty) }
    }

     
     
     
     
     
     
     
     
    func syncScene(isConnected: Bool, tunnelIsUp: Bool, channelFailed: Bool = false,
                   isActive: Bool, isBackground: Bool) {
        if self.tunnelIsUp != tunnelIsUp {
            if self.tunnelIsUp { tunnelDidStop() }
            self.tunnelIsUp = tunnelIsUp
        }
        if self.channelFailed != channelFailed { self.channelFailed = channelFailed }
        if !isConnected || isBackground { tunnelIsUp ? pause() : stop() }
        else if isActive { start(commandConnected: true) }
    }

     
     
     
     
    func setChannelState(tunnelIsUp: Bool, channelFailed: Bool) {
        if self.tunnelIsUp != tunnelIsUp { self.tunnelIsUp = tunnelIsUp }
        if self.channelFailed != channelFailed { self.channelFailed = channelFailed }
    }

     
     
     
     
     
     
    func tunnelDidStop() {
        if usesStaticFixtureFeed { return }
        recordClosedConnections()
        history.record([], at: Date())
        history.releaseSeals(before: .max)
        requestLog = history.entries
    }

     
     
     
    func clearRequestHistory() {
        history.clear()
         
         
        historyFloor = source.receiptSequence
        closedCursor = source.closedLog?.cursor ?? closedCursor
        requestLog = []
         
        HakoActivityRequestsPause.shared.clear()
    }

    func stop() {
        if usesStaticFixtureFeed { return }
        generation &+= 1
        confirmationRetry?.cancel(); confirmationRetry = nil
        lease?.release()
        lease = nil
        connected = false
        loading = false
        closing = []
        closingAll = false
        locallyClosed = []
        activityConnections = []
        lastObservation = nil
    }

     
     
    @Published private(set) var tunnelIsUp = false
     
     
     
    @Published private(set) var channelFailed = false

     
     
     
    var isStreaming: Bool { usesStaticFixtureFeed || lease != nil }

     
     
     
     
     
     
     
    func pause() {
        if usesStaticFixtureFeed { return }
        generation &+= 1
        confirmationRetry?.cancel(); confirmationRetry = nil
        lease?.release()
        lease = nil
        loading = false
        closing = []
        closingAll = false
    }



    func sync(_ commandConnected: Bool) {
        if commandConnected { start(commandConnected: true) } else { stop() }
    }

    func refresh() async {
        guard !usesStaticFixtureFeed, lease != nil, !closingAll, closing.isEmpty else { return }
        let token = generation
        do { try await source.refresh() }
        catch {
            guard token == generation else { return }
            self.error = error.localizedDescription
        }
    }

     
     
     
    @discardableResult
    func close(_ id: String) async -> String? {
        if usesStaticFixtureFeed {
            activityConnections.removeAll { $0.id == id }
            return nil
        }
        guard lease != nil, !closingAll, !closing.contains(id) else { return nil }
        let token = generation
         
         
        let runtime = observedRuntimeIdentity
        closing.insert(id)
        defer { if token == generation { closing.remove(id) } }
        do {
            guard try await source.close(id), token == generation,
                  observedRuntimeIdentity == runtime else { return nil }
            locallyClosed.insert(id)
            activityConnections.removeAll { $0.id == id }
             
             
             
            history.record(activityConnections, at: Date())
            requestLog = history.entries
            return nil
        } catch {
            guard token == generation else { return nil }
            return error.localizedDescription
        }
    }

    @discardableResult
    func closeAll() async -> String? {
        if usesStaticFixtureFeed { activityConnections = []; return nil }
        guard lease != nil, !closingAll, closing.isEmpty else { return nil }
        let token = generation
        closingAll = true
        defer { if token == generation { closingAll = false } }
         
         
        let targets = Set(activityConnections.map(\.id))
        let runtime = observedRuntimeIdentity
        do {
            guard try await source.close(nil), token == generation,
                  observedRuntimeIdentity == runtime else { return nil }
            locallyClosed.formUnion(targets)
            activityConnections.removeAll { targets.contains($0.id) }
             
            history.record(activityConnections, at: Date())
            requestLog = history.entries
            return nil
        } catch {
            guard token == generation else { return nil }
            return error.localizedDescription
        }
    }

    private func adoptRuntime(_ identity: String?) {
        guard let identity, identity != observedRuntimeIdentity else { return }
        if observedRuntimeIdentity != nil {
             
             
             
             
            recordClosedConnections(evicts: false)
            history.beginRuntime(at: Date())
            requestLog = history.entries
        }
        observedRuntimeIdentity = identity
    }

     
     
     
     
     
     
     
     
     
     
     
    private func scheduleConfirmationRetry(immediately: Bool = false) {
        guard confirmationRetry == nil, !usesStaticFixtureFeed else { return }
        confirmationRetryID += 1
        let id = confirmationRetryID
        let token = generation
        confirmationRetry = Task { @MainActor [weak self] in
            var attempts = 0
            var asks = immediately
            while let self, !Task.isCancelled, token == self.generation, self.lease != nil {
                if asks { try? await self.source.refresh(); attempts += 1 }
                asks = true
                let delay = attempts < 30 ? self.confirmationRetryNanoseconds : 5 * self.confirmationRetryNanoseconds
                try? await Task.sleep(nanoseconds: delay)
            }
            if let self, self.confirmationRetryID == id { self.confirmationRetry = nil }
        }
    }

     
    private func recordClosedConnections(evicts: Bool = true) {
        guard let log = source.closedLog else { return }
        let (closed, next) = log.closes(after: closedCursor)
        closedCursor = next
         
        history.recordClosed(closed.filter { $0.stamp > historyFloor }, evicts: evicts)
    }

    private func apply(_ frame: ConnectionObservation<[HakoConnection]>) {
        confirmationRetry?.cancel(); confirmationRetry = nil
        framesSinceStart += 1
        adoptRuntime(frame.runtimeIdentity)
        var rows = frame.value
        if !locallyClosed.isEmpty {
            locallyClosed.formIntersection(rows.lazy.map(\.id))
            rows.removeAll { locallyClosed.contains($0.id) }
        }
        activityConnections = rows
        lastObservation = frame
        loading = false
        error = ""
         
         
         
         
        let decoded = frame.decodedSequence
        if decoded > historyFloor { history.record(rows, at: frame.observedDate) }
         
         
        recordClosedConnections()
        history.releaseSeals(before: decoded)
        requestLog = history.entries
    }

}


