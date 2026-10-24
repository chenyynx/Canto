#if os(iOS) || os(macOS)
import Foundation

 
 
 
 
 
 
 
 
 
 
 
 

extension ModuleJQMachine {
    @inline(never)
    func evalField(_ target: ModuleJQNode, _ name: String, _ optional: Bool, _ input: Value, _ path: At, _ env: Env,
                           _ emit: Emit) throws {
        if path == nil, target.isSingle { return try indexed(try single(target, input, env), .string(name), nil, optional, emit) }
        try eval(target, input, path, env) { value, at in
            try self.indexed(value, .string(name), at, optional, emit)
        }
    }

    @inline(never)
    func evalIndex(_ target: ModuleJQNode, _ keyNode: ModuleJQNode, _ optional: Bool, _ input: Value, _ path: At,
                           _ env: Env, _ emit: Emit) throws {
        if keyNode.isSingle {
            let key = try single(keyNode, input, env)
            if path == nil, target.isSingle { return try indexed(try single(target, input, env), key, nil, optional, emit) }
            return try eval(target, input, path, env) { value, at in
                try self.indexed(value, key, at, optional, emit)
            }
        }
        try eval(keyNode, input, nil, env) { key, _ in
            try self.eval(target, input, path, env) { value, at in
                try self.indexed(value, key, at, optional, emit)
            }
        }
    }

    @inline(never)
    func evalSlice(_ target: ModuleJQNode, _ fromNode: ModuleJQNode?, _ toNode: ModuleJQNode?, _ optional: Bool,
                           _ input: Value, _ path: At, _ env: Env, _ emit: Emit) throws {
        try optionalValues(fromNode, input, env) { from in
            try self.optionalValues(toNode, input, env) { to in
                let key = Value.object(ModuleJSONObject(uniqueKeys: ["start", "end"], values: [from, to]))
                try self.eval(target, input, path, env) { value, at in
                    try self.indexed(value, key, at, optional, emit)
                }
            }
        }
    }

    @inline(never)
    func evalIterate(_ target: ModuleJQNode, _ optional: Bool, _ input: Value, _ path: At, _ env: Env,
                             _ emit: Emit) throws {
        try eval(target, input, path, env) { value, at in
            try self.iterate(value, at, optional, emit)
        }
    }

    @inline(never)
     
     
     
    func evalString(_ parts: [ModuleJQCompiledPart], _ format: String?, _ input: Value, _ path: At, _ env: Env,
                    _ emit: Emit) throws {
        var pieces = [String](repeating: "", count: parts.count)
         
        var held = [UInt](repeating: 0, count: parts.count)
        defer { for key in held { release(key) } }
        func piece(_ value: Value, _ index: Int) throws {
            let text: String
            if let format { text = try applyFormat(format, value) } else { text = try tostring(value) }
            release(held[index])
            held[index] = 0
            pieces[index] = text
            held[index] = try hold(.string(text))
        }
        func build(_ from: Int) throws {
            var index = from
            while index >= 0 {
                switch parts[index] {
                case .text(let text):
                    pieces[index] = text
                case .interpolation(let inner) where inner.isSingle:
                    try piece(try single(inner, input, env), index)
                case .interpolation(let inner):
                    let at = index
                    return try eval(inner, input, nil, env) { value, _ in
                        try piece(value, at)
                        try build(at - 1)
                    }
                }
                index -= 1
            }
            var length = 0
            for piece in pieces { length &+= piece.utf8.count }
            try produce(length)
            try charge(length >> 6)
            var text = ""
            text.reserveCapacity(length)
            for piece in pieces { text += piece }
            try emit(.string(text), path)
        }
        try build(parts.count - 1)
    }

    @inline(never)
    func evalCollect(_ inner: ModuleJQNode, _ input: Value, _ path: At, _ env: Env, _ emit: Emit) throws {
        var gathered = ModuleJQGathered()
        try eval(inner, input, nil, env) { value, _ in try gathered.append(value, self) }
        let array = try gathered.array(self)
        try checkMemory()
        try emit(array, path)
    }

    @inline(never)
    func evalObject(_ entries: [ModuleJQCompiledEntry], _ input: Value, _ path: At, _ env: Env, _ emit: Emit) throws {
        try buildObject(entries, 0, ModuleJSONObject(), input, env) { object in
            try emit(Value.object(object), path)
        }
    }

    @inline(never)
    func evalNegate(_ inner: ModuleJQNode, _ input: Value, _ path: At, _ env: Env, _ emit: Emit) throws {
        try eval(inner, input, nil, env) { value, _ in
            guard case .number(let number) = value else { throw self.typeError(value, "cannot be negated") }
            try emit(.number(-number.value), path)
        }
    }

     
     
    @inline(never)
    func evalPipe(_ stages: [ModuleJQNode], _ from: Int, _ input: Value, _ path: At, _ env: Env,
                          _ emit: Emit) throws {
        var value = input
        var index = from
        if path == nil {
            while index < stages.count - 1, stages[index].isSingle {
                value = try single(stages[index], value, env)
                index += 1
            }
        }
        if index == stages.count - 1 { return try eval(stages[index], value, path, env, emit) }
        try eval(stages[index], value, path, env) { output, at in
            try self.evalPipe(stages, index + 1, output, at, env, emit)
        }
    }

    @inline(never)
    func evalBinary(_ operation: ModuleJQBinaryOperator, _ left: ModuleJQNode, _ right: ModuleJQNode, _ input: Value,
                            _ path: At, _ env: Env, _ emit: Emit) throws {
        if right.isSingle {
            let b = try single(right, input, env)
            if left.isSingle { return try emit(try binary(operation, try single(left, input, env), b), path) }
             
            let held = try hold(b)
            defer { release(held) }
            return try eval(left, input, nil, env) { a, _ in try emit(try self.binary(operation, a, b), path) }
        }
        try eval(right, input, nil, env) { b, _ in
            let held = try self.hold(b)
            defer { self.release(held) }
            try self.eval(left, input, nil, env) { a, _ in
                try emit(try self.binary(operation, a, b), path)
            }
        }
    }

    @inline(never)
    func evalAnd(_ left: ModuleJQNode, _ right: ModuleJQNode, _ input: Value, _ path: At, _ env: Env,
                         _ emit: Emit) throws {
        if left.isSingle {
            guard try single(left, input, env).isTruthy else { return try emit(.bool(false), path) }
            return try eval(right, input, nil, env) { b, _ in try emit(.bool(b.isTruthy), path) }
        }
        try eval(left, input, nil, env) { a, _ in
            guard a.isTruthy else { return try emit(.bool(false), path) }
            try self.eval(right, input, nil, env) { b, _ in try emit(.bool(b.isTruthy), path) }
        }
    }

    @inline(never)
    func evalOr(_ left: ModuleJQNode, _ right: ModuleJQNode, _ input: Value, _ path: At, _ env: Env,
                        _ emit: Emit) throws {
        if left.isSingle {
            if try single(left, input, env).isTruthy { return try emit(.bool(true), path) }
            return try eval(right, input, nil, env) { b, _ in try emit(.bool(b.isTruthy), path) }
        }
        try eval(left, input, nil, env) { a, _ in
            if a.isTruthy { return try emit(.bool(true), path) }
            try self.eval(right, input, nil, env) { b, _ in try emit(.bool(b.isTruthy), path) }
        }
    }

    @inline(never)
    func evalAlternative(_ left: ModuleJQNode, _ right: ModuleJQNode, _ input: Value, _ path: At, _ env: Env,
                                 _ emit: Emit) throws {
        var found = false
        try eval(left, input, path, env) { value, at in
            if value.isTruthy {
                found = true
                try emit(value, at)
            }
        }
        if !found { try eval(right, input, path, env, emit) }
    }

    @inline(never)
     
     
    func evalConditional(_ branches: [ModuleJQBranch], _ from: Int, _ otherwise: ModuleJQNode?, _ input: Value,
                         _ path: At, _ env: Env, _ emit: Emit) throws {
        var index = from
        while index < branches.count, branches[index].condition.isSingle {
            if try single(branches[index].condition, input, env).isTruthy { return try eval(branches[index].then, input, path, env, emit) }
            index += 1
        }
        guard index < branches.count else {
            if let otherwise { return try eval(otherwise, input, path, env, emit) }
            return try emit(input, path)
        }
        let at = index
        try eval(branches[at].condition, input, nil, env) { verdict, _ in
            if verdict.isTruthy {
                try self.eval(branches[at].then, input, path, env, emit)
            } else {
                try self.evalConditional(branches, at + 1, otherwise, input, path, env, emit)
            }
        }
    }

    @inline(never)
    func evalTry(_ body: ModuleJQNode, _ handler: ModuleJQNode?, _ input: Value, _ path: At, _ env: Env,
                         _ emit: Emit) throws {
        let owner = token()
        do {
            try eval(body, input, path, env) { value, at in
                do {
                    try emit(value, at)
                } catch let thrown as ModuleJQThrow {
                    switch thrown {
                    case .raised, .breakLabel: throw ModuleJQThrow.downstream(thrown, owner: owner)
                    default: throw thrown
                    }
                }
            }
        } catch let thrown as ModuleJQThrow {
            switch thrown {
            case .downstream(let inner, let by) where by == owner:
                throw inner
            case .raised(let message):
                if let handler { try eval(handler, message, path, env, emit) }
            case .breakLabel(let label):
                if let handler {
                    let value = Value.object(ModuleJSONObject(uniqueKeys: ["__jq"], values: [.number(Double(label))]))
                    try eval(handler, value, path, env, emit)
                }
            default:
                throw thrown
            }
        }
    }

    @inline(never)
    func evalReduce(_ source: ModuleJQNode, _ patterns: ModuleJQPatterns, _ initial: ModuleJQNode, _ update: ModuleJQNode,
                            _ input: Value, _ path: At, _ env: Env, _ emit: Emit) throws {
         
         
        var sourceInput: Value? = input
        try eval(initial, input, path, env) { start, startPath in
            var state: Value? = start
             
            var held = try self.hold(start)
            defer { self.release(held) }
            let from = sourceInput ?? .null
            sourceInput = nil
            try self.eval(source, from, path, env) { item, itemPath in
                try self.destructure(patterns, item, env) { bound in
                    let current = state ?? .null
                    state = nil
                    try self.eval(update, current, itemPath, bound) { next, _ in
                        self.release(held)
                        held = 0
                        state = next
                        held = try self.hold(next)
                    }
                    if state == nil {
                        self.release(held)
                        held = 0
                    }
                }
            }
            try emit(state ?? .null, startPath)
        }
    }

    @inline(never)
    func evalForeach(_ source: ModuleJQNode, _ patterns: ModuleJQPatterns, _ initial: ModuleJQNode,
                             _ update: ModuleJQNode, _ extract: ModuleJQNode?, _ input: Value, _ path: At, _ env: Env,
                             _ emit: Emit) throws {
        var sourceInput: Value? = input
        try eval(initial, input, path, env) { start, _ in
            var state: Value? = start
             
            var held = try self.hold(start)
            defer { self.release(held) }
            let from = sourceInput ?? .null
            sourceInput = nil
            try self.eval(source, from, path, env) { item, itemPath in
                try self.destructure(patterns, item, env) { bound in
                    let current = state ?? .null
                    state = nil
                    try self.eval(update, current, itemPath, bound) { next, nextPath in
                        self.release(held)
                        held = 0
                        state = next
                        held = try self.hold(next)
                        if let extract {
                            try self.eval(extract, next, nextPath, bound, emit)
                        } else {
                            try emit(next, nextPath)
                        }
                    }
                    if state == nil {
                        self.release(held)
                        held = 0
                    }
                }
            }
        }
    }

    @inline(never)
    func evalCallUser(_ hops: Int, _ arguments: [ModuleJQNode], _ input: Value, _ path: At, _ env: Env,
                              _ emit: Emit) throws {
        let defining = ModuleJQEnvironment.up(env, hops)
        guard case .function(let function) = defining.entry else { preconditionFailure("a call resolved to a function") }
        try call(function, arguments, defining, input, path, env, emit)
    }

    @inline(never)
    func evalCallParameter(_ hops: Int, _ input: Value, _ path: At, _ env: Env, _ emit: Emit) throws {
        let holder = ModuleJQEnvironment.up(env, hops)
        guard case .closure(let body, let closureEnv) = holder.entry else { preconditionFailure("a parameter resolved to a closure") }
         
        try guardStack()
        try eval(body, input, path, closureEnv, emit)
    }

    @inline(never)
    func evalBind(_ source: ModuleJQNode, _ patterns: ModuleJQPatterns, _ body: ModuleJQNode, _ input: Value,
                          _ path: At, _ env: Env, _ emit: Emit) throws {
        if source.isSingle {
            return try destructure(patterns, try single(source, input, env), env) { bound in
                try self.eval(body, input, path, bound, emit)
            }
        }
        try eval(source, input, nil, env) { value, _ in
            try self.destructure(patterns, value, env) { bound in
                try self.eval(body, input, path, bound, emit)
            }
        }
    }

    @inline(never)
    func evalLabel(_ body: ModuleJQNode, _ input: Value, _ path: At, _ env: Env, _ emit: Emit) throws {
        let label = newLabel()
        do {
            try eval(body, input, path, ModuleJQEnvironment(env, .label(label)), emit)
        } catch ModuleJQThrow.breakLabel(let target) where target == label {
            return
        }
    }

     
    func recurseAll(_ value: Value, _ at: ModuleJQPath?, _ emit: Emit) throws {
        try tick()
        try emit(value, at)
        switch value {
        case .array(let array):
            try enter()
            defer { leave() }
            for (index, item) in array.items.enumerated() {
                try recurseAll(item, at.map { ModuleJQPath($0, .number(Double(index)), item) }, emit)
            }
        case .object(let object):
            try enter()
            defer { leave() }
            let keys = object.keys, values = object.values
            for position in keys.indices {
                try recurseAll(values[position], at.map { ModuleJQPath($0, .string(keys[position]), values[position]) }, emit)
            }
        default:
            break
        }
    }

     
    func optionalValues(_ node: ModuleJQNode?, _ input: Value, _ env: ModuleJQEnvironment?,
                                _ body: (Value) throws -> Void) throws {
        guard let node else { return try body(.null) }
        try eval(node, input, nil, env) { value, _ in try body(value) }
    }

     
    func closure(_ argument: ModuleJQNode, _ env: ModuleJQEnvironment?) -> ModuleJQEnvironment.Entry {
        if case .callParameter(let hops) = argument,
           case .closure(let body, let closureEnv) = ModuleJQEnvironment.up(env, hops).entry {
            return .closure(body, closureEnv)
        }
        return .closure(argument, env)
    }

    func call(_ function: ModuleJQFunction, _ arguments: [ModuleJQNode], _ defining: ModuleJQEnvironment?,
              _ input: Value, _ path: ModuleJQPath?, _ env: ModuleJQEnvironment?, _ emit: Emit) throws {
        try enter()
        defer { leave() }
        var inner = defining
        for argument in arguments { inner = ModuleJQEnvironment(inner, closure(argument, env)) }
        let valued = function.valued
        if valued.isEmpty { return try eval(function.body, input, path, inner, emit) }
         
         
         
        func bindValue(_ from: Int, _ outer: ModuleJQEnvironment?) throws {
            var next = from
            var scope = outer
            while next < valued.count, arguments[valued[next]].isSingle {
                scope = ModuleJQEnvironment(scope, .value(try single(arguments[valued[next]], input, env)))
                next += 1
            }
            if next == valued.count { return try eval(function.body, input, path, scope, emit) }
            let at = next, bound = scope
            try eval(arguments[valued[at]], input, nil, env) { value, _ in
                try bindValue(at + 1, ModuleJQEnvironment(bound, .value(value)))
            }
        }
        try bindValue(0, inner)
    }

     

    func indexed(_ value: Value, _ key: Value, _ at: ModuleJQPath?, _ optional: Bool, _ emit: Emit) throws {
        if let at, !Self.identical(value, at.value) {
            throw fail("Invalid path expression near attempt to access element \(Self.dump(key)) of \(Self.dump(value, 30))")
        }
        let result: Value
        if optional {
             
            guard Self.indexes(value, key) else { return }
            do {
                result = try index(value, key)
            } catch ModuleJQThrow.raised {
                return
            }
        } else {
            result = try index(value, key)
        }
        try emit(result, at.map { ModuleJQPath($0, key, result) })
    }

     
    static func indexes(_ value: Value, _ key: Value) -> Bool {
        switch (value, key) {
        case (.object, .string), (.array, .number), (.array, .object), (.array, .array), (.string, .object),
             (.null, .string), (.null, .number), (.null, .object):
            return true
        default:
            return false
        }
    }

    func iterate(_ value: Value, _ at: ModuleJQPath?, _ optional: Bool = false, _ emit: Emit) throws {
        if let at, !Self.identical(value, at.value) {
            throw fail("Invalid path expression near attempt to iterate through \(Self.dump(value, 30))")
        }
        switch value {
        case .array(let array):
            for (index, item) in array.items.enumerated() {
                try emit(item, at.map { ModuleJQPath($0, .number(Double(index)), item) })
            }
        case .object(let object):
            let keys = object.keys, values = object.values
            for position in keys.indices {
                try emit(values[position], at.map { ModuleJQPath($0, .string(keys[position]), values[position]) })
            }
        default:
            if optional { return }
            throw fail("Cannot iterate over \(value.typeName) (\(Self.dump(value)))")
        }
    }

     

     
     
     
    func buildObject(_ entries: [ModuleJQCompiledEntry], _ from: Int, _ start: ModuleJSONObject, _ input: Value,
                     _ env: ModuleJQEnvironment?, _ done: (ModuleJSONObject) throws -> Void) throws {
        var index = from
        var partial = start
        while index < entries.count {
            switch entries[index] {
            case .pair(let keyNode, let valueNode) where keyNode.isSingle && valueNode.isSingle:
                let key = try single(keyNode, input, env)
                guard case .string(let name) = key else { throw fail("Cannot use \(key.typeName) (\(Self.dump(key))) as object key") }
                let value = try single(valueNode, input, env)
                try checkDepth(building: value.depth + 1)
                partial.set(name, value)
            case .keyOnly(let keyNode) where keyNode.isSingle:
                let key = try single(keyNode, input, env)
                guard case .string(let name) = key else { throw fail("Cannot use \(key.typeName) (\(Self.dump(key))) as object key") }
                let value = try self.index(input, key)
                try checkDepth(building: value.depth + 1)
                partial.set(name, value)
            default:
                return try buildEntry(entries, index, partial, input, env, done)
            }
            index += 1
        }
        try done(partial)
    }

     
    private func buildEntry(_ entries: [ModuleJQCompiledEntry], _ index: Int, _ partial: ModuleJSONObject, _ input: Value,
                            _ env: ModuleJQEnvironment?, _ done: (ModuleJSONObject) throws -> Void) throws {
        switch entries[index] {
        case .pair(let keyNode, let valueNode):
            try eval(keyNode, input, nil, env) { key, _ in
                guard case .string(let name) = key else { throw self.fail("Cannot use \(key.typeName) (\(Self.dump(key))) as object key") }
                try self.eval(valueNode, input, nil, env) { value, _ in
                    try self.checkDepth(building: value.depth + 1)
                    var next = partial
                    next.set(name, value)
                    try self.buildObject(entries, index + 1, next, input, env, done)
                }
            }
        case .keyOnly(let keyNode):
            try eval(keyNode, input, nil, env) { key, _ in
                guard case .string(let name) = key else { throw self.fail("Cannot use \(key.typeName) (\(Self.dump(key))) as object key") }
                let value = try self.index(input, key)
                try self.checkDepth(building: value.depth + 1)
                var next = partial
                next.set(name, value)
                try self.buildObject(entries, index + 1, next, input, env, done)
            }
        }
    }

}
#endif
