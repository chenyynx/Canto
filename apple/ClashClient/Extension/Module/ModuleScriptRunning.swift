#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 

struct ModuleScriptMatch {
    let script: ModuleScript
    let moduleID: String
     
     
     
     
    let format: ModuleFormat
     
    let bodyFile: URL?
    let origin: ModuleRuleOrigin
     
    let url: String
     
     
     
    let writtenFor: ModuleScriptFamily

    init(script: ModuleScript, moduleID: String, format: ModuleFormat, bodyFile: URL?, origin: ModuleRuleOrigin, url: String,
         writtenFor: ModuleScriptFamily? = nil) {
        self.script = script
        self.moduleID = moduleID
        self.format = format
        self.bodyFile = bodyFile
        self.origin = origin
        self.url = url
        self.writtenFor = writtenFor ?? ModuleScriptFamily(format: format)
    }
}

struct ModuleScriptRequest: Equatable, Sendable {
     
     
    var id: String
    var method: String
    var url: String
    var headers: ModuleHTTPHeaders
     
    var body: Data?
}

struct ModuleScriptResponse: Equatable, Sendable {
    var status: Int
    var headers: ModuleHTTPHeaders
    var body: Data?
}

enum ModuleScriptOutcome: Equatable, Sendable {
     
    case unchanged
     
    case request(ModuleScriptRequest)
     
    case response(ModuleScriptResponse)
     
     
    case drop(String)
     
    case aborted(String)
     
    case timedOut
     
    case unavailable(String)
}

 
 
 
final class ModuleScriptSink {
    private let queue: DispatchQueue
    private let metrics: ModuleEngineMetrics
    private let unavailable: (String) -> Void
     
     
    let upstreams: ModuleScriptUpstreamOpening?

    init(queue: DispatchQueue, metrics: ModuleEngineMetrics, upstreams: ModuleScriptUpstreamOpening? = nil,
         unavailable: @escaping (String) -> Void) {
        self.queue = queue
        self.metrics = metrics
        self.upstreams = upstreams
        self.unavailable = unavailable
    }

     
    var engineQueue: DispatchQueue { queue }

     
    func scriptsUnavailable(_ reason: String) {
        queue.async { [self] in unavailable(reason) }
    }

     
     
    func update(_ change: @escaping (inout ModuleEngineCounters) -> Void) {
        queue.async { [self] in metrics.update(change) }
    }
}

protocol ModuleScriptRunning: AnyObject {
     
     
    var isAvailable: Bool { get }
     
    func attach(_ sink: ModuleScriptSink)
     
     
     
     
    func run(_ match: ModuleScriptMatch, request: ModuleScriptRequest,
             completion: @escaping (ModuleScriptOutcome) -> Void)
    func run(_ match: ModuleScriptMatch, request: ModuleScriptRequest, response: ModuleScriptResponse,
             completion: @escaping (ModuleScriptOutcome) -> Void)
     
     
     
     
     
    func releaseAll()
     
     
     
    func cancel(_ requestID: String)
}

extension ModuleScriptRunning {
     
    func cancel(_ requestID: String) {}
}

 
 
final class ModuleNoScripts: ModuleScriptRunning {
    init() {}

    var isAvailable: Bool { false }

    func attach(_ sink: ModuleScriptSink) {}

    func run(_ match: ModuleScriptMatch, request: ModuleScriptRequest, completion: @escaping (ModuleScriptOutcome) -> Void) {
        completion(.unavailable("scripts are not part of this build"))
    }

    func run(_ match: ModuleScriptMatch, request: ModuleScriptRequest, response: ModuleScriptResponse,
             completion: @escaping (ModuleScriptOutcome) -> Void) {
        completion(.unavailable("scripts are not part of this build"))
    }

    func releaseAll() {}
}

 
 
 
 
 
 
 
 
 
final class ModuleScriptCall {
     
     
     
    static let maximumTimeout = 300
     
    static let grace: TimeInterval = 5

    enum Answer: Equatable, Sendable {
         
        case answered(ModuleScriptOutcome)
         
        case noAnswer(within: TimeInterval)
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func defaultTimeout(of match: ModuleScriptMatch) -> Int {
        switch match.format {
        case .surge, .stash: return 5
        case .loon: return 10
        case .quantumultX: return Int(ModuleScriptDefaults.quantumultXHTTPSeconds)
        }
    }

     
     
    static func limit(for match: ModuleScriptMatch, grace: TimeInterval = ModuleScriptCall.grace) -> TimeInterval {
        TimeInterval(min(maximumTimeout, max(0, match.script.timeout ?? defaultTimeout(of: match)))) + max(0, grace)
    }

    private var timer: DispatchSourceTimer?
    private var deliver: ((Answer) -> Void)?
     
    private var cancelRun: (() -> Void)?

    private init(deliver: @escaping (Answer) -> Void, cancelRun: (() -> Void)?) {
        self.deliver = deliver
        self.cancelRun = cancelRun
    }

     
     
     
    @discardableResult
    static func start(on queue: DispatchQueue, limit: TimeInterval,
                      run: (@escaping (ModuleScriptOutcome) -> Void) -> Void,
                      cancelRun: (() -> Void)? = nil,
                      deliver: @escaping (Answer) -> Void) -> ModuleScriptCall {
        dispatchPrecondition(condition: .onQueue(queue))
        let call = ModuleScriptCall(deliver: deliver, cancelRun: cancelRun)
         
         
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + max(0, limit))
        timer.setEventHandler { call.finish(.noAnswer(within: limit)) }
        call.timer = timer
        timer.resume()
         
        run { [weak call] outcome in queue.async { call?.finish(.answered(outcome)) } }
        return call
    }

     
     
    func cancel() {
        let waiting = deliver != nil
        let giveUp = cancelRun
        stop()
        if waiting { giveUp?() }
    }

    private func stop() {
        deliver = nil
        cancelRun = nil
        timer?.cancel()
        timer = nil
    }

    private func finish(_ answer: Answer) {
        guard let deliver else { return }
        stop()
        deliver(answer)
    }
}
#endif
