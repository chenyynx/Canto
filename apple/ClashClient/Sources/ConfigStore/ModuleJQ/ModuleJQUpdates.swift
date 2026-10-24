#if os(iOS) || os(macOS)
import Foundation

 
 

extension ModuleJQMachine {
     

     
    func paths(_ node: ModuleJQNode, _ input: Value, _ env: ModuleJQEnvironment?,
               _ body: (ModuleJQPath) throws -> Void) throws {
        try eval(node, input, ModuleJQPath(root: input), env) { value, at in
            guard let at, Self.identical(value, at.value) else {
                throw self.fail("Invalid path expression with result \(Self.dump(value, 30))")
            }
            try body(at)
        }
    }

     

    func update(_ operation: ModuleJQUpdateOperator, _ left: ModuleJQNode, _ right: ModuleJQNode, _ input: Value,
                        _ path: ModuleJQPath?, _ env: ModuleJQEnvironment?, _ emit: Emit) throws {
        switch operation {
        case .assign:
             
            let constant = Self.constantPath(left)
            try eval(right, input, nil, env) { value, _ in
                var result = input
                if let constant {
                    try self.setPath(&result, constant[...], value)
                    return try emit(result, path)
                }
                try self.paths(left, input, env) { at in
                    try self.setPath(&result, try self.components(at)[...], value)
                }
                try emit(result, path)
            }
        case .modify:
            try modify(left, input, env, { value, done in
                 
                 
                 
                 
                 
                let label = self.newLabel()
                if right.isSingle { return try done(try self.single(right, value, env)) }
                var first: Value?
                do {
                    try self.eval(right, value, nil, env) { output, _ in
                        if first != nil { throw ModuleJQThrow.breakLabel(label) }
                        first = output
                    }
                } catch {
                    if first == nil { throw error }
                }
                if let first { try done(first) }
            }, { try emit($0, path) })
        case .arithmetic(let operation):
             
            try eval(right, input, nil, env) { operand, _ in
                try self.modify(left, input, env, { value, done in
                    _ = self.newLabel()
                    try done(try self.binary(operation, value, operand))
                }, { try emit($0, path) })
            }
        case .alternative:
            try eval(right, input, nil, env) { fallback, _ in
                try self.modify(left, input, env, { value, done in
                    _ = self.newLabel()
                    try done(value.isTruthy ? value : fallback)
                }, { try emit($0, path) })
            }
        }
    }

     
    static func constantPath(_ node: ModuleJQNode) -> [Value]? {
        switch node {
        case .scalar(let inner):
            return constantPath(inner)
        case .identity:
            return []
        case .field(let target, let name, optional: false):
            return constantPath(target).map { $0 + [.string(name)] }
        case .index(let target, .literal(let key), optional: false), .index(let target, .scalar(.literal(let key)), optional: false):
            switch key {
            case .string, .number: return constantPath(target).map { $0 + [key] }
            default: return nil
            }
        default:
            return nil
        }
    }

     
     
     
    func modify(_ left: ModuleJQNode, _ input: Value, _ env: ModuleJQEnvironment?,
                _ update: (Value, (Value) throws -> Void) throws -> Void, _ emit: (Value) throws -> Void) throws {
         
         
         
        if let path = Self.constantPath(left) {
            var result = input
            let current = try getPath(result, path[...])
            var replacement: Value?
            try update(current) { replacement = $0 }
            if let replacement {
                try setPath(&result, path[...], replacement)
            } else {
                result = try deletePaths(result, [.array(ModuleJSONArray(path))])
            }
            return try emit(result)
        }
        if case .iterate(.identity, optional: false) = left {
            var result = input
            var deleted: [Value] = []
            switch input {
            case .array(let array):
                for index in 0..<array.count {
                    try tick()
                    var replacement: Value?
                    try update(array[index]) { replacement = $0 }
                    if let replacement {
                        try setIndex(&result, .number(Double(index)), replacement)
                    } else {
                        try self.beforeAppend(to: deleted)
                        deleted.append(.number(Double(index)))
                    }
                }
            case .object(let object):
                let keys = object.keys, values = object.values
                for position in keys.indices {
                    try tick()
                    var replacement: Value?
                    try update(values[position]) { replacement = $0 }
                    if let replacement {
                        try setIndex(&result, .string(keys[position]), replacement)
                    } else {
                        try self.beforeAppend(to: deleted)
                        deleted.append(.string(keys[position]))
                    }
                }
            default:
                throw fail("Cannot iterate over \(input.typeName) (\(Self.dump(input)))")
            }
            if !deleted.isEmpty { result = try deletePaths(result, deleted.map { .array(ModuleJSONArray([$0])) }) }
            return try emit(result)
        }
        var result = input
        var deletions: [Value] = []
        try paths(left, input, env) { at in
            let components = try self.components(at)
            let current = try self.getPath(result, components[...])
            var replacement: Value?
            try update(current) { replacement = $0 }
            if let replacement {
                try self.setPath(&result, components[...], replacement)
            } else {
                try self.beforeAppend(to: deletions)
                deletions.append(.array(ModuleJSONArray(components)))
            }
        }
        if !deletions.isEmpty { result = try deletePaths(result, deletions) }
        try emit(result)
    }
}
#endif
