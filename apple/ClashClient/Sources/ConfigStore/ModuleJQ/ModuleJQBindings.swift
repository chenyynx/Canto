#if os(iOS) || os(macOS)
import Foundation

 

extension ModuleJQMachine {
     

     
    final class Slots {
        var values: [Value]

        init(_ count: Int) {
            values = [Value](repeating: .null, count: count)
        }
    }

     
     
     
     
    func destructure(_ patterns: ModuleJQPatterns, _ value: Value, _ env: ModuleJQEnvironment?,
                     _ body: (ModuleJQEnvironment?) throws -> Void) throws {
        if patterns.variableCount == 1, patterns.alternatives.count == 1, case .variable = patterns.alternatives[0] {
            return try body(ModuleJQEnvironment(env, .value(value)))
        }
        for (number, alternative) in patterns.alternatives.enumerated() {
            let last = number == patterns.alternatives.count - 1
            do {
                let slots = Slots(patterns.variableCount)
                try bindings(alternative, value, env, slots) {
                    var bound = env
                    for slot in slots.values { bound = ModuleJQEnvironment(bound, .value(slot)) }
                    try body(bound)
                }
                return
            } catch let thrown as ModuleJQThrow {
                switch thrown {
                case .stop, .halt: throw thrown
                default: if last { throw thrown }
                }
            }
        }
    }

     
    enum PendingBinding {
        case bind(ModuleJQPatternNode, Value)
        case elements([ModuleJQPatternNode], next: Int, of: Value)
        case entries([(key: ModuleJQPatternKey, pattern: ModuleJQPatternNode?)], next: Int, of: Value)
    }

     
     
     
     
     
    func bindings(_ pattern: ModuleJQPatternNode, _ value: Value, _ env: ModuleJQEnvironment?, _ slots: Slots,
                  _ done: () throws -> Void) throws {
        try bind([.bind(pattern, value)], env, slots, done)
    }

    private func bind(_ start: [PendingBinding], _ env: ModuleJQEnvironment?, _ slots: Slots, _ done: () throws -> Void) throws {
        var work = start
        while let next = work.popLast() {
            switch next {
            case .bind(let pattern, let value):
                switch pattern {
                case .variable(let slot): slots.values[slot] = value
                case .array(let items): work.append(.elements(items, next: 0, of: value))
                case .object(let entries): work.append(.entries(entries, next: 0, of: value))
                }
            case .elements(let items, let index, let value):
                guard index < items.count else { continue }
                try tick()
                let element = try self.index(value, .number(Double(index)))
                work.append(.elements(items, next: index + 1, of: value))
                work.append(.bind(items[index], element))
            case .entries(let entries, let index, let value):
                guard index < entries.count else { continue }
                try tick()
                let entry = entries[index]
                work.append(.entries(entries, next: index + 1, of: value))
                switch entry.key {
                case .variable(let name, let slot):
                    let element = try self.index(value, .string(name))
                    slots.values[slot] = element
                    if let inner = entry.pattern { work.append(.bind(inner, element)) }
                case .expression(let keyNode) where keyNode.isSingle:
                    let key = try single(keyNode, value, env)
                    guard case .string = key else { throw fail("Cannot index \(value.typeName) with \(key.typeName)") }
                    work.append(.bind(entry.pattern!, try self.index(value, key)))
                case .expression(let keyNode):
                    let saved = slots.values
                    let rest = work
                    return try eval(keyNode, value, nil, env) { key, _ in
                        guard case .string = key else { throw self.fail("Cannot index \(value.typeName) with \(key.typeName)") }
                        let element = try self.index(value, key)
                        slots.values = saved
                        try self.bind(rest + [.bind(entry.pattern!, element)], env, slots, done)
                    }
                }
            }
        }
        try done()
    }

}
#endif
