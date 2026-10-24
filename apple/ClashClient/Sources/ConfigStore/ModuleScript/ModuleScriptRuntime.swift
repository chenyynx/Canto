#if os(iOS) || os(macOS)
import Foundation
import JavaScriptCore

 
 
 
 
 
 
 
final class ModuleScriptThread: @unchecked Sendable {
     
     
    static let stackSize = 1 << 20

     
     
    private final class Mailbox: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [() -> Void] = []
        private var closed = false
        private let available = DispatchSemaphore(value: 0)
        private var thread: Thread?

        func put(_ item: @escaping () -> Void) {
            lock.lock()
            defer { lock.unlock() }
            guard !closed else { return }
            items.append(item)
            available.signal()
        }

        func close() {
            lock.lock()
            closed = true
            lock.unlock()
            available.signal()
        }

         
        func take() -> (() -> Void)? {
            while true {
                available.wait()
                lock.lock()
                if !items.isEmpty {
                    let item = items.removeFirst()
                    lock.unlock()
                    return item
                }
                let done = closed
                lock.unlock()
                if done { return nil }
            }
        }

        func mark(_ current: Thread) {
            lock.lock()
            thread = current
            lock.unlock()
        }

        var isCurrent: Bool {
            lock.lock()
            defer { lock.unlock() }
            return thread === Thread.current
        }
    }

    private let mailbox = Mailbox()
    private let timers: DispatchQueue

    init(name: String) {
        timers = DispatchQueue(label: name + #".timers"#)
        let mailbox = self.mailbox
        let thread = Thread {
            mailbox.mark(Thread.current)
            while let item = mailbox.take() { autoreleasepool { item() } }
        }
        thread.name = name
        thread.stackSize = Self.stackSize
        thread.qualityOfService = .utility
        thread.start()
    }

    deinit { mailbox.close() }

    var isCurrent: Bool { mailbox.isCurrent }

    func async(_ work: @escaping () -> Void) {
        mailbox.put(work)
    }

    func asyncAfter(deadline: UInt64, _ work: @escaping () -> Void) {
        let mailbox = self.mailbox
        timers.asyncAfter(deadline: DispatchTime(uptimeNanoseconds: deadline)) { mailbox.put(work) }
    }
}

 
 
 
final class ModuleScriptFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var raised = false

    func raise() {
        lock.lock()
        raised = true
        lock.unlock()
    }

    var isRaised: Bool {
        lock.lock()
        defer { lock.unlock() }
        return raised
    }
}

 
 
 
final class ModuleScriptSliceMonitor: @unchecked Sendable {
    private let lock = NSLock()
    private var current: (run: UUID, since: UInt64)?

    func begin(_ run: UUID, at time: UInt64) {
        lock.lock()
        current = (run, time)
        lock.unlock()
    }

    func end() {
        lock.lock()
        current = nil
        lock.unlock()
    }

    func isInside(_ run: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return current?.run == run
    }
}

 
 
final class ModuleScriptRuntime {
    enum Failure: Error, Equatable, CustomStringConvertible {
        case noVirtualMachine
        case noContext
        case selfTestFailed(String)

        var description: String {
            switch self {
            case .noVirtualMachine: return #"JavaScriptCore made no virtual machine"#
            case .noContext: return #"JavaScriptCore made no context"#
            case .selfTestFailed(let detail): return #"JavaScriptCore failed its self-test: \#(detail)"#
            }
        }
    }

    let virtualMachine: JSVirtualMachine

    init(makeVirtualMachine: () -> JSVirtualMachine?) throws {
        guard let virtualMachine = makeVirtualMachine() else { throw Failure.noVirtualMachine }
        guard let probe = JSContext(virtualMachine: virtualMachine) else { throw Failure.noContext }
        probe.exceptionHandler = { _, _ in }
        guard let sum = probe.evaluateScript(#"1 + 1"#), sum.isNumber, sum.toInt32() == 2 else {
            throw Failure.selfTestFailed(probe.exception?.toString() ?? #"1 + 1 did not make 2"#)
        }
        self.virtualMachine = virtualMachine
    }

    func makeContext() -> JSContext? {
        JSContext(virtualMachine: virtualMachine)
    }
}
#endif
