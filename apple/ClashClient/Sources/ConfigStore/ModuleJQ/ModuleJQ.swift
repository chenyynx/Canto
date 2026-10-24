#if os(iOS) || os(macOS)
import Foundation
import os

 
 
 
 
 
 
 
 
 

 
 
 
 
 
struct ModuleRequestBudget: Sendable {
    static let perRequest: TimeInterval = 0.050

    private(set) var remainingNanoseconds: UInt64
     
    private(set) var stops = 0

    init(seconds: TimeInterval = ModuleRequestBudget.perRequest) {
        remainingNanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
    }

    var isSpent: Bool { remainingNanoseconds == 0 }

     
     
     
    static var unlimited: ModuleRequestBudget { ModuleRequestBudget(seconds: 86_400) }

     
    var remainingSeconds: TimeInterval { Double(remainingNanoseconds) / 1_000_000_000 }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    #if os(macOS)
    static let maximumBodyAllowance: TimeInterval = 0.250
    #else
    static let maximumBodyAllowance: TimeInterval = 0.128
    #endif

     
     
     
     
     
     
     
    mutating func allow(bodyBytes: Int) {
        let extra = UInt64(max(0, bodyBytes)).multipliedReportingOverflow(by: 1_000_000)
        let ceiling = UInt64(Self.maximumBodyAllowance * 1_000_000_000)
        let nanoseconds = extra.overflow ? ceiling : min(ceiling, extra.partialValue / 4_096)
        let sum = remainingNanoseconds.addingReportingOverflow(nanoseconds)
        remainingNanoseconds = sum.overflow ? .max : sum.partialValue
    }

    static func threadNanoseconds() -> UInt64 { clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) }

     
    func isSpent(since start: UInt64) -> Bool {
        Self.threadNanoseconds() &- start >= remainingNanoseconds
    }

    mutating func charge(_ nanoseconds: UInt64) {
        remainingNanoseconds = nanoseconds >= remainingNanoseconds ? 0 : remainingNanoseconds - nanoseconds
    }

     
     
     
     
    mutating func hold(_ nanoseconds: UInt64) -> UInt64 {
        let kept = min(nanoseconds, remainingNanoseconds)
        remainingNanoseconds -= kept
        return kept
    }

     
    mutating func release(_ nanoseconds: UInt64) {
        let sum = remainingNanoseconds.addingReportingOverflow(nanoseconds)
        remainingNanoseconds = sum.overflow ? .max : sum.partialValue
    }

    mutating func noteStop() { stops += 1 }
}

enum ModuleJQ {
     
     
     
    struct Program: @unchecked Sendable {
        let source: String
        let root: ModuleJQNode
    }

    struct Limits: Sendable {
         
        var steps: Int
         
        var outputBytes: Int
         
        var depth: Int
         
         
        var memoryBytes: Int
         
         
         
         
        var backstopBytes: Int

         
         
         
         
        init(steps: Int, outputBytes: Int, depth: Int) {
            self.steps = steps
            self.outputBytes = outputBytes
            self.depth = depth
            memoryBytes = max(4 << 20, outputBytes.multipliedReportingOverflow(by: 16).partialValue)
            backstopBytes = memoryBytes.multipliedReportingOverflow(by: 4).partialValue
        }

         
         
        static let engineMemoryCeiling = 32 << 20
        static let engineBackstopCeiling = 64 << 20

         
         
         
         
         
         
         
         
         
         
         
         
        static func engine(bodyBytes: Int, inputBytes: Int? = nil) -> Limits {
            var limits = Limits(steps: 4_000_000, outputBytes: bodyBytes, depth: 512)
            let input = max(0, inputBytes ?? bodyBytes)
            limits.memoryBytes = min(engineMemoryCeiling, max(4 << 20, input.multipliedReportingOverflow(by: 16).partialValue))
            limits.backstopBytes = min(engineBackstopCeiling, limits.memoryBytes * 4)
            return limits
        }
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    #if os(iOS)
    static let maximumBodyBytes = 512 << 10
    #else
    static let maximumBodyBytes = 10 << 20
    #endif

    enum RunOutcome: Equatable {
        case value(ModuleJSONValue)
        case noOutput
        case error(String)
        case stopped
    }

    struct ParseError: Error, CustomStringConvertible, Equatable {
        let message: String
        var description: String { message }
    }

     
    static func parse(_ text: String) throws -> Program {
        do {
            let syntax = try ModuleJQParser.parse(text)
            let compiler = ModuleJQCompiler(preludeReferences: try ModuleJQPrelude.loadReferences())
            return Program(source: text, root: try compiler.compile(syntax, nil))
        } catch let error as ModuleJQSyntaxError {
            throw ParseError(message: error.message)
        }
    }

     
     
     
    static func run(_ program: Program, on input: ModuleJSONValue, limits: Limits, budget: inout ModuleRequestBudget,
                    log: (String) -> Void) -> RunOutcome {
        let traced = trace(program, on: input, limits: limits, budget: &budget, maximumOutputs: 2, log: log)
        return outcome(of: traced, limits: limits, budget: &budget, log: log)
    }

     
    static func outcome(of traced: Trace, limits: Limits, budget: inout ModuleRequestBudget, log: (String) -> Void) -> RunOutcome {
        if traced.stoppedByBackstop { log("jq stopped: \(traced.ending); not counted against the rule") }
         
        if traced.outputs.isEmpty, case .stopped = traced.ending, !traced.stoppedByBackstop { budget.noteStop() }
        if let first = traced.outputs.first {
            if traced.outputs.count > 1 { log("jq gave more than one output; the first is used") }
            if case .error(let message) = traced.ending { log("jq raised after its first output: \(message)") }
            if case .stopped = traced.ending, traced.outputs.count == 1 { log("jq stopped after its first output") }
            guard ModuleJSONText.length(first, limit: limits.outputBytes) != nil else {
                log("jq's output is larger than \(limits.outputBytes) bytes")
                budget.noteStop()
                return .stopped
            }
            return .value(first)
        }
        switch traced.ending {
        case .finished, .halted: return .noOutput
        case .error(let message): return .error(message)
        case .stopped: return .stopped
        }
    }

     
     
    static func run(_ program: Program, on input: ModuleJSONValue, limits: Limits,
                    budget: inout ModuleRequestBudget) -> RunOutcome {
        run(program, on: input, limits: limits, budget: &budget, log: { line in
            logger.notice("\(line, privacy: .public)")
        })
    }

    static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Clash", category: "jq")

     
     
    static let logLineBytes = 16 << 10

     
    struct Trace {
        enum Ending: Equatable {
            case finished
             
            case error(String)
            case stopped(String)
            case halted
        }

        var outputs: [ModuleJSONValue] = []
        var ending: Ending = .finished
        var steps = 0
         
         
        var stoppedByBackstop = false
         
         
        var stoppedByBudget = false
         
        var ledgerBytes = 0
    }

    static func trace(_ program: Program, on input: ModuleJSONValue, limits: Limits, budget: inout ModuleRequestBudget,
                      maximumOutputs: Int = .max, log: (String) -> Void = { _ in }) -> Trace {
        var trace = Trace()
        if budget.isSpent {
            trace.ending = .stopped("the request's CPU budget is spent")
            trace.stoppedByBudget = true
            return trace
        }
        let ledger = ModuleJSONLedger()
        let previous = ModuleJSONLedger.begin(ledger)
        defer { ModuleJSONLedger.end(restoring: previous) }
        withoutActuallyEscaping(log) { log in
            let machine = ModuleJQMachine(limits: limits, budget: budget, ledger: ledger, log: log)
            do {
                try machine.eval(program.root, input, nil, nil) { value, _ in
                    trace.outputs.append(value)
                    if trace.outputs.count >= maximumOutputs { throw ModuleJQThrow.halt(nil) }
                }
            } catch let thrown as ModuleJQThrow {
                trace.ending = Self.ending(thrown, outputs: trace.outputs.count, maximum: maximumOutputs)
            } catch {
                trace.ending = .error("\(error)")
            }
            budget = machine.settle()
            trace.steps = machine.stepsTaken
            trace.stoppedByBackstop = machine.stoppedByBackstop
            trace.stoppedByBudget = machine.stoppedByBudget
            trace.ledgerBytes = machine.ledgerPeak
        }
        return trace
    }

    private static func ending(_ thrown: ModuleJQThrow, outputs: Int, maximum: Int) -> Trace.Ending {
        switch thrown {
        case .raised(let value):
            return .error(message(value))
        case .breakLabel:
            return .error("break")
        case .downstream(let inner, _):
            return ending(inner, outputs: outputs, maximum: maximum)
        case .halt(let value):
            if let value { return .error(message(value)) }
            return outputs >= maximum ? .finished : .halted
        case .stop(let why):
            return .stopped(why)
        }
    }

     
     
    static func message(_ value: ModuleJSONValue) -> String {
        if case .string(let text) = value {
            guard text.utf8.count > logLineBytes else { return text }
            return String(decoding: text.utf8.prefix(logLineBytes - 3), as: UTF8.self) + "..."
        }
        return "\(ModuleJQMachine.logText(value)) (not a string)"
    }
}

 
 
 
enum ModuleJQStack {
     
     
     
     
    static let runReserve: UInt = 128 << 10
     
    static let readReserve: UInt = 128 << 10

     
     
    static func floor(reserve: UInt) -> UInt {
        let thread = pthread_self()
        let top = UInt(bitPattern: pthread_get_stackaddr_np(thread))
        let size = UInt(pthread_get_stacksize_np(thread))
        return size > reserve * 2 ? top - size + reserve : top - size / 2
    }

    @inline(__always)
    static func address() -> UInt {
        var marker: UInt8 = 0
        return withUnsafeMutablePointer(to: &marker) { UInt(bitPattern: $0) }
    }
}
#endif
