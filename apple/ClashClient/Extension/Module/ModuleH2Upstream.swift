#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 

 
protocol ModuleUpstreamNegotiating: AnyObject {
     
     
    func open(authority: String, serverName: String, offering protocols: [String],
              completion: @escaping (Result<(stream: ModuleStream, negotiated: String?), ModuleUpstreamFailure>) -> Void)
}

extension ModuleUpstreamConnector: ModuleUpstreamNegotiating {}

 
 
protocol ModuleUpstreamGivingBack: AnyObject {
    func giveBack()
}

 
 
 
protocol ModuleKeptUpstream: AnyObject {
    var wasUsedBefore: Bool { get }
}

 
 
 
 
final class ModuleH2PooledHTTP11: ModuleStream, ModuleUpstreamGivingBack, ModuleKeptUpstream {
    private let base: ModuleStream
     
    private(set) var wasUsedBefore = false
    private var idle = false
    private var watching = false
    private var handOff: ((Data?, Bool, Error?) -> Void)?
    private var early: (data: Data?, isComplete: Bool, error: Error?)?
    private var ended = false
    fileprivate var onGiveBack: ((ModuleH2PooledHTTP11) -> Void)?
    fileprivate var onEnd: ((ModuleH2PooledHTTP11) -> Void)?

    fileprivate init(_ base: ModuleStream) {
        self.base = base
    }

    func receive(maximumLength: Int, _ completion: @escaping (Data?, Bool, Error?) -> Void) {
        if let early {
            self.early = nil
            return completion(early.data, early.isComplete, early.error)
        }
        if watching { return handOff = completion }
        base.receive(maximumLength: maximumLength, completion)
    }

    func send(_ data: Data, isFinal: Bool, _ completion: @escaping (Error?) -> Void) {
        base.send(data, isFinal: isFinal, completion)
    }

    func cancel() {
        guard !ended else { return }
        ended = true
        idle = false
        base.cancel()
        let told = onEnd
        onEnd = nil
        onGiveBack = nil
        told?(self)
    }

    func giveBack() {
        guard !ended else { return }
        guard let back = onGiveBack else { return cancel() }
        wasUsedBefore = true
        back(self)
    }

     
    fileprivate func lend() {
        idle = false
    }

     
    fileprivate func park() {
        idle = true
        guard !watching else { return }
        watching = true
        base.receive(maximumLength: 16 * 1024) { [weak self] data, isComplete, error in
            guard let self, !self.ended else { return }
            self.watching = false
            guard !self.idle else {
                 
                return self.cancel()
            }
            if let handOff = self.handOff {
                self.handOff = nil
                handOff(data, isComplete, error)
            } else {
                self.early = (data, isComplete, error)
            }
        }
    }
}

 
final class ModuleH2UpstreamPool {
    struct Key: Hashable {
        let authority: String
        let serverName: String
    }

     
     
    enum Grant {
        case h2(ModuleH2Stream)
        case h1(ModuleStream)
    }

     
    enum Prepared {
        case h2
        case h1(ModuleStream)
    }

     
     
     
    final class Ticket {
        fileprivate var leave: (() -> Void)?
        private(set) var isCancelled = false

        fileprivate init() {}

        func cancel() {
            guard !isCancelled else { return }
            isCancelled = true
            let leaving = leave
            leave = nil
            leaving?()
        }
    }

     
    private final class Waiter<Value> {
        let method: String
        let ticket: Ticket
        private var completion: ((Result<Value, ModuleUpstreamFailure>) -> Void)?

        init(method: String, ticket: Ticket, _ completion: @escaping (Result<Value, ModuleUpstreamFailure>) -> Void) {
            self.method = method
            self.ticket = ticket
            self.completion = completion
        }

        var isServed: Bool { completion == nil }

         
        func take() -> ((Result<Value, ModuleUpstreamFailure>) -> Void)? {
            let taken = completion
            completion = nil
            return taken
        }

        func serve(_ result: Result<Value, ModuleUpstreamFailure>) {
            take()?(result)
        }
    }

    private enum State {
        case probing([Waiter<Prepared>])
        case h2(ModuleH2Connection)
         
        case h1
    }

    private let queue: DispatchQueue
    private let base: ModuleUpstreamOpening
    private let limits: ModuleH2Limits
    private let buffers: ModuleH2BufferBudget?
    private let say: (String) -> Void
    private var states: [Key: State] = [:]
    private var waiting: [Key: [Waiter<Grant>]] = [:]
     
    private var connections: [ObjectIdentifier: ModuleH2Connection] = [:]
    private var closed = false
     
     
    static let http11ConnectionsPerUpstream = 6
    private var http11Open: [Key: Int] = [:]
    private var http11Parked: [Key: [ModuleH2PooledHTTP11]] = [:]
    private var http11Waiting: [Key: [Waiter<ModuleStream>]] = [:]
    private var http11All: [ObjectIdentifier: ModuleH2PooledHTTP11] = [:]

    init(queue: DispatchQueue, base: ModuleUpstreamOpening, limits: ModuleH2Limits = .upstream, buffers: ModuleH2BufferBudget? = nil,
         log: @escaping (String) -> Void) {
        self.queue = queue
        self.base = base
        self.limits = limits
        self.buffers = buffers
        say = log
    }

    var connectionCount: Int { connections.count }
     
    var waitingCount: Int {
        let probing = states.values.reduce(0) { total, state in
            if case .probing(let waiters) = state { return total + waiters.count }
            return total
        }
        return probing + waiting.values.reduce(0) { $0 + $1.count } + http11Waiting.values.reduce(0) { $0 + $1.count }
    }
     
    var http11ConnectionCount: Int { http11All.count }

     
    func speaksHTTP2(_ key: Key) -> Bool? {
        switch states[key] {
        case .h2?: return true
        case .h1?: return false
        case .probing?, nil: return nil
        }
    }

     
     
     
    @discardableResult
    func prepare(_ key: Key, fresh: Bool = false, ticket given: Ticket? = nil,
                 completion: @escaping (Result<Prepared, ModuleUpstreamFailure>) -> Void) -> Ticket {
        dispatchPrecondition(condition: .onQueue(queue))
        let ticket = given ?? Ticket()
        guard !ticket.isCancelled else { return ticket }
        guard !closed else {
            completion(.failure(.unreachable(#"the session ended"#)))
            return ticket
        }
        switch states[key] {
        case nil:
            let waiter = Waiter(method: "", ticket: ticket, completion)
            states[key] = .probing([waiter])
            ticket.leave = { [weak self, weak waiter] in self?.leaveProbe(key, waiter) }
            probe(key)
        case .probing(var waiters)?:
            let waiter = Waiter(method: "", ticket: ticket, completion)
            waiters.append(waiter)
            states[key] = .probing(waiters)
            ticket.leave = { [weak self, weak waiter] in self?.leaveProbe(key, waiter) }
        case .h2(let connection)?:
            guard connection.acceptsNewStreams else {
                states[key] = nil
                return prepare(key, fresh: fresh, ticket: ticket, completion: completion)
            }
            completion(.success(.h2))
        case .h1?:
            openHTTP11(key, fresh: fresh, ticket: ticket) { completion($0.map { .h1($0) }) }
        }
        return ticket
    }

     
     
     
    @discardableResult
    func request(_ key: Key, method: String, ticket given: Ticket? = nil,
                 completion: @escaping (Result<Grant, ModuleUpstreamFailure>) -> Void) -> Ticket {
        dispatchPrecondition(condition: .onQueue(queue))
        let ticket = given ?? Ticket()
        guard !ticket.isCancelled else { return ticket }
        guard !closed else {
            completion(.failure(.unreachable(#"the session ended"#)))
            return ticket
        }
        switch states[key] {
        case .h2(let connection)?:
            guard connection.acceptsNewStreams else {
                states[key] = nil
                return request(key, method: method, ticket: ticket, completion: completion)
            }
            if waiting[key]?.isEmpty ?? true, let stream = connection.openStream(method: method) {
                completion(.success(.h2(stream)))
                return ticket
            }
            let waiter = Waiter(method: method, ticket: ticket, completion)
            waiting[key, default: []].append(waiter)
            ticket.leave = { [weak self, weak waiter] in
                guard let self, let waiter else { return }
                self.waiting[key]?.removeAll { $0 === waiter }
                if self.waiting[key]?.isEmpty == true { self.waiting[key] = nil }
            }
        case .h1?:
            openHTTP11(key, ticket: ticket) { completion($0.map { .h1($0) }) }
        case .probing?, nil:
            prepare(key, ticket: ticket) { [weak self] result in
                switch result {
                case .failure(let failure): completion(.failure(failure))
                case .success(.h1(let stream)): completion(.success(.h1(stream)))
                case .success(.h2):
                    guard let self else { return completion(.failure(.unreachable(#"the session ended"#))) }
                    self.request(key, method: method, ticket: ticket, completion: completion)
                }
            }
        }
        return ticket
    }

     
    func close() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !closed else { return }
        closed = true
        let open = Array(connections.values)
        connections.removeAll()
        let probes = states.values.flatMap { state -> [Waiter<Prepared>] in
            if case .probing(let waiters) = state { return waiters }
            return []
        }
        states.removeAll()
        let queued = waiting.values.flatMap { $0 }
        waiting.removeAll()
        let http11 = Array(http11All.values)
        http11All.removeAll()
        http11Parked.removeAll()
        let http11Queued = http11Waiting.values.flatMap { $0 }
        http11Waiting.removeAll()
        for connection in open { connection.close(#"the session ended"#) }
        for connection in http11 { connection.cancel() }
        let ended = ModuleUpstreamFailure.unreachable(#"the session ended"#)
        probes.forEach { $0.serve(.failure(ended)) }
        queued.forEach { $0.serve(.failure(ended)) }
        http11Queued.forEach { $0.serve(.failure(ended)) }
    }

     

    private func leaveProbe(_ key: Key, _ waiter: Waiter<Prepared>?) {
        guard let waiter, case .probing(var waiters)? = states[key] else { return }
        waiters.removeAll { $0 === waiter }
        states[key] = .probing(waiters)
    }

    private func probe(_ key: Key) {
        guard let negotiating = base as? ModuleUpstreamNegotiating else {
             
            return settled(key, .h1, first: nil)
        }
        negotiating.open(authority: key.authority, serverName: key.serverName, offering: [#"h2"#, #"http/1.1"#]) { [weak self] result in
            guard let self else {
                if case .success(let opened) = result { opened.stream.cancel() }
                return
            }
            guard !self.closed else {
                if case .success(let opened) = result { opened.stream.cancel() }
                return
            }
            switch result {
            case .failure(let failure):
                guard case .probing(let waiters)? = self.states[key] else { return }
                self.states[key] = nil
                waiters.forEach { $0.serve(.failure(failure)) }
                let queued = self.waiting.removeValue(forKey: key) ?? []
                queued.forEach { $0.serve(.failure(failure)) }
            case .success(let opened) where opened.negotiated == #"h2"#:
                let connection = ModuleH2Connection(transport: opened.stream, role: .client, queue: self.queue, limits: self.limits,
                                                    buffers: self.buffers, log: self.say)
                let id = ObjectIdentifier(connection)
                connection.onEnd = { [weak self, weak connection] _ in
                    guard let self else { return }
                    self.connections[id] = nil
                    if let connection, case .h2(let current)? = self.states[key], current === connection {
                        self.states[key] = nil
                        self.serveWaiting(key)
                    }
                }
                connection.onStreamClosed = { [weak self] in self?.serveWaiting(key) }
                self.connections[id] = connection
                connection.start()
                self.settled(key, .h2(connection), first: nil)
            case .success(let opened):
                self.say(#"upstream \#(key.authority) (\#(key.serverName)) speaks HTTP/1.1: this session's HTTP/2 streams there go over HTTP/1.1, at most \#(Self.http11ConnectionsPerUpstream) connections at once"#)
                self.http11Open[key, default: 0] += 1
                self.settled(key, .h1, first: self.pooled(opened.stream, key))
            }
        }
    }

     
     
     
    private func settled(_ key: Key, _ state: State, first: ModuleH2PooledHTTP11?) {
        let waiters: [Waiter<Prepared>]
        if case .probing(let list)? = states[key] { waiters = list } else { waiters = [] }
        states[key] = state
        var spare = first
        for waiter in waiters {
            guard let completion = waiter.take() else { continue }
            switch state {
            case .h2:
                completion(.success(.h2))
            default:
                if let stream = spare {
                    spare = nil
                    completion(.success(.h1(stream)))
                } else {
                    openHTTP11(key, ticket: waiter.ticket) { completion($0.map { .h1($0) }) }
                }
            }
        }
        if let spare { given(spare, key) }
        serveWaiting(key)
    }

     
     
     
     
    private func serveWaiting(_ key: Key) {
        guard !closed else { return }
        while let next = waiting[key]?.first {
            switch states[key] {
            case .h2(let connection)? where connection.acceptsNewStreams:
                guard let stream = connection.openStream(method: next.method) else { return }
                dequeue(next, key)
                next.serve(.success(.h2(stream)))
            case .probing?:
                return
            default:
                 
                let queued = waiting.removeValue(forKey: key) ?? []
                for waiter in queued {
                    guard let completion = waiter.take() else { continue }
                    request(key, method: waiter.method, ticket: waiter.ticket, completion: completion)
                }
                return
            }
        }
    }

    private func dequeue(_ waiter: Waiter<Grant>, _ key: Key) {
        waiting[key]?.removeAll { $0 === waiter }
        if waiting[key]?.isEmpty == true { waiting[key] = nil }
    }

     
     
    private func openHTTP11(_ key: Key, fresh: Bool = false, ticket: Ticket,
                            completion: @escaping (Result<ModuleStream, ModuleUpstreamFailure>) -> Void) {
        guard !ticket.isCancelled else { return }
        guard !closed else { return completion(.failure(.unreachable(#"the session ended"#))) }
        if !fresh, var parked = http11Parked[key], let connection = parked.popLast() {
            http11Parked[key] = parked.isEmpty ? nil : parked
            connection.lend()
            return completion(.success(connection))
        }
        guard http11Open[key, default: 0] < Self.http11ConnectionsPerUpstream else {
            let waiter = Waiter(method: "", ticket: ticket, completion)
            http11Waiting[key, default: []].append(waiter)
            ticket.leave = { [weak self, weak waiter] in
                guard let self, let waiter else { return }
                self.http11Waiting[key]?.removeAll { $0 === waiter }
                if self.http11Waiting[key]?.isEmpty == true { self.http11Waiting[key] = nil }
            }
            return
        }
        http11Open[key, default: 0] += 1
        base.open(authority: key.authority, serverName: key.serverName, tls: true) { [weak self] result in
            guard let self, !self.closed else {
                if case .success(let stream) = result { stream.cancel() }
                return completion(.failure(.unreachable(#"the session ended"#)))
            }
            switch result {
            case .failure(let failure):
                self.http11Open[key, default: 1] -= 1
                if !ticket.isCancelled { completion(.failure(failure)) }
                self.serveHTTP11(key)
            case .success(let stream):
                let connection = self.pooled(stream, key)
                 
                guard !ticket.isCancelled else { return self.given(connection, key) }
                completion(.success(connection))
            }
        }
    }

    private func pooled(_ stream: ModuleStream, _ key: Key) -> ModuleH2PooledHTTP11 {
        let connection = ModuleH2PooledHTTP11(stream)
        connection.onGiveBack = { [weak self] connection in
            guard let self else { return connection.cancel() }
            self.given(connection, key)
        }
        connection.onEnd = { [weak self] connection in self?.http11Ended(connection, key) }
        http11All[ObjectIdentifier(connection)] = connection
        return connection
    }

     
     
    private func given(_ connection: ModuleH2PooledHTTP11, _ key: Key) {
        guard !closed else { return connection.cancel() }
        while let next = http11Waiting[key]?.first {
            http11Waiting[key]?.removeFirst()
            if http11Waiting[key]?.isEmpty == true { http11Waiting[key] = nil }
            guard let completion = next.take() else { continue }
            connection.lend()
            return completion(.success(connection))
        }
        http11Parked[key, default: []].append(connection)
        connection.park()
    }

    private func http11Ended(_ connection: ModuleH2PooledHTTP11, _ key: Key) {
        guard http11All.removeValue(forKey: ObjectIdentifier(connection)) != nil else { return }
        http11Open[key, default: 1] -= 1
        http11Parked[key]?.removeAll { $0 === connection }
        serveHTTP11(key)
    }

     
    private func serveHTTP11(_ key: Key) {
        guard !closed else { return }
        while let next = http11Waiting[key]?.first {
            http11Waiting[key]?.removeFirst()
            if http11Waiting[key]?.isEmpty == true { http11Waiting[key] = nil }
            guard let completion = next.take() else { continue }
            return openHTTP11(key, ticket: next.ticket, completion: completion)
        }
    }
}

 
 
 
 
final class ModuleH2UpstreamRouter: ModuleUpstreamOpening {
    private let pool: ModuleH2UpstreamPool
    private let base: ModuleUpstreamOpening
    private let shared: ModuleH2StreamShared
    private let queue: DispatchQueue
    private let say: (String) -> Void
    private var preopened: (key: ModuleH2UpstreamPool.Key, stream: ModuleStream)?
     
     
    private var opens = 0
     
    private var ticket: ModuleH2UpstreamPool.Ticket?

    init(pool: ModuleH2UpstreamPool, base: ModuleUpstreamOpening, shared: ModuleH2StreamShared, queue: DispatchQueue,
         preopened: (key: ModuleH2UpstreamPool.Key, stream: ModuleStream)? = nil, log: @escaping (String) -> Void) {
        self.pool = pool
        self.base = base
        self.shared = shared
        self.queue = queue
        self.preopened = preopened
        say = log
    }

    func open(authority: String, serverName: String, tls: Bool,
              completion: @escaping (Result<ModuleStream, ModuleUpstreamFailure>) -> Void) {
        let spare = preopened
        preopened = nil
        guard tls else {
            spare.map { Self.letGo($0.stream) }
            return base.open(authority: authority, serverName: serverName, tls: false, completion: completion)
        }
        let key = ModuleH2UpstreamPool.Key(authority: authority, serverName: serverName)
        opens += 1
        if let spare {
            if spare.key == key {
                shared.upstreamOpened()
                return completion(.success(spare.stream))
            }
            Self.letGo(spare.stream)
        }
        ticket = pool.prepare(key, fresh: opens > 1) { [self] result in
            ticket = nil
            switch result {
            case .failure(let failure):
                completion(.failure(failure))
            case .success(.h1(let stream)):
                shared.upstreamOpened()
                completion(.success(stream))
            case .success(.h2):
                completion(.success(ModuleH2UpstreamEnd(pool: pool, key: key, shared: shared, queue: queue, say: say)))
            }
        }
    }

     
     
    func discard() {
        preopened.map { Self.letGo($0.stream) }
        preopened = nil
        ticket?.cancel()
        ticket = nil
    }

     
    private static func letGo(_ stream: ModuleStream) {
        if let lent = stream as? ModuleUpstreamGivingBack { lent.giveBack() } else { stream.cancel() }
    }
}
#endif
