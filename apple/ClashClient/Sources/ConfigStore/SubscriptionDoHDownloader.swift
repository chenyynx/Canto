import Foundation
import Network

 
 
@available(iOS 17, macOS 14, tvOS 17, *)
final class SubscriptionDoHDownloader: HTTPFetching {
    let resolver: URL
    init(resolver: URL) { self.resolver = resolver }

    func fetch(_ request: URLRequest, maxBytes: Int, redirectPolicy: DownloadRedirectPolicy) async throws -> DownloadResult {
        let relay = try SubscriptionDNSRelay(resolver: resolver)
        return try await withTaskCancellationHandler {
            defer { relay.close() }
            let port = try await relay.start()
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 20
            configuration.waitsForConnectivity = false
            var proxy = ProxyConfiguration(socksv5Proxy: .hostPort(host: "127.0.0.1", port: port))
            proxy.applyCredential(username: relay.username, password: relay.password)
            proxy.allowFailover = false
            configuration.proxyConfigurations = [proxy]
            let session = URLSession(configuration: configuration)
            defer { session.invalidateAndCancel() }
            do {
                return try await ResourceDownloader(session: session, maximumAttempts: 1)
                    .fetch(request, maxBytes: maxBytes, redirectPolicy: redirectPolicy)
            } catch {
                if Task.isCancelled { throw CancellationError() }
                throw relay.failure ?? error
            }
        } onCancel: { relay.close() }
    }
}

@available(iOS 17, macOS 14, tvOS 17, *)
private final class SubscriptionDNSRelay: @unchecked Sendable {
    let username = UUID().uuidString
    let password = UUID().uuidString
    private let resolver: URL
    private let listener: NWListener
    private let queue = DispatchQueue(label: "clash.subscription.doh")
     
    private var closed = false
    private var incoming: [UUID: NWConnection] = [:]
    private var outgoing: [UUID: NWConnection] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var recordedFailure: Error?
    var failure: Error? { queue.sync { recordedFailure } }

    init(resolver: URL) throws {
        guard resolver.scheme?.lowercased() == "https", resolver.host?.isEmpty == false,
              resolver.fragment == nil else { throw URLError(.badURL) }
        self.resolver = resolver
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() async throws -> NWEndpoint.Port {
        try Task.checkCancellation()
        defer { queue.async { self.listener.stateUpdateHandler = nil } }
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard !self.closed else { continuation.resume(throwing: CancellationError()); return }
                let waiter = SubscriptionDNSContinuation(continuation)
                self.listener.stateUpdateHandler = { state in
                    switch state {
                    case .ready:
                        if let port = self.listener.port { waiter.finish(.success(port)) }
                        else { waiter.finish(.failure(URLError(.cannotConnectToHost))) }
                    case .failed(let error): waiter.finish(.failure(error))
                    case .cancelled: waiter.finish(.failure(CancellationError()))
                    default: break
                    }
                }
                self.listener.newConnectionHandler = { connection in
                    guard !self.closed, self.incoming.count < 8 else { connection.cancel(); return }
                    let id = UUID()
                    self.incoming[id] = connection
                    connection.start(queue: self.queue)
                    self.tasks[id] = Task { await self.serve(connection, id: id) }
                     
                    self.queue.asyncAfter(deadline: .now() + 65) { self.remove(id) }
                }
                self.listener.start(queue: self.queue)
                self.queue.asyncAfter(deadline: .now() + 5) {
                    if waiter.finish(.failure(URLError(.timedOut))) { self.listener.cancel() }
                }
            }
        }
    }
    func close() {
        queue.async {
            self.closed = true
            self.listener.cancel()
            self.listener.newConnectionHandler = nil
            for id in Array(self.incoming.keys) { self.remove(id) }
        }
    }
    private func remove(_ id: UUID) {
        tasks.removeValue(forKey: id)?.cancel()
        incoming.removeValue(forKey: id)?.cancel()
        outgoing.removeValue(forKey: id)?.cancel()
    }
    private func serve(_ client: NWConnection, id: UUID) async {
        defer { queue.async { self.remove(id) } }
        do {
            let greeting = try await Self.read(client, count: 2)
            guard greeting[0] == 5, greeting[1] > 0 else { throw URLError(.badServerResponse) }
            let methods = try await Self.read(client, count: Int(greeting[1]))
            guard methods.contains(2) else { throw URLError(.userAuthenticationRequired) }
            try await Self.send(client, Data([5, 2]))
            let auth = try await Self.read(client, count: 2)
            guard auth[0] == 1 else { throw URLError(.userAuthenticationRequired) }
            let user = try await Self.read(client, count: Int(auth[1]))
            let length = try await Self.read(client, count: 1)
            let secret = try await Self.read(client, count: Int(length[0]))
            guard user == Data(username.utf8), secret == Data(password.utf8) else { throw URLError(.userAuthenticationRequired) }
            try await Self.send(client, Data([1, 0]))
            let command = try await Self.read(client, count: 4)
            guard command[0] == 5, command[1] == 1, command[2] == 0 else { throw URLError(.unsupportedURL) }
            let host: String
            switch command[3] {
            case 1:
                let bytes = try await Self.read(client, count: 4)
                guard let ip = IPv4Address(bytes) else { throw URLError(.cannotFindHost) }
                host = ip.debugDescription
            case 4:
                let bytes = try await Self.read(client, count: 16)
                guard let ip = IPv6Address(bytes) else { throw URLError(.cannotFindHost) }
                host = ip.debugDescription
            case 3:
                let length = try await Self.read(client, count: 1)
                let name = try await Self.read(client, count: Int(length[0]))
                guard let value = String(data: name, encoding: .utf8), !value.isEmpty else { throw URLError(.cannotFindHost) }
                host = value
            default: throw URLError(.unsupportedURL)
            }
            let portBytes = try await Self.read(client, count: 2)
            guard let port = NWEndpoint.Port(rawValue: UInt16(portBytes[0]) << 8 | UInt16(portBytes[1])) else {
                throw URLError(.badURL)
            }
            let addresses = try await SubscriptionDoHResolver.addresses(host, resolver: resolver)
            let server = try await Self.connect(addresses, port: port)
            queue.async {
                if self.closed || self.incoming[id] == nil { server.cancel() }
                else { self.outgoing[id] = server }
            }
            try await Self.send(client, Data([5, 0, 0, 1, 0, 0, 0, 0, 0, 0]))
            await withTaskGroup(of: Void.self) { group in
                group.addTask { try? await Self.pump(client, server) }
                group.addTask { try? await Self.pump(server, client) }
                await group.waitForAll()
            }
        } catch {
            queue.async {
                if !(error is CancellationError), !self.closed { self.recordedFailure = error }
            }
        }
    }
    private static func read(_ connection: NWConnection, count: Int) async throws -> Data {
        guard count > 0, count <= 255 else { throw URLError(.badServerResponse) }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                    if let error { continuation.resume(throwing: error) }
                    else if let data, data.count == count { continuation.resume(returning: data) }
                    else { continuation.resume(throwing: URLError(.networkConnectionLost)) }
                }
            }
        } onCancel: { connection.cancel() }
    }
    private static func send(_ connection: NWConnection, _ data: Data?, complete: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: data, contentContext: complete ? .finalMessage : .defaultMessage,
                            isComplete: complete, completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            })
        }
    }
    private static func pump(_ from: NWConnection, _ to: NWConnection) async throws {
        try await withTaskCancellationHandler {
            while true {
                try Task.checkCancellation()
                let chunk: (Data?, Bool) = try await withCheckedThrowingContinuation { continuation in
                    from.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { data, _, complete, error in
                        if let error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: (data, complete)) }
                    }
                }
                try await send(to, chunk.0, complete: chunk.1)
                if chunk.1 { return }
            }
        } onCancel: { from.cancel(); to.cancel() }
    }
    private static func connect(_ addresses: [String], port: NWEndpoint.Port) async throws -> NWConnection {
        try await withThrowingTaskGroup(of: NWConnection?.self) { group in
            for (index, address) in addresses.prefix(8).enumerated() {
                group.addTask {
                    do {
                        try await Task.sleep(nanoseconds: UInt64(index) * 250_000_000)
                        return try await connectOne(address, port: port)
                    } catch { return nil }
                }
            }
            for try await result in group {
                if let result {
                    group.cancelAll()
                     
                     
                    for try await other in group { other?.cancel() }
                    return result
                }
            }
            throw URLError(.cannotConnectToHost)
        }
    }
    private static func connectOne(_ address: String, port: NWEndpoint.Port) async throws -> NWConnection {
        let connection = NWConnection(host: NWEndpoint.Host(address), port: port, using: .tcp)
        let queue = DispatchQueue(label: "clash.subscription.doh.connect")
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            do {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                    let waiter = SubscriptionDNSContinuation(continuation)
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready: waiter.finish(.success(()))
                        case .failed(let error): waiter.finish(.failure(error))
                        case .cancelled: waiter.finish(.failure(CancellationError()))
                        default: break
                        }
                    }
                    connection.start(queue: queue)
                    queue.asyncAfter(deadline: .now() + 6) {
                        if waiter.finish(.failure(URLError(.timedOut))) { connection.cancel() }
                    }
                }
                return connection
            } catch { connection.cancel(); throw error }
        } onCancel: { connection.cancel() }
    }
}

@available(iOS 17, macOS 14, tvOS 17, *)
private enum SubscriptionDoHResolver {
    static func addresses(_ host: String, resolver: URL) async throws -> [String] {
        if IPv4Address(host) != nil || IPv6Address(host) != nil { return [host] }
        return try await withThrowingTaskGroup(of: [String].self) { group in
            for type: UInt16 in [1, 28] { group.addTask { try await query(host, type: type, resolver: resolver) } }
            var answers: [String] = [], failure: Error?
            while !group.isEmpty {
                do { if let result = try await group.next() { answers += result } }
                catch { failure = error }
            }
            guard !answers.isEmpty else { throw failure ?? URLError(.cannotFindHost) }
            var unique = Set<String>()
            return answers.filter { unique.insert($0).inserted }
        }
    }
    private static func query(_ host: String, type: UInt16, resolver: URL) async throws -> [String] {
        let labels = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")).split(separator: ".")
        guard !labels.isEmpty, labels.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 63 }), host.utf8.count <= 253 else {
            throw URLError(.cannotFindHost)
        }
        let id = UInt16.random(in: 0...UInt16.max)
        var message = Data([UInt8(id >> 8), UInt8(id & 255), 1, 0, 0, 1, 0, 0, 0, 0, 0, 0])
        for label in labels { message.append(UInt8(label.utf8.count)); message.append(contentsOf: label.utf8) }
        message.append(contentsOf: [0, UInt8(type >> 8), UInt8(type & 255), 0, 1])
        var request = URLRequest(url: resolver, timeoutInterval: 6)
        request.httpMethod = "POST"; request.httpBody = message
        request.setValue("application/dns-message", forHTTPHeaderField: "Content-Type")
        request.setValue("application/dns-message", forHTTPHeaderField: "Accept")
        let session = ResourceDownloader.bounded(seconds: 6)
        defer { session.invalidateAndCancel() }
        let response = try await ResourceDownloader(session: session, maximumAttempts: 1)
            .fetch(request, maxBytes: 65_535, redirectPolicy: .sameOrigin)
        let bytes = [UInt8](response.data)
        func word(_ index: Int) throws -> Int {
            guard index >= 0, index + 1 < bytes.count else { throw URLError(.badServerResponse) }
            return Int(bytes[index]) << 8 | Int(bytes[index + 1])
        }
        func name(_ offset: inout Int) throws -> String {
            var cursor = offset, jumped = false, seen = Set<Int>(), parts: [String] = [], total = 0
            while true {
                guard cursor < bytes.count, seen.insert(cursor).inserted, seen.count <= 128 else { throw URLError(.badServerResponse) }
                let length = Int(bytes[cursor])
                if length & 0xC0 == 0xC0 {
                    let pointer = try word(cursor) & 0x3FFF
                    if !jumped { offset = cursor + 2 }; jumped = true; cursor = pointer; continue
                }
                guard length <= 63, cursor + 1 + length <= bytes.count else { throw URLError(.badServerResponse) }
                cursor += 1
                if length == 0 { if !jumped { offset = cursor }; return parts.joined(separator: ".").lowercased() }
                guard let label = String(bytes: bytes[cursor..<(cursor + length)], encoding: .utf8) else { throw URLError(.badServerResponse) }
                total += length + 1; guard total <= 254 else { throw URLError(.badServerResponse) }
                parts.append(label); cursor += length
            }
        }
        guard bytes.count >= 12, try word(0) == Int(id), bytes[2] & 0x80 != 0,
              bytes[2] & 0x7A == 0, try word(4) == 1 else { throw URLError(.badServerResponse) }
        let rcode = bytes[3] & 15
        if rcode == 3 { return [] }
        guard rcode == 0 else { throw URLError(.dnsLookupFailed) }
        var offset = 12
        let question = try name(&offset)
        guard question == labels.joined(separator: "."), try word(offset) == Int(type), try word(offset + 2) == 1 else { throw URLError(.badServerResponse) }
        offset += 4
        var records: [(String, String)] = [], aliases: [String: String] = [:]
        for _ in 0..<(try word(6)) {
            let owner = try name(&offset)
            let recordType = try word(offset), recordClass = try word(offset + 2), length = try word(offset + 8)
            offset += 10
            guard offset + length <= bytes.count else { throw URLError(.badServerResponse) }
            if recordClass == 1 {
                if recordType == 5 {
                    var target = offset
                    let alias = try name(&target)
                    guard target <= offset + length else { throw URLError(.badServerResponse) }
                    aliases[owner] = alias
                } else if recordType == Int(type) {
                    let data = Data(bytes[offset..<(offset + length)])
                    if type == 1, length == 4, let ip = IPv4Address(data) { records.append((owner, ip.debugDescription)) }
                    if type == 28, length == 16, let ip = IPv6Address(data) { records.append((owner, ip.debugDescription)) }
                }
            }
            offset += length
        }
        var owners: Set<String> = [question], current = question
        while let alias = aliases[current], owners.insert(alias).inserted { current = alias }
        return records.filter { owners.contains($0.0) }.map(\.1)
    }
}

 
private final class SubscriptionDNSContinuation<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    init(_ continuation: CheckedContinuation<Value, Error>) { self.continuation = continuation }
    @discardableResult func finish(_ result: Result<Value, Error>) -> Bool {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        guard let continuation else { return false }
        continuation.resume(with: result)
        return true
    }
}
