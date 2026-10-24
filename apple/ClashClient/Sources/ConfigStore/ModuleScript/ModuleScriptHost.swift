#if os(iOS) || os(macOS)
import CryptoKit
import Darwin
import Foundation
import JavaScriptCore

 
 
enum ModuleScriptFootprint {
    static func current() -> Int64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int64(info.phys_footprint) : 0
    }
}

 
 
 
struct ModuleScriptSourceCache {
    let byteLimit: Int
    private var entries: [String: (text: String, bytes: Int)] = [:]
    private var order: [String] = []
    private(set) var bytes = 0

    init(byteLimit: Int) { self.byteLimit = byteLimit }

    var count: Int { entries.count }

    mutating func text(for digest: String) -> String? {
        guard let entry = entries[digest] else { return nil }
        order.removeAll { $0 == digest }
        order.append(digest)
        return entry.text
    }

    mutating func insert(_ text: String, bytes size: Int, for digest: String) {
        guard size <= byteLimit, entries[digest] == nil else { return }
        while bytes + size > byteLimit, let oldest = order.first {
            order.removeFirst()
            bytes -= entries.removeValue(forKey: oldest)?.bytes ?? 0
        }
        entries[digest] = (text, size)
        order.append(digest)
        bytes += size
    }

    mutating func removeAll() {
        entries.removeAll()
        order.removeAll()
        bytes = 0
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
final class ModuleScriptHost: ModuleScriptHosting, @unchecked Sendable {
     
     
     
     
    struct Configuration: Equatable, Sendable {
         
        var maximumRunning: Int
        var maximumWaiting: Int
         
         
        var maximumHTTPTimeout: Double
         
         
        var maximumAppTimeout: Double
         
        var idleTrimAfter: Double
         
        var residueReadAfter: Double = 5
        var sourceCacheBytes: Int
        var maximumSourceBytes: Int
         
         
         
        var footprintAllowanceBytes: Int64?
         
         
        var overrunGrace: Double = 0.05
        var session: ModuleScriptSessionLimits

         
        func maximumTimeout(for kind: ModuleScriptKind) -> Double {
            kind.phase == nil ? maximumAppTimeout : maximumHTTPTimeout
        }

         
        init(_ host: ModuleScriptLimitsTable.Host, run: ModuleScriptLimitsTable.Run) {
            maximumRunning = host.maximumRunning
            maximumWaiting = host.maximumWaiting
            maximumHTTPTimeout = host.maximumHTTPTimeout
            maximumAppTimeout = host.maximumAppTimeout
            idleTrimAfter = host.idleTrimAfter
            sourceCacheBytes = host.sourceCacheBytes
            maximumSourceBytes = host.maximumSourceBytes
            footprintAllowanceBytes = host.footprintAllowanceBytes
            session = ModuleScriptSessionLimits(run)
        }

         
        init() {
            let table = ModuleScriptLimitsTable.current
            self.init(table.tunnel, run: table.tunnelRun)
        }

         
        static var platformDefault: Configuration {
            let table = ModuleScriptLimitsTable.current
            return Configuration(table.tunnel, run: table.tunnelRun)
        }

         
        static var app: Configuration {
            let table = ModuleScriptLimitsTable.current
            return Configuration(table.app, run: table.appRun)
        }
    }

     
    private final class Job: @unchecked Sendable {
        let id: UUID
        let declaration: ModuleScriptDeclaration
        let phase: ModuleScriptPhase?
        let request: ModuleScriptHostRequest?
        let response: ModuleScriptHostResponse?
        let body: Data?
        let timeout: Double
        let deadline: UInt64
         
         
        let cancelled: ModuleScriptFlag
        private let lock = NSLock()
        private var completion: ((ModuleScriptHostOutcome) -> Void)?

        init(id: UUID, declaration: ModuleScriptDeclaration, phase: ModuleScriptPhase?,
             request: ModuleScriptHostRequest?, response: ModuleScriptHostResponse?, body: Data?,
             timeout: Double, deadline: UInt64, cancelled: ModuleScriptFlag,
             completion: @escaping (ModuleScriptHostOutcome) -> Void) {
            self.id = id
            self.cancelled = cancelled
            self.declaration = declaration
            self.phase = phase
            self.request = request
            self.response = response
            self.body = body
            self.timeout = timeout
            self.deadline = deadline
            self.completion = completion
        }

         
        func finish(_ outcome: ModuleScriptHostOutcome) {
            lock.lock()
            let completion = self.completion
            self.completion = nil
            lock.unlock()
            completion?(outcome)
        }
    }

     
     
    private final class Answer: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Int, Never>?

        init(_ continuation: CheckedContinuation<Int, Never>) { self.continuation = continuation }

        func give(_ value: Int) {
            lock.lock()
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: value)
        }
    }

     
     
     
     
     
     
    private final class SessionHandle {
        var session: ModuleScriptSession?
        let settled = ModuleScriptFlag()
    }

    private struct Running {
        let job: Job
        let handle: SessionHandle
         
        let lane: Lane
        let startedAt: UInt64
        let footprintAtStart: Int64
        let sessionID: String
         
         
         
        var settled = false
    }

    private enum SourceLoad {
        case text(String)
        case refused(ModuleScriptSkipReason)
    }

     
    static let scriptsTracked = 64

    let configuration: Configuration
    let store: ModuleScriptStore
    let quarantine: ModuleScriptQuarantine

     
     
    private let control = DispatchQueue(label: "modules.scripts.control", qos: .utility)

    private let services: ModuleScriptServices
    private let makeVirtualMachine: () -> JSVirtualMachine?
    private let footprint: () -> Int64
    private let now: () -> UInt64
    private let onStop: (ModuleScriptStopReason) -> Void

     
     
     
    private var lane = Lane()
     
     
     
    private var heldLanes = 0
    private var stopReason: ModuleScriptStopReason?
    private var hasRuntime = false
     
     
    private var baseline: Int64 = 0
     
     
     
     
    private var runBaseline: Int64 = 0
    private var running: [UUID: Running] = [:]
    private var waiting: [Job] = []
    private var sources: ModuleScriptSourceCache
    private var idleTrim: DispatchWorkItem?
    private var residueRead: DispatchWorkItem?

     
     
     
     
    private final class Lane {
        let thread = ModuleScriptThread(name: "modules.scripts")
        let monitor = ModuleScriptSliceMonitor()
        var runtime: ModuleScriptRuntime?
        let contexts = NSHashTable<JSContext>.weakObjects()
    }

     
    private let shared = NSLock()
    private var storedAvailability: ModuleScriptAvailability = .available
    private var storedMetrics = ModuleScriptHostMetrics()

    init(
        configuration: Configuration = .platformDefault,
        services: ModuleScriptServices,
        store: ModuleScriptStore,
        quarantine: ModuleScriptQuarantine,
        makeVirtualMachine: @escaping () -> JSVirtualMachine? = { JSVirtualMachine() },
        footprint: @escaping () -> Int64 = ModuleScriptFootprint.current,
        now: @escaping () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        onStop: @escaping (ModuleScriptStopReason) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.services = services
        self.store = store
        self.quarantine = quarantine
        self.makeVirtualMachine = makeVirtualMachine
        self.footprint = footprint
        self.now = now
        self.onStop = onStop
        sources = ModuleScriptSourceCache(byteLimit: configuration.sourceCacheBytes)
        storedMetrics.quarantined = quarantine.all.count
    }

     
    deinit {
        let lane = self.lane
        lane.thread.async { lane.runtime = nil }
    }

     
     
    static func timeout(for script: ModuleScriptDeclaration, configuration: Configuration) -> Double {
        min(max(script.timeoutSeconds, 0.05), configuration.maximumTimeout(for: script.kind))
    }

     

    func run(
        _ script: ModuleScriptDeclaration, phase: ModuleScriptPhase?,
        request: ModuleScriptHostRequest?, response: ModuleScriptHostResponse?, body: Data?
    ) async -> ModuleScriptHostOutcome {
        let timeout = Self.timeout(for: script, configuration: configuration)
        let id = UUID()
        let deadline = now() + UInt64(timeout * 1_000_000_000)
         
         
         
        let cancelled = ModuleScriptFlag()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<ModuleScriptHostOutcome, Never>) in
                let job = Job(id: id, declaration: script, phase: phase, request: request, response: response,
                              body: body, timeout: timeout, deadline: deadline, cancelled: cancelled,
                              completion: { continuation.resume(returning: $0) })
                control.async { self.admit(job) }
            }
        } onCancel: {
            cancelled.raise()
            self.control.async { self.cancel(id) }
        }
    }

    var availability: ModuleScriptAvailability {
        shared.lock()
        defer { shared.unlock() }
        return storedAvailability
    }

    func stop(_ reason: ModuleScriptStopReason) {
        control.async { self.stopNow(reason) }
    }

    func trim() {
        control.async {
            guard self.running.isEmpty, self.waiting.isEmpty else { return }
            self.trimNow()
        }
    }

    func metrics() -> ModuleScriptHostMetrics {
        shared.lock()
        defer { shared.unlock() }
        return storedMetrics
    }

     
     
     
    func liveContexts() async -> Int {
        await withCheckedContinuation { continuation in
            let answer = Answer(continuation)
            control.async { [self] in
                let lane = self.lane
                lane.thread.async { answer.give(lane.contexts.allObjects.count) }
            }
            control.asyncAfter(deadline: .now() + 2) { answer.give(-1) }
        }
    }

     

     
     
    private static func fits(_ job: Job) -> Bool {
        switch job.declaration.phase {
        case nil: return job.phase == nil && job.request == nil && job.response == nil
        case .request?: return job.phase == .request && job.request != nil
        case .response?: return job.phase == .response && job.request != nil && job.response != nil
        }
    }

    private func admit(_ job: Job) {
        if job.cancelled.isRaised { return end(job, .skipped(.cancelled), measured: nil) }
        if let stopReason { return end(job, .skipped(.stopped(stopReason)), measured: nil) }
        guard Self.fits(job) else { return end(job, .skipped(.phaseMismatch), measured: nil) }
        let digest = job.declaration.sourceSHA256.lowercased()
        if quarantine.entry(for: digest) != nil {
            return end(job, .skipped(.quarantined(digest)), measured: nil)
        }
        let cap = configuration.maximumTimeout(for: job.declaration.kind)
        if let asked = job.declaration.timeout, asked > cap {
            services.log(#"[script] \#(job.declaration.name) asks for timeout \#(Int(asked)) s; held to \#(cap) s"#)
        }
        if running.count < configuration.maximumRunning {
            start(job)
        } else if waiting.count < configuration.maximumWaiting {
            waiting.append(job)
            let id = job.id
            control.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: job.deadline)) { [weak self] in
                self?.expireWaiting(id)
            }
        } else {
            end(job, .skipped(.busy), measured: nil)
        }
    }

    private func start(_ job: Job) {
        let source: String
        switch loadSource(job.declaration) {
        case .text(let text): source = text
         
         
        case .refused(let reason): return end(job, .skipped(reason), measured: nil)
        }
        idleTrim?.cancel()
        idleTrim = nil
        residueRead?.cancel()
        residueRead = nil
        let reading = footprint()
        if !hasRuntime {
            baseline = reading
            hasRuntime = true
        }
        if running.isEmpty { runBaseline = reading }
        let id = job.id
        let handle = SessionHandle()
        let sessionID = Self.sessionID()
        let lane = self.lane
        running[id] = Running(job: job, handle: handle, lane: lane, startedAt: now(), footprintAtStart: reading,
                              sessionID: sessionID)
        let watchAt = job.deadline + UInt64(configuration.overrunGrace * 1_000_000_000)
        control.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: watchAt)) { [weak self] in self?.watch(id) }
        let limits = configuration.session
        lane.thread.async { [weak self] in
            self?.open(job, handle: handle, lane: lane, source: source, limits: limits, sessionID: sessionID)
        }
    }

     
     
    private func open(_ job: Job, handle: SessionHandle, lane: Lane, source: String, limits: ModuleScriptSessionLimits,
                      sessionID: String) {
        let id = job.id
        guard !handle.settled.isRaised else {
            control.async { [weak self] in self?.released(id) }
            return
        }
        if lane.runtime == nil {
            do {
                lane.runtime = try ModuleScriptRuntime(makeVirtualMachine: makeVirtualMachine)
                updateMetrics { $0.virtualMachinesCreated += 1 }
            } catch {
                let reason = ModuleScriptStopReason.javaScriptUnavailable(String(describing: error))
                control.async { [weak self] in
                    self?.stopNow(reason)
                    self?.released(id)
                }
                return
            }
        }
        guard let context = lane.runtime?.makeContext() else {
            let reason = ModuleScriptStopReason.javaScriptUnavailable(ModuleScriptRuntime.Failure.noContext.description)
            control.async { [weak self] in
                self?.stopNow(reason)
                self?.released(id)
            }
            return
        }
        lane.contexts.add(context)
        noteContexts(lane)
        let session = ModuleScriptSession(
            declaration: job.declaration, request: job.request, response: job.response,
            body: job.body, context: context, thread: lane.thread, monitor: lane.monitor, runID: id, store: store,
            services: services, limits: limits, timeoutSeconds: job.timeout, deadline: job.deadline,
            sessionID: sessionID, settled: handle.settled, now: now,
            completion: { [weak self] outcome in
                guard let self else { return }
                self.control.async { self.sessionEnded(id, outcome) }
            })
        handle.session = session
        session.start(source: source)
    }

    private func startWaiting() {
        while stopReason == nil, running.count < configuration.maximumRunning, !waiting.isEmpty {
            let job = waiting.removeFirst()
            if job.cancelled.isRaised {
                end(job, .skipped(.cancelled), measured: nil)
            } else if job.deadline <= now() {
                end(job, .skipped(.busy), measured: nil)
            } else {
                start(job)
            }
        }
    }

    private func expireWaiting(_ id: UUID) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        end(waiting.remove(at: index), .skipped(.busy), measured: nil)
    }

     
    private func cancel(_ id: UUID) {
        if let index = waiting.firstIndex(where: { $0.id == id }) {
            end(waiting.remove(at: index), .skipped(.cancelled), measured: nil)
        } else if running[id] != nil {
            settle(id, .skipped(.cancelled))
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private func watch(_ id: UUID) {
        guard let entry = running[id] else { return }
        guard entry.lane.monitor.isInside(id) else {
            if !entry.settled { settle(id, .timedOut(seconds: entry.job.timeout)) }
            return
        }
        entry.handle.settled.raise()
        let declaration = entry.job.declaration
        let digest = declaration.sourceSHA256.lowercased()
        let seconds = entry.job.timeout
        running[id] = nil
        services.log(#"[Script Timeout] \#(declaration.name): still running synchronous code after \#(seconds) s; "#
                     + #"its body \#(digest) is quarantined and the other scripts go on on a new thread"#)
        quarantine.add(ModuleScriptQuarantine.Entry(
            sha256: digest, scriptName: declaration.name, scriptPath: declaration.scriptPath, at: Date(),
            timeoutSeconds: seconds, reason: #"ran synchronous code past its \#(seconds) s timeout"#), log: services.log)
        let count = quarantine.all.count
        updateMetrics { $0.quarantined = count }
        giveUp(entry.lane, held: entry.handle,
               stoppedBy: .overran(scriptName: declaration.name, sha256: digest, seconds: seconds))
         
        if !entry.settled { end(entry.job, .timedOut(seconds: seconds), measured: nil) }
        startWaiting()
    }

     
     
     
     
     
     
     
     
    private func giveUp(_ given: Lane, held: SessionHandle, stoppedBy reason: ModuleScriptStopReason) {
        var handles = [held]
        for (id, entry) in running where entry.lane === given {
            settle(id, .skipped(.stopped(reason)))
            handles.append(entry.handle)
            running[id] = nil
        }
        if lane === given {
            lane = Lane()
            hasRuntime = false
        }
        heldLanes += 1
        services.log(#"[script] \#(heldLanes) script thread(s) held by a script past its timeout"#)
        given.thread.async { [weak self] in
            for handle in handles { handle.session = nil }
            given.runtime = nil
            self?.control.async { self?.laneCameBack() }
        }
    }

     
    private func laneCameBack() {
        heldLanes -= 1
        services.log(#"[script] a script past its timeout returned; \#(heldLanes) script thread(s) still held"#)
    }

     
     
     
     
    private func settle(_ id: UUID, _ outcome: ModuleScriptHostOutcome, say: Bool = true) {
        guard var entry = running[id], !entry.settled else { return }
        entry.settled = true
        running[id] = entry
        entry.handle.settled.raise()
        let milliseconds = Int((now() &- entry.startedAt) / 1_000_000)
        if say { log(outcome, entry.job.declaration.name, entry.sessionID, milliseconds) }
        end(entry.job, outcome, measured: say ? (milliseconds, footprint() - entry.footprintAtStart) : nil, say: false)
        let handle = entry.handle
        entry.lane.thread.async { handle.session?.end(outcome) }
    }

     
    private func released(_ id: UUID) {
        guard let entry = running[id], entry.settled else { return }
        running[id] = nil
        let lane = entry.lane
        lane.thread.async { [weak self] in self?.noteContexts(lane) }
        guard stopReason == nil else { return }
        startWaiting()
        scheduleIdleTrimIfIdle()
    }

    private func sessionEnded(_ id: UUID, _ outcome: ModuleScriptHostOutcome) {
        guard let entry = running[id] else { return }
        if entry.settled { return released(id) }
        running[id] = nil
        let milliseconds = Int((now() &- entry.startedAt) / 1_000_000)
        let current = footprint()
        log(outcome, entry.job.declaration.name, entry.sessionID, milliseconds)
        let over = current - baseline
        updateMetrics { metrics in
            metrics.footprintBytes = over
            metrics.footprintBytesPeak = max(metrics.footprintBytesPeak, over)
        }
         
         
        let added = current - runBaseline
        if stopReason == nil, let allowance = configuration.footprintAllowanceBytes, added > allowance {
            stopNow(.footprint(overBaselineBytes: added, allowanceBytes: allowance))
        }
        end(entry.job, outcome, measured: (milliseconds, current - entry.footprintAtStart))
        let lane = entry.lane
        lane.thread.async { [weak self] in self?.noteContexts(lane) }
        guard stopReason == nil else { return }
        startWaiting()
        scheduleIdleTrimIfIdle()
    }

    private func end(_ job: Job, _ outcome: ModuleScriptHostOutcome,
                     measured: (milliseconds: Int, footprintDelta: Int64)?, say: Bool = true) {
        if say, measured == nil, case .skipped(let reason) = outcome {
            services.log(#"[script] \#(job.declaration.name) not run: \#(reason)"#)
        }
         
        let storeBytes = store.knownTotalBytes
        let path = job.declaration.scriptPath
        updateMetrics { metrics in
            metrics.runs += 1
            metrics.storeBytes = storeBytes
            if metrics.scripts[path] == nil, metrics.scripts.count >= Self.scriptsTracked,
               let dropped = metrics.scripts.keys.first {
                metrics.scripts[dropped] = nil
            }
            var script = metrics.scripts[path] ?? ModuleScriptHostMetrics.Script()
            script.runs += 1
            switch outcome {
            case .done:
                metrics.done += 1
                script.done += 1
            case .aborted:
                metrics.aborted += 1
                script.aborted += 1
            case .timedOut:
                metrics.timedOut += 1
                script.timedOut += 1
            case .skipped:
                metrics.skipped += 1
                script.skipped += 1
            }
            if let measured {
                script.lastMilliseconds = measured.milliseconds
                script.footprintDeltaPeakBytes = max(script.footprintDeltaPeakBytes, measured.footprintDelta)
            }
            metrics.scripts[path] = script
        }
        job.finish(outcome)
    }

     
    private func log(_ outcome: ModuleScriptHostOutcome, _ name: String, _ sessionID: String, _ milliseconds: Int) {
        let who = #"\#(name) \#(sessionID)"#
        switch outcome {
        case .done(let result): services.log(#"[script] \#(who) done in \#(milliseconds) ms: \#(Self.summary(result))"#)
        case .aborted(let message): services.log(#"[Script Aborted] \#(who): \#(message)"#)
        case .timedOut(let seconds): services.log(#"[Script Timeout] \#(who): no $done within \#(seconds) s"#)
        case .skipped(let reason): services.log(#"[script] \#(who) ended without a result: \#(reason)"#)
        }
    }

    static func summary(_ result: ModuleScriptResult) -> String {
        func fields(_ edit: ModuleScriptEdit) -> String {
            [edit.url.map { #"url \#($0)"# }, edit.status.map { #"status \#($0)"# },
             edit.headers.map { #"\#($0.count) headers"# }, edit.body.map { #"body \#($0.count) bytes"# }]
                .compactMap { $0 }.joined(separator: #", "#)
        }
        switch result {
        case .passThrough: return #"unchanged"#
        case .modifyRequest(let edit): return #"request changed (\#(fields(edit)))"#
        case .respond(let edit): return #"answered here (\#(fields(edit)))"#
        case .modifyResponse(let edit): return #"response changed (\#(fields(edit)))"#
        case .closeConnection: return #"connection closed"#
        case .completed(let json?): return #"completed (\#(json.utf8.count) bytes of JSON)"#
        case .completed(nil): return #"completed with nothing"#
        }
    }

     

    private func loadSource(_ declaration: ModuleScriptDeclaration) -> SourceLoad {
        let digest = declaration.sourceSHA256.lowercased()
        if let text = sources.text(for: digest) { return .text(text) }
        guard let data = try? Data(contentsOf: declaration.sourceFile) else {
            return .refused(.sourceMissing(declaration.sourceFile.path))
        }
        guard data.count <= configuration.maximumSourceBytes else { return .refused(.sourceTooLarge(data.count)) }
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == digest else { return .refused(.sourceMismatch(expected: digest, actual: actual)) }
        let text = String(decoding: data, as: UTF8.self)
        sources.insert(text, bytes: data.count, for: digest)
        let cacheBytes = sources.bytes
        updateMetrics { metrics in
            metrics.sourceCacheBytes = cacheBytes
            metrics.scripts[declaration.scriptPath, default: ModuleScriptHostMetrics.Script()].sourceBytes = data.count
        }
        return .text(text)
    }

    private func scheduleIdleTrimIfIdle() {
        guard running.isEmpty, waiting.isEmpty, hasRuntime, stopReason == nil else { return }
        idleTrim?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.trimNow() }
        idleTrim = work
        control.asyncAfter(deadline: .now() + configuration.idleTrimAfter, execute: work)
    }

    private func trimNow() {
        idleTrim?.cancel()
        idleTrim = nil
        guard running.isEmpty, hasRuntime, stopReason == nil else { return }
        dropRuntime()
        updateMetrics { $0.idleTrims += 1 }
        let work = DispatchWorkItem { [weak self] in self?.readResidue() }
        residueRead = work
        control.asyncAfter(deadline: .now() + configuration.residueReadAfter, execute: work)
    }

    private func readResidue() {
        residueRead = nil
        let residue = footprint() - baseline
        updateMetrics { metrics in
            metrics.residueBytes = residue
            metrics.footprintBytes = residue
        }
        services.log(#"[script] idle: \#(residue) bytes over the reading before scripts began, "#
                     + #"\#(configuration.residueReadAfter) s after the VM was let go"#)
    }

     
     
    private func dropRuntime() {
        hasRuntime = false
        sources.removeAll()
        updateMetrics { $0.sourceCacheBytes = 0 }
        let lane = self.lane
        lane.thread.async { [weak self] in
            lane.runtime = nil
            self?.noteContexts(lane)
        }
    }

    private func stopNow(_ reason: ModuleScriptStopReason) {
        guard stopReason == nil else { return }
        stopReason = reason
        shared.lock()
        storedAvailability = .stopped(reason)
        storedMetrics.stopped = "\(reason)"
        shared.unlock()
        services.log(#"[script] scripts stopped: \#(reason)"#)
         
        onStop(reason)
        idleTrim?.cancel()
        idleTrim = nil
        residueRead?.cancel()
        residueRead = nil
        let pending = waiting
        waiting.removeAll()
        for job in pending { end(job, .skipped(.stopped(reason)), measured: nil) }
         
        for id in running.keys { settle(id, .skipped(.stopped(reason)), say: false) }
        dropRuntime()
    }

     
    private func noteContexts(_ lane: Lane) {
        let live = lane.contexts.allObjects.count
        updateMetrics { metrics in
            metrics.contexts = live
            metrics.contextsPeak = max(metrics.contextsPeak, live)
        }
    }

    private func updateMetrics(_ body: (inout ModuleScriptHostMetrics) -> Void) {
        shared.lock()
        body(&storedMetrics)
        shared.unlock()
    }

    private static func sessionID() -> String {
        String(format: "%08x", UInt32.random(in: .min ... .max))
    }
}
#endif
