#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

 
 
 
 
 
protocol ModuleScriptUpstreamOpening: AnyObject {
    func open(authority: String, serverName: String, tls: Bool, insecure: Bool, outbound: String?,
              completion: @escaping (Result<ModuleStream, ModuleUpstreamFailure>) -> Void)
}

extension ModuleUpstreamConnector: ModuleScriptUpstreamOpening {}

 
 
 
 
enum ModuleScriptOutbound {
    static let header = #"Clash-Outbound"#

     
     
     
    static func encoded(_ name: String) -> String {
        var out = ""
        for byte in name.utf8 {
            switch byte {
            case UInt8(ascii: "A")...UInt8(ascii: "Z"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "."), UInt8(ascii: "_"), UInt8(ascii: "~"):
                out.unicodeScalars.append(Unicode.Scalar(byte))
            default:
                out += String(format: "%%%02X", byte)
            }
        }
        return out
    }

     
     
     
    static func refusal(_ name: String) -> String? {
        if ModuleRuntimeNames.engineGeneration(of: name) != nil {
            return #"the outbound "\#(name)" is the module engine's own; a request on it would come back here"#
        }
         
         
        if rejects.contains(name) { return #"the outbound "\#(name)" refuses every request"# }
        return nil
    }

     
     
     
     
    static let rejects: Set<String> = ["REJECT", "REJECT-DROP", "REJECT-NO-DROP", "REJECT-TINYGIF"]

     
     
    static func refused(_ name: String, status: Int) -> String? {
        switch status {
        case 502: return #"no outbound named "\#(name)""#
        case 400: return #"Clash could not read the outbound name "\#(name)""#
        default: return nil
        }
    }
}

final class ModuleScriptNetwork: ModuleScriptNetworking, @unchecked Sendable {
     
     
    static let outboundOptions = ["policy", "node"]
     
     
     
    static let routingOptions = ["policy-descriptor", "alpn"]
     
     
    static let stashProxyHeader = #"X-Stash-Selected-Proxy"#
     
     
     
     
    static let acceptedEncodings = #"gzip, deflate"#

     
     
    static let defaultTimeoutSeconds: Double = 5

    private let limits: ModuleScriptLimitsTable.Run
     
     
     
     
    private let ceiling: Int
    private let defaultTimeoutSeconds: Double
    private let bytesBudget: Int
    private let date: () -> Date
    private let log: (String) -> Void
    private let now: () -> UInt64
    private let lock = NSLock()
    private var upstreams: (opener: ModuleScriptUpstreamOpening, queue: DispatchQueue)?
    private var stopped: String?
    private var running: [Int: ModuleScriptHTTPOperation] = [:]
    private var jars: [String: ModuleScriptCookieJar] = [:]
    private var nextID = 1
     
     
    private var held: [Int: Int] = [:]
    private var heldTotal = 0
    private var heldMost = 0
     
    private var paused: [(id: Int, queue: DispatchQueue, read: () -> Void)] = []

    init(limits: ModuleScriptLimitsTable.Run = ModuleScriptLimitsTable.current.tunnelRun,
         ceiling: Int = ModuleScriptLimitsTable.current.tunnel.maximumRunning
             * ModuleScriptLimitsTable.current.tunnelRun.maximumPendingRequests,
         bytesInFlight: Int = ModuleScriptLimitsTable.current.tunnel.maximumNetworkBytesInFlight,
         defaultTimeoutSeconds: Double = ModuleScriptNetwork.defaultTimeoutSeconds,
         date: @escaping () -> Date = Date.init,
         now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
         log: @escaping (String) -> Void) {
        self.limits = limits
        self.ceiling = ceiling
        self.bytesBudget = bytesInFlight
        self.date = date
        self.defaultTimeoutSeconds = defaultTimeoutSeconds
        self.now = now
        self.log = log
    }

     
    var bytesInFlight: Int { lock.lock(); defer { lock.unlock() }; return heldTotal }
    var mostBytesInFlight: Int { lock.lock(); defer { lock.unlock() }; return heldMost }

     
     
    func attach(_ opener: ModuleScriptUpstreamOpening, queue: DispatchQueue) {
        lock.lock()
        upstreams = (opener, queue)
        lock.unlock()
    }

     
     
     
    func stop(_ why: String) {
        lock.lock()
        let first = stopped == nil
        if first { stopped = why }
        let all = Array(running.values)
        running.removeAll()
        jars.removeAll()
        lock.unlock()
        guard first else { return }
        log(#"[$httpClient] stopped: \#(why); \#(all.count) request\#(all.count == 1 ? "" : "s") let go"#)
        all.forEach { $0.cancel(why) }
    }

     

    func send(_ request: ModuleScriptHTTPRequest, run: ModuleScriptHTTPRun,
              completion: @escaping @Sendable (Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) -> Void)
        -> ModuleScriptNetworkCancellation {
        start(request, run: run, completion: completion)
    }

     
     
    func runEnded(_ id: String) {
        lock.lock()
        let ended = running.values.filter { $0.runID == id }
        for operation in ended { running[operation.id] = nil }
        jars[id] = nil
        lock.unlock()
        ended.forEach { $0.cancel(#"the script's run ended"#) }
    }

     
    private func cancel(_ id: Int) {
        lock.lock()
        let operation = running.removeValue(forKey: id)
        lock.unlock()
        operation?.cancel(#"the script's run ended"#)
    }

     

    private func start(_ request: ModuleScriptHTTPRequest, run: ModuleScriptHTTPRun,
                       completion: @escaping @Sendable (Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) -> Void)
        -> ModuleScriptNetworkCancellation {
        let fail = { (message: String) -> ModuleScriptNetworkCancellation in
            completion(.failure(ModuleScriptNetworkFailure(message: message)))
            return ModuleScriptNetworkCancellation()
        }
        let said = #"\#(request.method) \#(request.url)"#
        if let host = ModuleScriptHTTPTarget.nonASCIIHost(in: request.url) {
            let why = #"non-ASCII host names are not supported: \#(host)"#
            log(#"[$httpClient] \#(said): \#(why)"#)
            return fail(why)
        }
        guard let target = ModuleScriptHTTPTarget(request.url) else {
            return fail(#"\#(request.url.isEmpty ? "an empty address" : request.url) is not an http or https address"#)
        }
         
        var headers = request.headers
        for option in Self.routingOptions where request.options[option] != nil {
            log(#"[$httpClient] \#(said): \#(option) is not supported here; it goes on over HTTP/1.1"#)
        }
        let stash = headers.last { $0.name.caseInsensitiveCompare(Self.stashProxyHeader) == .orderedSame }
            .map { $0.value.removingPercentEncoding ?? $0.value }
        headers.removeAll { $0.name.caseInsensitiveCompare(Self.stashProxyHeader) == .orderedSame }
        let outbound = (Self.outboundOptions.lazy.compactMap { request.options[$0] }.first ?? stash)
            .flatMap { $0.isEmpty ? nil : $0 }
        if let outbound {
            if let refusal = ModuleScriptOutbound.refusal(outbound) {
                log(#"[$httpClient] \#(said): \#(refusal)"#)
                return fail(refusal)
            }
            log(#"[$httpClient] \#(said): goes out on "\#(outbound)""#)
        }
        let insecure = Self.flag(request.options["insecure"], otherwise: false)
        if insecure { log(#"[$httpClient] \#(said): insecure: the server's certificate is not checked for this request"#) }
         
        let seconds = request.timeoutSeconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? defaultTimeoutSeconds
        let started = now()
        let deadline = min(started &+ UInt64(min(seconds, 86_400) * 1_000_000_000), run.deadline)
        guard deadline > started else { return fail(#"the script's run has no time left for it"#) }
        let waited = Double(deadline - started) / 1_000_000_000

        lock.lock()
        if let stopped {
            lock.unlock()
            return fail(stopped)
        }
        guard let upstreams else {
            lock.unlock()
            return fail(ModuleScriptNoNetwork.unavailable)
        }
        let id = nextID
        nextID += 1
        guard running.count < ceiling else {
            let count = running.count
            lock.unlock()
            return fail(#"\#(count) requests are out already, every run's together"#)
        }
        let operation = ModuleScriptHTTPOperation(
            id: id, runID: run.id, method: request.method, target: target, headers: headers, body: request.body,
            insecure: insecure, outbound: outbound, autoRedirect: Self.flag(request.options["auto-redirect"], otherwise: true),
            autoCookie: Self.flag(request.options["auto-cookie"], otherwise: true), waitSeconds: waited,
            maximumResponseBytes: request.maximumResponseBytes ?? limits.maximumResponseBodyBytes,
            maximumRedirects: limits.maximumRedirects,
            opener: upstreams.opener, queue: upstreams.queue, network: self, log: log, completion: completion)
        running[id] = operation
        lock.unlock()
        upstreams.queue.async {
            operation.arm()
            operation.start()
        }
        return ModuleScriptNetworkCancellation { [weak self] in self?.cancel(id) }
    }

     
    fileprivate func finished(_ operation: ModuleScriptHTTPOperation) {
        lock.lock()
        running[operation.id] = nil
        lock.unlock()
    }

     

     
    fileprivate func hold(_ operation: ModuleScriptHTTPOperation, bytes: Int) {
        lock.lock()
        heldTotal += bytes - (held[operation.id] ?? 0)
        held[operation.id] = bytes
        heldMost = max(heldMost, heldTotal)
        lock.unlock()
    }

     
     
     
     
    fileprivate func whenRoom(_ operation: ModuleScriptHTTPOperation, _ read: @escaping () -> Void) {
        lock.lock()
        let others = running.count - 1
        guard heldTotal >= bytesBudget, paused.count < others else {
            lock.unlock()
            return read()
        }
        paused.append((operation.id, operation.queue, read))
        let total = heldTotal
        lock.unlock()
        log(#"[$httpClient] \#(operation.shown): waits to read; \#(total) of \#(bytesBudget) bytes in flight"#)
    }

     
    fileprivate func release(_ operation: ModuleScriptHTTPOperation) {
        lock.lock()
        heldTotal -= held.removeValue(forKey: operation.id) ?? 0
        paused.removeAll { $0.id == operation.id }
        var resumed: [(queue: DispatchQueue, read: () -> Void)] = []
         
         
        let others = running.count - (running[operation.id] == nil ? 0 : 1)
        while !paused.isEmpty, heldTotal < bytesBudget || (resumed.isEmpty && paused.count >= others) {
            let next = paused.removeFirst()
            resumed.append((next.queue, next.read))
        }
        lock.unlock()
        for item in resumed { item.queue.async(execute: item.read) }
    }

     

    fileprivate func cookies(for host: String, overHTTPS: Bool, run: String?) -> String? {
        guard let run else { return nil }
        lock.lock()
        defer { lock.unlock() }
        return jars[run]?.header(for: host, overHTTPS: overHTTPS)
    }

    fileprivate func store(_ setCookies: [String], from host: String, overHTTPS: Bool, run: String?) {
        guard let run, !setCookies.isEmpty else { return }
        let now = date()
        lock.lock()
        defer { lock.unlock() }
         
        guard stopped == nil, running.values.contains(where: { $0.runID == run }) else { return }
        jars[run, default: ModuleScriptCookieJar()].store(setCookies, from: host, overHTTPS: overHTTPS, now: now)
    }

     
    static func flag(_ written: String?, otherwise: Bool) -> Bool {
        guard let written = written?.trimmingCharacters(in: .whitespaces).lowercased() else { return otherwise }
        switch written {
        case "true", "1", "yes": return true
        case "false", "0", "no": return false
        default: return otherwise
        }
    }
}

 
 
 
struct ModuleScriptHTTPTarget: Equatable {
    let scheme: String
    let host: String
    let port: Int
    let target: String

    init?(_ address: String, relativeTo base: ModuleScriptHTTPTarget? = nil) {
        let resolved: URLComponents?
        if let base {
            resolved = URL(string: address, relativeTo: base.url).flatMap { URLComponents(url: $0.absoluteURL, resolvingAgainstBaseURL: false) }
        } else {
            resolved = URLComponents(string: address)
        }
        guard let components = resolved, let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let rawHost = components.host, !rawHost.isEmpty, components.user == nil, components.password == nil else { return nil }
        let defaultPort = scheme == "https" ? 443 : 80
        let port = components.port ?? defaultPort
        guard (1...65_535).contains(port) else { return nil }
        var path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        if let query = components.percentEncodedQuery { path += "?" + query }
        guard ModuleHTTPParser.isValidTarget(path[...]) else { return nil }
        self.scheme = scheme
        self.host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        self.port = port
        self.target = path
    }

     
     
     
    static func nonASCIIHost(in address: String) -> String? {
        guard let separator = address.range(of: "://") else { return nil }
        let rest = address[separator.upperBound...]
        let authority = rest.prefix { !"/?#".contains($0) }
        let host = authority.split(separator: "@", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        let name = host.hasPrefix("[") ? host : String(host.prefix { $0 != ":" })
        return name.unicodeScalars.contains { !$0.isASCII } ? name : nil
    }

    var tls: Bool { scheme == "https" }
    private var shownHost: String { host.contains(":") ? "[\(host)]" : host }
     
    var authority: String { "\(shownHost):\(port)" }
     
    var hostField: String { port == (tls ? 443 : 80) ? shownHost : "\(shownHost):\(port)" }
    var url: URL? { URL(string: "\(scheme)://\(hostField)\(target)") }
    var shown: String { "\(scheme)://\(hostField)\(target)" }

    func sameOrigin(_ other: ModuleScriptHTTPTarget) -> Bool {
        scheme == other.scheme && host == other.host && port == other.port
    }
}

 
 
private final class ModuleScriptHTTPOperation {
    let id: Int
    let runID: String?
    let queue: DispatchQueue
    private var method: String
    private var target: ModuleScriptHTTPTarget
    private var headers: [ModuleScriptHeader]
    private var body: Data?
    private let insecure: Bool
    private let outbound: String?
    private let autoRedirect: Bool
    private let autoCookie: Bool
    private let waitSeconds: Double
    private let maximumResponseBytes: Int
    private let maximumRedirects: Int
    private let opener: ModuleScriptUpstreamOpening
    private weak var network: ModuleScriptNetwork?
    private let log: (String) -> Void
    private var completion: ((Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) -> Void)?
    private var deadline: ModuleDeadline?
    private var reader: ModuleStreamReader?
    private var hops = 0
    private var began = false

    init(id: Int, runID: String?, method: String, target: ModuleScriptHTTPTarget, headers: [ModuleScriptHeader], body: Data?,
         insecure: Bool, outbound: String?, autoRedirect: Bool, autoCookie: Bool, waitSeconds: Double, maximumResponseBytes: Int,
         maximumRedirects: Int, opener: ModuleScriptUpstreamOpening, queue: DispatchQueue, network: ModuleScriptNetwork, log: @escaping (String) -> Void,
         completion: @escaping (Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>) -> Void) {
        self.id = id
        self.runID = runID
        self.method = method
        self.target = target
        self.headers = headers
        self.body = body
        self.insecure = insecure
        self.outbound = outbound
        self.autoRedirect = autoRedirect
        self.autoCookie = autoCookie
        self.waitSeconds = waitSeconds
        self.maximumResponseBytes = maximumResponseBytes
        self.maximumRedirects = maximumRedirects
        self.opener = opener
        self.queue = queue
        self.network = network
        self.log = log
        self.completion = completion
    }

    private var said: String { #"\#(method) \#(target.shown)"# }
     
    var shown: String { said }
     
    private var interims = 0
     
     
    static let maximumInterimResponses = 16

     
    func arm() {
        guard completion != nil, deadline == nil else { return }
        let seconds = waitSeconds
        deadline = ModuleDeadline(after: seconds, queue: queue) { [weak self] in
            self?.fail(#"no response within \#(String(format: "%g", seconds)) s"#)
        }
    }

     
    func start() {
        guard completion != nil, !began else { return }
        began = true
        connect()
    }

     
    func cancel(_ why: String) {
        queue.async { [self] in finish(.failure(ModuleScriptNetworkFailure(message: why)), tellNetwork: false) }
    }

    private func fail(_ message: String) {
        finish(.failure(ModuleScriptNetworkFailure(message: message)), tellNetwork: true)
    }

    private func finish(_ result: Result<ModuleScriptHTTPResponse, ModuleScriptNetworkFailure>, tellNetwork: Bool) {
        guard let completion else { return }
        self.completion = nil
        deadline?.cancel()
        deadline = nil
        reader?.stream.cancel()
        reader = nil
        network?.release(self)
        completion(result)
        if tellNetwork { network?.finished(self) }
    }

     

    private func connect() {
        let hop = target
        opener.open(authority: hop.authority, serverName: hop.host, tls: hop.tls, insecure: insecure,
                    outbound: outbound) { [weak self] result in
            guard let self, self.completion != nil else {
                if case .success(let stream) = result { stream.cancel() }
                return
            }
            switch result {
            case .failure(let failure):
                 
                var why = Self.describe(failure)
                if case .refused(let status) = failure, let name = self.outbound,
                   let refused = ModuleScriptOutbound.refused(name, status: status) {
                    why = refused
                }
                self.fail(#"the upstream \#(hop.authority) failed: \#(why)"#)
            case .success(let stream):
                self.send(over: stream)
            }
        }
    }

    static func describe(_ failure: ModuleUpstreamFailure) -> String {
        switch failure {
        case .unreachable(let why): return why
        case .refused(let status): return #"the CONNECT was answered \#(status)"#
        case .untrusted(let why): return #"its certificate was not trusted: \#(why)"#
        case .timedOut: return #"the CONNECT timed out"#
        }
    }

     
     
     
     
     
     
    private func head() -> ModuleHTTPRequestHead {
        let framing: Set<String> = ["content-length", "transfer-encoding", "connection", "keep-alive", "proxy-connection", "te",
                                    "upgrade", "trailer", "host"]
        var fields = ModuleHTTPHeaders(headers.filter { !framing.contains($0.name.lowercased()) }
            .map { ModuleHTTPField(name: $0.name, value: $0.value) })
        fields.fields.insert(ModuleHTTPField(name: "Host", value: target.hostField), at: 0)
        if !fields.contains("Accept-Encoding") { fields.add("Accept-Encoding", ModuleScriptNetwork.acceptedEncodings) }
        if autoCookie, !fields.contains("Cookie"), let cookies = network?.cookies(for: target.host, overHTTPS: target.tls, run: runID) {
            fields.add("Cookie", cookies)
        }
        fields.add("Connection", "close")
        if let body {
            fields.add("Content-Length", String(body.count))
        } else if ["POST", "PUT", "PATCH"].contains(method.uppercased()) {
            fields.add("Content-Length", "0")
        }
        return ModuleHTTPRequestHead(method: method, target: target.target, version: .http11, headers: fields)
    }

     
     
    private func send(over stream: ModuleStream) {
        let reader = ModuleStreamReader(stream)
        self.reader = reader
        interims = 0
        let headBytes: Data
        do {
            headBytes = try ModuleHTTPSerializer.head(head())
        } catch {
            return fail(#"the request could not be written: \#(String(describing: error))"#)
        }
        let body = self.body
        stream.send(headBytes) { [weak self] error in
            guard let self, self.completion != nil else { return }
            if let error { return self.fail(#"the request could not be sent: \#(String(describing: error))"#) }
            guard let body, !body.isEmpty else { return self.readHead(reader) }
            stream.send(body) { [weak self] error in
                guard let self, self.completion != nil else { return }
                if let error { return self.fail(#"the request could not be sent: \#(String(describing: error))"#) }
                self.readHead(reader)
            }
        }
    }

     
     
    private func fill(_ reader: ModuleStreamReader, _ then: @escaping (Error?) -> Void) {
        guard let network else { return reader.fill(then) }
        network.whenRoom(self) { [weak self] in
            guard let self, self.completion != nil else { return }
            reader.fill(then)
        }
    }

     
     
    private func readHead(_ reader: ModuleStreamReader, failedRead: Bool = false) {
        let parsed: ModuleHTTPParse<ModuleHTTPResponseHead>
        do {
            parsed = try ModuleHTTPParser.response(reader.buffer)
        } catch {
            return fail(#"the response could not be read: \#(String(describing: error))"#)
        }
        switch parsed {
        case .head(let head, let consumed):
            reader.buffer = Data(reader.buffer.dropFirst(consumed))
             
            if head.isInterim {
                interims += 1
                guard interims <= Self.maximumInterimResponses else {
                    return fail(#"more than \#(Self.maximumInterimResponses) interim responses before the answer"#)
                }
                return readHead(reader, failedRead: failedRead)
            }
            let framing: ModuleHTTPFraming
            do {
                framing = try ModuleHTTPFraming.ofResponse(head, requestMethod: method)
            } catch {
                return fail(#"the response could not be read: \#(String(describing: error))"#)
            }
            readBody(reader, head, ModuleHTTPBodyReader(framing), Data())
        case .needMore:
            guard !reader.ended, !failedRead else { return fail(#"the server closed before it answered"#) }
            network?.hold(self, bytes: reader.buffer.count)
            fill(reader) { [weak self] error in
                guard let self, self.completion != nil else { return }
                self.readHead(reader, failedRead: error != nil)
            }
        }
    }

    private func readBody(_ reader: ModuleStreamReader, _ head: ModuleHTTPResponseHead, _ framed: ModuleHTTPBodyReader,
                          _ collected: Data, failedRead: Bool = false) {
        var body = framed
        var collected = collected
        do {
            let (raw, payload) = try body.consume(reader.buffer)
            reader.buffer = Data(reader.buffer.dropFirst(raw))
            collected += payload
        } catch {
            return fail(#"the response could not be read: \#(String(describing: error))"#)
        }
        guard collected.count <= maximumResponseBytes else { return fail(tooLarge) }
        network?.hold(self, bytes: reader.buffer.count + collected.count)
        if body.isComplete { return answered(head, collected) }
        if reader.ended {
            do {
                try body.endOfStream()
            } catch {
                return fail(#"the server closed before the response was whole"#)
            }
            return answered(head, collected)
        }
        guard !failedRead else { return fail(#"the server closed before the response was whole"#) }
        fill(reader) { [weak self] error in
            guard let self, self.completion != nil else { return }
            self.readBody(reader, head, body, collected, failedRead: error != nil)
        }
    }

    private var tooLarge: String {
        #"its response is over the \#(maximumResponseBytes) bytes a script may take"#
    }

    private func answered(_ head: ModuleHTTPResponseHead, _ encoded: Data) {
        reader?.stream.cancel()
        reader = nil
        if autoCookie { network?.store(head.headers.values("Set-Cookie"), from: target.host, overHTTPS: target.tls, run: runID) }
        if autoRedirect, [301, 302, 303, 307, 308].contains(head.status), let location = head.headers.first("Location") {
            return redirect(head.status, to: location)
        }
        var body = encoded
         
        for coding in ModuleContentCoding.parse(head.headers.first("Content-Encoding")).reversed() {
            do {
                let decoded = try ModuleBodyDecoder.decode(body, coding: coding, maximumOutputLength: maximumResponseBytes)
                guard !decoded.outputLimitExceeded else { return fail(tooLarge) }
                network?.hold(self, bytes: body.count + decoded.data.count)
                body = decoded.data
            } catch let failure as ModuleBodyDecoderError {
                 
                log(#"[$httpClient] \#(said): its body is not decoded (\#(failure.reason)); it is handed over as it came"#)
                break
            } catch {
                return fail(#"the response could not be decoded: \#(String(describing: error))"#)
            }
        }
        finish(.success(ModuleScriptHTTPResponse(status: head.status, headers: head.headers.fields.map {
            ModuleScriptHeader(name: $0.name, value: $0.value)
        }, body: body)), tellNetwork: true)
    }

     
     
     
    private func redirect(_ status: Int, to location: String) {
        hops += 1
        guard hops <= maximumRedirects else { return fail(#"more than \#(maximumRedirects) redirects"#) }
        if let host = ModuleScriptHTTPTarget.nonASCIIHost(in: location) {
            let why = #"non-ASCII host names are not supported: \#(host)"#
            log(#"[$httpClient] \#(said): redirected to \#(location); \#(why)"#)
            return fail(why)
        }
        guard let next = ModuleScriptHTTPTarget(location, relativeTo: target) else {
            return fail(#"it was redirected to \#(location), which is not an http or https address"#)
        }
        log(#"[$httpClient] \#(said): \#(status) to \#(next.shown)"#)
        let upper = method.uppercased()
        if status == 303 ? upper != "HEAD" : ((status == 301 || status == 302) && upper == "POST") {
            method = "GET"
            body = nil
            headers.removeAll { ["content-type", "content-encoding"].contains($0.name.lowercased()) }
        }
        if !next.sameOrigin(target) {
            headers.removeAll { ["authorization", "proxy-authorization", "cookie", "host"].contains($0.name.lowercased()) }
        }
        target = next
         
        network?.hold(self, bytes: 0)
        connect()
    }
}

#endif
