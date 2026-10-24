#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 

 
 
protocol ModuleTableSession: AnyObject {
    func close()
    var isIdle: Bool { get }
    func windDown()
    func adoptNewestIfIdle()
    func shed(for rung: ModuleEngineReport.Rung)
}

extension ModuleExchange: ModuleTableSession {}

final class ModuleH2Session: ModuleTableSession {
    private let connection: ModuleH2Connection
    private let context: ModuleExchangeContext
    private var services: ModuleExchangeServices
    private let newest: (() -> ModuleExchangeServices?)?
    private var onEnd: ((_ drains: Bool) -> Void)?
    private let pool: ModuleH2UpstreamPool
    private let base: ModuleUpstreamOpening
     
    private var exchanges: [UInt32: (exchange: ModuleExchange, router: ModuleH2UpstreamRouter)] = [:]
    private var relays: [UInt32: ModuleH2StreamRelay] = [:]
    private var ended = false
    private var windingDown = false

    init(client: ModuleStream, context: ModuleExchangeContext, services: ModuleExchangeServices, limits: ModuleH2Limits = .app,
         upstreamLimits: ModuleH2Limits = .upstream, newest: (() -> ModuleExchangeServices?)? = nil,
         onEnd: @escaping (_ drains: Bool) -> Void) {
        self.context = context
        self.services = services
        self.newest = newest
        self.onEnd = onEnd
        base = services.upstreams
        let log = services.log
        connection = ModuleH2Connection(transport: client, role: .server, queue: services.queue, limits: limits,
                                        buffers: services.http2Buffers) { log.say($0) }
        pool = ModuleH2UpstreamPool(queue: services.queue, base: services.upstreams, limits: upstreamLimits,
                                    buffers: services.http2Buffers) { log.say($0) }
    }

    func start() {
        dispatchPrecondition(condition: .onQueue(services.queue))
        connection.onRequest = { [weak self] stream, head in self?.take(stream, head) }
        connection.onEnd = { [weak self] why in self?.connectionEnded(why) }
        connection.start()
    }

    private func say(_ line: String) { services.log.say(line) }

     

    func close() {
        dispatchPrecondition(condition: .onQueue(services.queue))
        finish(drains: false) { connection.close(#"the session was closed"#) }
    }

    var isIdle: Bool { !ended && connection.openStreamCount == 0 && exchanges.isEmpty && relays.isEmpty }
    var isWindingDown: Bool { windingDown }
    var streamCount: Int { exchanges.count + relays.count }
     
    var upstreamRequestsWaiting: Int { pool.waitingCount }

     
     
    func windDown() {
        dispatchPrecondition(condition: .onQueue(services.queue))
        guard !ended, !windingDown else { return }
        windingDown = true
        if isIdle { say(#"the engine stopped for memory: the idle session for \#(context.host) is closed"#) }
        connection.goAway(.noError, #"the engine stopped for memory"#)
    }

    func adoptNewestIfIdle() {
        guard !ended, exchanges.isEmpty, relays.isEmpty, let newer = newest?() else { return }
        services = newer
    }

    func shed(for rung: ModuleEngineReport.Rung) {
        adoptNewestIfIdle()
        for entry in exchanges.values { entry.exchange.shed(for: rung) }
        if rung >= .engineStopped { windDown() }
    }

     

    private func take(_ stream: ModuleH2Stream, _ head: HTTP2RequestHead) {
        guard !ended else { return stream.reset(.refusedStream) }
        services.allowance.noteActivity()
        if let newer = newest?() { services = newer }
        let headEnded = stream.isRemoteEnded
        let url = #"\#(context.scheme)://\#(head.effectiveAuthority ?? context.host)\#(head.path ?? "")"#
        guard head.method != "CONNECT" else {
            services.metrics.update { $0.requestsTotal += 1 }
            say(#"refused CONNECT \#(head.effectiveAuthority ?? "") inside \#(context.scheme)://\#(context.host): a session names one origin"#)
            return answer(stream, status: 405)
        }
        guard let h1 = ModuleH2Bridge.h1Request(head, endStream: headEnded) else {
            say(#"the request \#(head.method) \#(url) cannot be read as HTTP/1.1 for the rules: relayed as it came"#)
            return relay(stream, head, h1: nil, url: url)
        }
        if mayAct(on: h1.head) {
            bridge(stream, head, h1: h1, headEnded: headEnded, url: url, preopened: nil, buffered: [])
        } else {
            relay(stream, head, h1: h1, url: url)
        }
    }

     
     
     
    private func mayAct(on head: ModuleHTTPRequestHead) -> Bool {
        services.program.mayAct(on: ModuleRequestURLs.make(scheme: context.scheme, connectionHost: context.host,
                                                           port: context.target.port, head: head))
    }

    private var defaultKey: ModuleH2UpstreamPool.Key {
        ModuleH2UpstreamPool.Key(authority: context.target.authority, serverName: context.host)
    }

     
     
    private func relay(_ stream: ModuleH2Stream, _ head: HTTP2RequestHead, h1: (head: ModuleHTTPRequestHead, bytes: Data, chunked: Bool)?,
                       url: String) {
        services.metrics.update { $0.requestsTotal += 1 }
        let headEnded = stream.isRemoteEnded
        let relay = ModuleH2StreamRelay(app: stream, head: head) { [weak self] in self?.relays[stream.id] = nil }
        relays[stream.id] = relay
        let key = defaultKey
        relay.ticket = pool.request(key, method: head.method) { [weak self] result in
            guard let self, !self.ended else {
                if case .success(.h2(let up)) = result { up.reset(.cancel) }
                if case .success(.h1(let raw)) = result { Self.letGo(raw) }
                return relay.abandon()
            }
            switch result {
            case .failure(let failure):
                self.relays[stream.id] = nil
                _ = relay.handOver()
                self.services.metrics.update {
                    $0.upstreamFailuresTotal += 1
                    if case .untrusted = failure { $0.upstreamUntrustedTotal += 1 }
                }
                self.say(#"upstream \#(key.authority) (\#(key.serverName)) failed: \#(failure)"#)
                guard !stream.isOver else { return }
                self.answer(stream, status: 502)
            case .success(.h2(let up)):
                relay.begin(up)
            case .success(.h1(let raw)):
                self.relays[stream.id] = nil
                let buffered = relay.handOver()
                guard let h1, !stream.isOver else {
                    Self.letGo(raw)
                    if h1 == nil { stream.reset(.internalError) }
                    return
                }
                 
                 
                self.services.metrics.update { $0.requestsTotal -= 1 }
                self.bridge(stream, head, h1: h1, headEnded: headEnded, url: url, preopened: (key, raw), buffered: buffered)
            }
        }
    }

    private func bridge(_ stream: ModuleH2Stream, _ head: HTTP2RequestHead, h1: (head: ModuleHTTPRequestHead, bytes: Data, chunked: Bool),
                        headEnded: Bool, url: String, preopened: (key: ModuleH2UpstreamPool.Key, stream: ModuleStream)?,
                        buffered: [ModuleH2StreamRelay.Buffered]) {
        let log = services.log
        let shared = ModuleH2StreamShared(original: head, synthesizedHost: h1.head.headers.first(#"host"#))
         
         
        stream.creditsConnectionOnReceipt = true
        shared.onUpstreamOpened = { [weak stream] in stream?.creditsConnectionOnReceipt = false }
        let app = ModuleH2AppStream(stream, request: h1, headEnded: headEnded, url: url, shared: shared,
                                    queue: services.queue) { log.say($0) }
        for item in buffered {
            switch item {
            case .data(let data, let end): app.appSent(data, end: end)
            case .trailers(let trailers): app.appSentTrailers(trailers)
            }
        }
        let router = ModuleH2UpstreamRouter(pool: pool, base: base, shared: shared, queue: services.queue,
                                            preopened: preopened) { log.say($0) }
        shared.onRefused = { [weak stream] in stream?.reset(.refusedStream) }
        var mine = services
        mine.upstreams = router
        let id = stream.id
        let newest = self.newest
        let exchange = ModuleExchange(client: app, buffered: Data(), context: context, services: mine, newest: {
            guard var newer = newest?() else { return nil }
            newer.upstreams = router
            return newer
        }, oneRequest: true) { [weak self] in
            router.discard()
            self?.exchanges[id] = nil
        }
        exchanges[id] = (exchange, router)
        exchange.start()
    }

     
    private static func letGo(_ stream: ModuleStream) {
        if let lent = stream as? ModuleUpstreamGivingBack { lent.giveBack() } else { stream.cancel() }
    }

     
     
    private func answer(_ stream: ModuleH2Stream, status: Int) {
        let empty = ModuleHTTPHeaders([ModuleHTTPField(name: #"content-length"#, value: "0")])
        let fields = (try? HTTP2ResponseHead(status: status, headers: empty).fields()) ?? [HPACKField(#":status"#, String(status))]
        stream.sendHead(fields, endStream: true) { [weak stream] _ in
            guard let stream, !stream.isOver, !stream.isRemoteEnded else { return }
            stream.reset(.noError)
        }
    }

     

    private func connectionEnded(_ why: String) {
        finish(drains: true) {}
    }

    private func finish(drains: Bool, _ last: () -> Void) {
        guard !ended else { return }
        ended = true
        let open = exchanges.values.map(\.exchange)
        exchanges.removeAll()
        let relayed = Array(relays.values)
        relays.removeAll()
        for exchange in open { exchange.close() }
        for relay in relayed { relay.abandon() }
        pool.close()
        last()
        let end = onEnd
        onEnd = nil
        end?(drains)
    }
}

 
 
 
 
 
final class ModuleH2StreamRelay {
    enum Buffered {
        case data(Data, end: Bool)
        case trailers(HTTP2Trailers)
    }

    private let app: ModuleH2Stream
    private let head: HTTP2RequestHead
     
    private let headEnded: Bool
    private var onOver: (() -> Void)?
    private var buffered: [Buffered] = []
    private var upstream: ModuleH2Stream?
     
    var ticket: ModuleH2UpstreamPool.Ticket?

    init(app: ModuleH2Stream, head: HTTP2RequestHead, onOver: @escaping () -> Void) {
        self.app = app
        self.head = head
        self.onOver = onOver
        headEnded = app.isRemoteEnded
         
         
        app.creditsConnectionOnReceipt = true
        app.onData = { [weak self] data, end in self?.buffered.append(.data(data, end: end)) }
        app.onTrailers = { [weak self] trailers in self?.buffered.append(.trailers(trailers)) }
        app.onEnd = { [weak self] how in self?.appEnded(how) }
    }

    func begin(_ up: ModuleH2Stream) {
        ticket = nil
        guard !app.isOver else {
            up.reset(.cancel)
            return over()
        }
        upstream = up
        app.creditsConnectionOnReceipt = false
        let app = self.app
        guard let fields = try? head.fields() else {
            up.reset(.cancel)
            return app.reset(.internalError)
        }
        up.sendHead(fields, endStream: headEnded)
        for item in buffered { Self.forward(item, from: app, to: up) }
        buffered = []
         
        app.onData = { [weak app, weak up] data, end in
            guard let app else { return }
            guard let up else { return app.consumed(data.count) }
            Self.forward(.data(data, end: end), from: app, to: up)
        }
        app.onTrailers = { [weak app, weak up] trailers in
            guard let app, let up else { return }
            Self.forward(.trailers(trailers), from: app, to: up)
        }
        up.onResponse = { [weak app, weak up] response in
            guard let app, let up else { return }
            guard let fields = try? response.fields() else {
                up.reset(.cancel)
                return app.reset(.internalError)
            }
            app.sendHead(fields, endStream: up.isRemoteEnded)
        }
        up.onData = { [weak app, weak up] data, end in
            guard let up else { return }
            guard let app else { return up.consumed(data.count) }
             
             
            app.sendData(data, endStream: end) { _ in up.consumed(data.count) }
        }
        up.onTrailers = { [weak app] trailers in
            app?.sendTrailers((try? trailers.fields()) ?? [])
        }
        up.onEnd = { [weak app] how in
            guard let app else { return }
            switch how {
            case .finished:
                break
            case .reset(.noError) where app.isLocalEnded:
                 
                 
                app.resetAfterSending(.noError)
            case .refused:
                app.reset(.refusedStream)
            case .reset(let code):
                app.reset(Self.carried(code))
            case .resetHere, .lost:
                app.reset(.internalError)
            }
        }
    }

     
     
    private static func carried(_ code: HTTP2ErrorCode) -> HTTP2ErrorCode {
        switch code {
        case .cancel, .refusedStream, .enhanceYourCalm, .http11Required, .internalError: return code
        default: return .internalError
        }
    }

    private static func forward(_ item: Buffered, from app: ModuleH2Stream, to up: ModuleH2Stream) {
        switch item {
        case .data(let data, let end):
            up.sendData(data, endStream: end) { _ in app.consumed(data.count) }
        case .trailers(let trailers):
            up.sendTrailers((try? trailers.fields()) ?? [])
        }
    }

    private func appEnded(_ how: ModuleH2StreamEnd) {
         
        ticket?.cancel()
        ticket = nil
        if how != .finished, let upstream, !upstream.isOver { upstream.reset(.cancel) }
        over()
    }

     
     
    func handOver() -> [Buffered] {
        let taken = buffered
        buffered = []
        app.onData = nil
        app.onTrailers = nil
        app.onEnd = nil
        onOver = nil
        return taken
    }

     
    func abandon() {
        ticket?.cancel()
        ticket = nil
        if let upstream, !upstream.isOver { upstream.reset(.cancel) }
        if !app.isOver { app.reset(.cancel) }
        over()
    }

    private func over() {
        let told = onOver
        onOver = nil
        told?()
    }
}
#endif
