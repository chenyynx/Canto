#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
final class ModuleScriptRunner: ModuleScriptRunning, @unchecked Sendable {
     
     
    static let networkStopped = #"scripts are stopped for memory (rung 1)"#

    private let host: ModuleScriptHosting
     
     
    private let network: ModuleScriptNetwork?
    private let log: (String) -> Void
    private let lock = NSLock()
    private var sink: ModuleScriptSink?
     
    private var told = false
     
     
    private var inFlight: [String: Task<Void, Never>] = [:]

    init(host: ModuleScriptHosting, log: @escaping (String) -> Void, network: ModuleScriptNetwork? = nil) {
        self.host = host
        self.log = log
        self.network = network
    }

    var isAvailable: Bool { host.availability == .available }

     
     
    func attach(_ sink: ModuleScriptSink) {
        lock.lock()
        self.sink = sink
        told = false
        lock.unlock()
         
         
        if let upstreams = sink.upstreams { network?.attach(upstreams, queue: sink.engineQueue) }
        report()
    }

    func run(_ match: ModuleScriptMatch, request: ModuleScriptRequest,
             completion: @escaping (ModuleScriptOutcome) -> Void) {
        start(match, phase: .request, request: request, response: nil, body: request.body, completion: completion)
    }

    func run(_ match: ModuleScriptMatch, request: ModuleScriptRequest, response: ModuleScriptResponse,
             completion: @escaping (ModuleScriptOutcome) -> Void) {
        start(match, phase: .response, request: request, response: response, body: response.body, completion: completion)
    }

     
     
     
    func releaseAll() {
        host.stop(.engine(#"memory rung 1"#))
        network?.stop(Self.networkStopped)
    }

    private func start(
        _ match: ModuleScriptMatch, phase: ModuleScriptPhase, request: ModuleScriptRequest,
        response: ModuleScriptResponse?, body: Data?, completion: @escaping (ModuleScriptOutcome) -> Void
    ) {
        guard let declaration = Self.declaration(match) else {
            log(#"[script] \#(match.script.name) not run: \#(match.moduleID) has no published body for \#(match.script.scriptURL) yet"#)
            return completion(.unchanged)
        }
         
        let hostRequest = ModuleScriptHostRequest(
            id: request.id, url: request.url, method: request.method, headers: Self.scriptHeaders(request.headers))
        let hostResponse = response.map { ModuleScriptHostResponse(status: $0.status, headers: Self.scriptHeaders($0.headers)) }
        let host = self.host
        let key = request.id
         
         
        lock.lock()
        let task = Task { [self] in
            let outcome = await host.run(declaration, phase: phase, request: hostRequest, response: hostResponse, body: body)
            lock.lock()
            inFlight[key] = nil
            lock.unlock()
             
            report()
            completion(Self.outcome(outcome, request: request, response: response))
        }
        inFlight[key] = task
        lock.unlock()
    }

    func cancel(_ requestID: String) {
        lock.lock()
        let task = inFlight.removeValue(forKey: requestID)
        lock.unlock()
        task?.cancel()
    }

     
     
     
     
    private func report() {
        let metrics = host.metrics()
        let availability = host.availability
        lock.lock()
        guard let sink else {
            lock.unlock()
            return
        }
        var stop: String?
        if case .stopped(let reason) = availability, !told, !Self.isTheEngines(reason) {
            told = true
            stop = Self.reason(reason)
        }
        lock.unlock()
        sink.update { counters in
            counters.scriptContexts = metrics.contexts
            counters.scriptContextsPeak = max(counters.scriptContextsPeak, metrics.contextsPeak)
            counters.scriptsQuarantined = metrics.quarantined
        }
        if let stop { sink.scriptsUnavailable(stop) }
    }

    private static func isTheEngines(_ reason: ModuleScriptStopReason) -> Bool {
        if case .engine = reason { return true }
        return false
    }

     
     
    static func reason(_ stop: ModuleScriptStopReason) -> String {
        switch stop {
        case .javaScriptUnavailable(let why):
            return #"JavaScriptCore could not start: \#(why)"#
        case .footprint(let over, let allowance):
            return #"scripts used \#(over) bytes over the reading before they began, past their \#(allowance)-byte allowance"#
        case .overran(let name, let sha256, let seconds):
            return #"\#(name) ran synchronous code past its \#(seconds) s timeout; its body \#(sha256) is quarantined"#
        case .engine(let why):
            return #"stopped by the engine: \#(why)"#
        }
    }

     
     
     
     
     
     
     
     
    static func declaration(_ match: ModuleScriptMatch) -> ModuleScriptDeclaration? {
        guard let file = match.bodyFile, let sha = match.script.bodySHA256 else { return nil }
        let script = match.script
        return ModuleScriptDeclaration(
            name: script.name,
            kind: .http(script.phase == .request ? .request : .response),
            family: ModuleScriptFamily(format: match.format),
            syntax: .classic,
            scriptPath: script.scriptURL,
            sourceFile: file,
            sourceSHA256: sha,
            requiresBody: script.requiresBody,
            binaryBodyMode: script.binaryBodyMode,
            timeout: script.timeout.map(Double.init),
            argument: argument(of: script))
    }

     
    static func argument(of script: ModuleScript) -> ModuleScriptArgument? {
        if let typed = script.typedArguments {
            return .object(typed.map { field in
                let value: ModuleScriptArgument.Value
                switch field.value {
                case .string(let text): value = .string(text)
                case .number(let number): value = .number(number)
                case .bool(let flag): value = .bool(flag)
                case .null: value = .null
                }
                return ModuleScriptArgument.Field(name: field.name, value: value)
            })
        }
        return script.argument.map { .text($0) }
    }

    static func scriptHeaders(_ headers: ModuleHTTPHeaders) -> [ModuleScriptHeader] {
        headers.fields.map { ModuleScriptHeader(name: $0.name, value: $0.value) }
    }

    static func httpHeaders(_ lines: [ModuleScriptHeader]) -> ModuleHTTPHeaders {
        ModuleHTTPHeaders(lines.map { ModuleHTTPField(name: $0.name, value: $0.value) })
    }

     
    static func outcome(
        _ outcome: ModuleScriptHostOutcome, request: ModuleScriptRequest, response: ModuleScriptResponse?
    ) -> ModuleScriptOutcome {
        switch outcome {
        case .done(.passThrough):
            return .unchanged
        case .done(.modifyRequest(let edit)):
            return .request(ModuleScriptRequest(
                id: request.id, method: request.method, url: edit.url ?? request.url,
                headers: edit.headers.map { httpHeaders($0) } ?? request.headers, body: edit.body ?? request.body))
        case .done(.respond(let edit)):
            return .response(ModuleScriptResponse(
                status: edit.status ?? 200, headers: edit.headers.map { httpHeaders($0) } ?? ModuleHTTPHeaders(),
                body: edit.body ?? Data()))
        case .done(.modifyResponse(let edit)):
            let original = response ?? ModuleScriptResponse(status: 200, headers: ModuleHTTPHeaders(), body: nil)
            return .response(ModuleScriptResponse(
                status: edit.status ?? original.status, headers: edit.headers.map { httpHeaders($0) } ?? original.headers,
                body: edit.body ?? original.body))
        case .done(.closeConnection):
             
             
            return .drop(#"the script closed the connection"#)
        case .done(.completed):
             
            return .unchanged
        case .aborted(let message):
            return .aborted(message)
        case .timedOut:
            return .timedOut
        case .skipped(.stopped(let stop)):
            return .unavailable(reason(stop))
        case .skipped:
             
             
            return .unchanged
        }
    }
}
#endif
