#if os(iOS) || os(macOS)
import Darwin
import Foundation
import os

 
 
 
 

struct ModuleMemoryReading: Equatable, Sendable {
     
    let footprint: Int64
     
     
    let headroom: Int64?
}

 
 
enum ModulePressureLevel: Int, Sendable {
    case normal = 1
    case warning = 2
    case critical = 4
}

enum ModuleMemoryProbe {
     
     
     
     
     
     
     
    static func read() -> ModuleMemoryReading {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        let footprint = result == KERN_SUCCESS ? Int64(info.phys_footprint) : -1
        #if os(iOS)
        let available = Int64(os_proc_available_memory())
        return ModuleMemoryReading(footprint: footprint, headroom: available > 0 ? available : nil)
        #else
        return ModuleMemoryReading(footprint: footprint, headroom: nil)
        #endif
    }

     
     
     
     
     
     
    static func available() -> Int64? {
        #if os(iOS)
        let available = Int64(os_proc_available_memory())
        return available > 0 ? available : nil
        #else
        return nil
        #endif
    }

     
    static func pressureLevel() -> ModulePressureLevel? {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return nil }
        return ModulePressureLevel(rawValue: Int(level))
    }
}

 
 
protocol ModulePressureSource: AnyObject {
    func start(_ handler: @escaping (DispatchSource.MemoryPressureEvent) -> Void)
    func cancel()
}

final class ModuleSystemPressureSource: ModulePressureSource {
    private let source: DispatchSourceMemoryPressure
    private var started = false
    private var cancelled = false

    init(queue: DispatchQueue) {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: queue)
    }

    func start(_ handler: @escaping (DispatchSource.MemoryPressureEvent) -> Void) {
        guard !started, !cancelled else { return }
        started = true
        source.setEventHandler { [weak source] in
            guard let source else { return }
            handler(source.data)
        }
        source.resume()
    }

    func cancel() {
        guard !cancelled else { return }
        cancelled = true
        source.setEventHandler(handler: nil)
         
        if !started { source.resume() }
        source.cancel()
    }

    deinit { cancel() }
}

struct ModuleLadderThresholds: Equatable, Sendable {
     
    var scripts: Int64
    var bodies: Int64
    var engine: Int64
     
    var assumedLimit: Int64?
     
    var followsPressureOnly: Bool
     
     
     
     
     
    var bodiesAtOnceUnderPressure: Int? = nil

    private static let mib: Int64 = 1 << 20

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static let iOS = ModuleLadderThresholds(scripts: 18 * mib, bodies: 12 * mib, engine: 8 * mib,
                                             assumedLimit: 50 * mib, followsPressureOnly: false)
     
     
     
     
     
     
     
     
    static let macOS = ModuleLadderThresholds(scripts: 0, bodies: 0, engine: 0, assumedLimit: nil, followsPressureOnly: true,
                                               bodiesAtOnceUnderPressure: 2)

    static var current: ModuleLadderThresholds {
        #if os(macOS)
        return .macOS
        #else
        return .iOS
        #endif
    }
}

final class ModuleMemoryLadder: ModuleAllowance {
    typealias Rung = ModuleEngineReport.Rung
    typealias Cause = ModuleEngineReport.RungCause

     
     
    static let readingSpacing: TimeInterval = 0.25
     
     
     
     
    static let criticalRepeat: TimeInterval = 60
     
     
     
     
    static let normalHold: TimeInterval = 600

     
     
    static func monotonicNow() -> Date { Date(timeIntervalSinceReferenceDate: ModuleEngine.monotonicNow()) }

    private let thresholds: ModuleLadderThresholds
    private let probe: () -> ModuleMemoryReading
    private let pressureLevel: () -> ModulePressureLevel?
    private let now: () -> Date
    private let onChange: (Rung, Cause, ModuleMemoryReading) -> Void
    private let onReading: (ModuleMemoryReading) -> Void
     
     
    private let onLower: (Rung, Cause?) -> Void
    private(set) var rung: Rung
     
    private(set) var rungCause: Cause?
     
     
     
    private(set) var memoryRung: Rung
    private var lastReadingAt: Date?
     
     
    private var lastHeadroom: Int64?
     
    private var criticalSince: Date?
     
    private var lastCriticalAt: Date?
     
    private var normalSince: Date?
     
    private var scriptsMissing = false
    private var pressureSource: ModulePressureSource?

     
     
    init(thresholds: ModuleLadderThresholds, startingAt start: Rung = .normal, takenBy cause: Cause? = nil,
         probe: @escaping () -> ModuleMemoryReading = ModuleMemoryProbe.read,
         pressureLevel: @escaping () -> ModulePressureLevel? = ModuleMemoryProbe.pressureLevel,
         now: @escaping () -> Date = ModuleMemoryLadder.monotonicNow, onChange: @escaping (Rung, Cause, ModuleMemoryReading) -> Void,
         onReading: @escaping (ModuleMemoryReading) -> Void = { _ in },
         onLower: @escaping (Rung, Cause?) -> Void = { _, _ in }) {
        self.thresholds = thresholds
        self.probe = probe
        self.pressureLevel = pressureLevel
        self.now = now
        self.onChange = onChange
        self.onReading = onReading
        self.onLower = onLower
        rung = start
        rungCause = start == .normal ? nil : cause
        memoryRung = cause == .scriptsUnavailable ? .normal : start
        scriptsMissing = cause == .scriptsUnavailable
    }

    deinit {
        pressureSource?.cancel()
    }

    var allowsScripts: Bool { rung < .scriptsStopped }
    var allowsBodies: Bool { rung < .bodiesStopped }
    var allowsDecryption: Bool { rung < .engineStopped }
    var bodiesAtOnce: Int? { memoryRung >= .scriptsStopped ? thresholds.bodiesAtOnceUnderPressure : nil }

    func noteActivity() { evaluate() }

    func evaluate() { evaluate(forced: false) }

     
     
     
    private func evaluate(forced: Bool) {
        let at = now()
        let near = lastHeadroom.map { $0 <= thresholds.scripts } ?? false
        if !forced, !near, let last = lastReadingAt, at.timeIntervalSince(last) < Self.readingSpacing, at >= last { return }
        lastReadingAt = at
        guard !thresholds.followsPressureOnly else { return followLevel(at) }
        let reading = probe()
        onReading(reading)
        guard let headroom = reading.headroom ?? thresholds.assumedLimit.map({ $0 - reading.footprint }) else { return }
        lastHeadroom = headroom
        let target: Rung
        if headroom <= thresholds.engine {
            target = .engineStopped
        } else if headroom <= thresholds.bodies {
            target = .bodiesStopped
        } else if headroom <= thresholds.scripts {
            target = .scriptsStopped
        } else {
            target = .normal
        }
        raise(to: target, cause: .memoryHeadroom, reading)
    }

     
     
    private func followLevel(_ at: Date) {
        if criticalSince != nil, rung < .engineStopped {
            stillCritical(at)
            if criticalSince != nil { return }
        }
        easeIfNormal(at)
    }

     
     
     
    private func easeIfNormal(_ at: Date) {
        guard memoryRung > .normal, memoryRung < .engineStopped, pressureLevel() == .normal else {
            normalSince = nil
            return
        }
        guard let since = normalSince, at >= since else {
            normalSince = at
            return
        }
        guard at.timeIntervalSince(since) >= Self.normalHold else { return }
        normalSince = nil
        memoryRung = .normal
        lower(to: scriptsMissing ? .scriptsStopped : .normal, cause: scriptsMissing ? .scriptsUnavailable : nil)
    }

     
     
     
    func publication() {
        guard thresholds.followsPressureOnly, memoryRung >= .engineStopped else { return }
        memoryRung = .bodiesStopped
        if criticalSince != nil { criticalSince = now() }
        lower(to: .bodiesStopped, cause: .memoryPressure)
    }

    private func lower(to target: Rung, cause: Cause?) {
        guard target < rung else { return }
        rung = target
        rungCause = cause
        onLower(target, cause)
    }

     
     
     
    private func stillCritical(_ at: Date) {
        guard let since = criticalSince, rung < .engineStopped, let level = pressureLevel() else { return }
        guard level == .critical else {
            criticalSince = nil
            return
        }
        guard at.timeIntervalSince(since) >= Self.criticalRepeat else { return }
        let reading = probe()
        onReading(reading)
        raise(to: .engineStopped, cause: .memoryPressure, reading)
    }

     
     
     
     
     
     
     
     
    func pressure(_ event: DispatchSource.MemoryPressureEvent) {
        guard thresholds.followsPressureOnly else { return evaluate(forced: true) }
        if event.contains(.critical) {
            normalSince = nil
            let at = now()
            if criticalSince == nil { criticalSince = at }
            let repeated = lastCriticalAt.map { at.timeIntervalSince($0) < Self.criticalRepeat && at >= $0 } ?? false
            lastCriticalAt = at
            let reading = probe()
            onReading(reading)
            let fallsBack = repeated && pressureLevel() == nil
            raise(to: fallsBack ? .engineStopped : .bodiesStopped, cause: .memoryPressure, reading)
        } else if event.contains(.warning) {
            criticalSince = nil
            normalSince = nil
            let reading = probe()
            onReading(reading)
            raise(to: .scriptsStopped, cause: .memoryPressure, reading)
        } else {
            criticalSince = nil
        }
    }

     
    func scriptsUnavailable() {
        scriptsMissing = true
        raise(to: .scriptsStopped, cause: .scriptsUnavailable, probe())
    }

     
    func watchPressure(on queue: DispatchQueue,
                       source make: (DispatchQueue) -> ModulePressureSource = { ModuleSystemPressureSource(queue: $0) }) {
        guard pressureSource == nil else { return }
        let source = make(queue)
        source.start { [weak self] event in self?.pressure(event) }
        pressureSource = source
    }

     
    func stopWatching() {
        pressureSource?.cancel()
        pressureSource = nil
    }

    private func raise(to target: Rung, cause: Cause, _ reading: ModuleMemoryReading) {
        let memory = cause != .scriptsUnavailable
        let memoryRose = memory && target > memoryRung
        if memoryRose { memoryRung = target }
        if target > rung {
            rung = target
            rungCause = cause
            onChange(target, cause, reading)
        } else if memoryRose, target == rung, rungCause == .scriptsUnavailable {
             
            rungCause = cause
            onChange(target, cause, reading)
        }
    }
}

 
 
struct ModuleLadderSeams {
    var probe: () -> ModuleMemoryReading = ModuleMemoryProbe.read
    var pressureLevel: () -> ModulePressureLevel? = ModuleMemoryProbe.pressureLevel
    var now: () -> Date = ModuleMemoryLadder.monotonicNow
     
    var pressureSource: ((DispatchQueue) -> ModulePressureSource)? = { ModuleSystemPressureSource(queue: $0) }

    static var system: ModuleLadderSeams { ModuleLadderSeams() }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ModuleEngineBudget {
    static let steady: Int64 = 4 << 20
    #if os(macOS)
    static let peak: Int64 = 8 << 20
    #else
    static let peak: Int64 = 10 << 20
    #endif

     
     
     
     
     
     
     
     
    static let heldPerList: Int64 = 16 << 10
    static let heldPerListEntry: Int64 = 56
    static let heldPerListNameByte: Int64 = 4

     
     
     
     
     
     
    static let heldPerProgram: Int64 = 16 << 10
    static let heldPerRuleByte: Int64 = 4
     
     
     
     
     
     
     
     
    static let heldPerCompiledRegex: Int64 = 1_843
    static let ruleBytesPerCompiledRegex: Int64 = 30
    static let compiledRegexesAtMost = Int64(ModuleGatedMatcher.maximumPinned + ModuleRewriteProgram.maximumCarriedRegexes)

     
     
     
     
    static func programHeld(keptRuleBytes: Int, compiledRegexes: Int) -> Int64 {
        heldPerProgram + Int64(max(0, keptRuleBytes)) * heldPerRuleByte + Int64(max(0, compiledRegexes)) * heldPerCompiledRegex
    }

     
    static func listsHeld(_ assignment: ModuleEngineAssignment) -> Int64 {
        let lists = [assignment.mitmHosts, assignment.forceHTTPEngineHosts]
        let entries = lists.reduce(0) { $0 + $1.items.count }
        let bytes = lists.reduce(0) { total, list in
            total + list.items.reduce(0) { sum, item in
                if case .name(let name) = item.entry.pattern { return sum + name.utf8.count }
                return sum
            }
        }
        return heldPerList + Int64(entries) * heldPerListEntry + Int64(bytes) * heldPerListNameByte
    }

     
    static func programHeld(ruleBytes: Int) -> Int64 {
        let bytes = Int64(max(0, ruleBytes))
        return heldPerProgram + bytes * heldPerRuleByte + min(bytes / ruleBytesPerCompiledRegex, compiledRegexesAtMost) * heldPerCompiledRegex
    }

     
     
     
    static func ruleBytes(listsHolding lists: Int64) -> Int {
        let left = steady - lists
        var low = 0, high = ModuleReader.maximumRuleBytes
        guard programHeld(ruleBytes: high) > left else { return high }
        while low < high {
            let middle = (low + high + 1) / 2
            if programHeld(ruleBytes: middle) <= left { low = middle } else { high = middle - 1 }
        }
        return low
    }
}

extension ModuleEngineAssembly {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    static func react(engine: ModuleEngine, reporter: ModuleEngineReporter, scripts: ModuleScriptRunning)
        -> (ModuleEngineReport.Rung, ModuleEngineReport.RungCause, ModuleMemoryReading) -> Void {
        { [weak engine, weak reporter] rung, cause, reading in
            guard let engine, let reporter, rung > .normal else { return }
            let before = reporter.report.rung
            let mib = { (bytes: Int64?) in bytes.map { String(format: "%.1f MiB", Double($0) / 1_048_576) } ?? "unknown" }
            let what: String
            switch rung {
            case .normal: what = "nothing stops"
            case .scriptsStopped: what = "scripts stop"
            case .bodiesStopped: what = "scripts and body changes stop"
            case .engineStopped: what = "every new session is relayed untouched"
            }
            let name = cause == .scriptsUnavailable ? "rung" : "memory rung"
            engine.log.say("\(name) \(rung.rawValue) (\(cause.rawValue)), \(what): footprint \(mib(reading.footprint)), headroom \(mib(reading.headroom))")
            scripts.releaseAll()
            if rung >= .engineStopped { engine.passThroughCauses.insert(.memory) }
            engine.interceptor?.shed(for: rung)
            engine.metrics.update {
                if before < .scriptsStopped { $0.ladderScriptsStoppedTotal += 1 }
                if before < .bodiesStopped, rung >= .bodiesStopped { $0.ladderBodiesStoppedTotal += 1 }
                if before < .engineStopped, rung >= .engineStopped { $0.ladderEngineStoppedTotal += 1 }
            }
            reporter.record {
                if rung > before {
                    $0.rung = rung
                    $0.rungAt = reporter.now()
                }
                if rung >= before { $0.rungCause = cause }
                $0.footprintBytes = reading.footprint
                $0.headroomBytes = reading.headroom
                $0.counters = engine.metrics.counters
                if rung >= .engineStopped {
                    $0.state = .passThrough
                    if before < .engineStopped { $0.lastMemoryStopAt = reporter.now() }
                }
            }
        }
    }

     
     
     
     
     
    static func relax(engine: ModuleEngine, reporter: ModuleEngineReporter) -> (ModuleEngineReport.Rung, ModuleEngineReport.RungCause?) -> Void {
        { [weak engine, weak reporter] rung, cause in
            guard let engine, let reporter else { return }
            let why = rung >= .bodiesStopped ? "a new publication ends rung 3" : "the system's memory pressure stayed normal for 10 minutes"
            engine.log.say("memory rung \(rung.rawValue) (\(cause?.rawValue ?? "none")): \(why)")
            if rung < .engineStopped { engine.passThroughCauses.remove(.memory) }
            reporter.record {
                $0.rung = rung
                $0.rungCause = cause
                $0.rungAt = reporter.now()
                if rung < .engineStopped, $0.state == .passThrough, !engine.passThroughOnly { $0.state = .running }
            }
        }
    }
}
#endif
