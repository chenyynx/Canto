#if os(iOS) || os(macOS)
import Foundation

 
 

extension ModuleJQMachine {
     
     
    func values(_ arguments: [ModuleJQNode], _ input: Value, _ env: ModuleJQEnvironment?,
                _ body: ([Value]) throws -> Void) throws {
        if arguments.allSatisfy(\.isSingle) {
            var current = [Value](repeating: .null, count: arguments.count)
            for index in arguments.indices.reversed() { current[index] = try single(arguments[index], input, env) }
            return try body(current)
        }
        switch arguments.count {
        case 0:
            try body([])
        case 1:
            try eval(arguments[0], input, nil, env) { a, _ in try body([a]) }
        default:
            var current = [Value](repeating: .null, count: arguments.count)
            func level(_ index: Int) throws {
                if index < 0 { return try body(current) }
                try eval(arguments[index], input, nil, env) { value, _ in
                    current[index] = value
                    try level(index - 1)
                }
            }
            try level(arguments.count - 1)
        }
    }

    func callNative(_ native: ModuleJQNative, _ arguments: [ModuleJQNode], _ input: Value, _ path: ModuleJQPath?,
                    _ env: ModuleJQEnvironment?, _ emit: Emit) throws {
        switch native {
        case .empty:
            return
        case .not:
            try emit(.bool(!input.isTruthy), path)
        case .path:
            try paths(arguments[0], input, env) { at in
                try emit(.array(ModuleJSONArray(try self.components(at))), path)
            }
        case .getpath:
            try values(arguments, input, env) { arguments in
                let result = try self.getPathValue(input, arguments[0])
                if let path {
                    guard Self.identical(input, path.value) else {
                        throw self.fail("Invalid path expression with result \(Self.dump(input, 30))")
                    }
                    if case .array(let components) = arguments[0] {
                        try self.reserve(components.count * ModuleJQPath.bytes)
                        try emit(result, path.appending(components.items, value: result))
                    } else {
                        try emit(result, path)
                    }
                } else {
                    try emit(result, nil)
                }
            }
        case .setpath:
            try values(arguments, input, env) { arguments in
                guard case .array(let components) = arguments[0] else { throw self.fail("Path must be specified as an array") }
                var result = input
                try self.setPath(&result, components.items[...], arguments[1])
                try emit(result, path)
            }
        case .delpaths:
            try values(arguments, input, env) { arguments in
                guard case .array(let list) = arguments[0] else { throw self.fail("Paths must be specified as an array") }
                try emit(try self.deletePaths(input, list.items), path)
            }
        case .has:
            try values(arguments, input, env) { arguments in try emit(.bool(try self.has(input, arguments[0])), path) }
        case .contains:
            try values(arguments, input, env) { arguments in
                let b = arguments[0]
                guard input.kindRank == b.kindRank else { throw self.typeError(input, b, "cannot have their containment checked") }
                try emit(.bool(try self.contains(input, b)), path)
            }
        case .length:
            try emit(try length(input), path)
        case .utf8bytelength:
            guard case .string(let string) = input else { throw typeError(input, "only strings have UTF-8 byte length") }
            try emit(.number(Double(string.utf8.count)), path)
        case .type:
            try emit(.string(input.typeName), path)
        case .keys, .keysUnsorted:
            switch input {
            case .object(let object):
                try charge(object.count)
                let keys = native == .keys ? object.sortedKeys : object.keys
                try reserve(ModuleJSONLedger.arrayBytes(capacity: keys.count))
                try emit(.array(ModuleJSONArray(keys.map { .string($0) }, childDepth: 0)), path)
            case .array(let array):
                try charge(array.count)
                try emit(.array(ModuleJSONArray((0..<array.count).map { .number(Double($0)) }, childDepth: 0)), path)
            default:
                throw typeError(input, "has no keys")
            }
        case .tojson:
            try emit(.string(try text(input)), path)
        case .fromjson:
            guard case .string(let text) = input else { throw typeError(input, "only strings can be parsed") }
            try emit(try parseJSON(text), path)
        case .tonumber:
            switch input {
            case .number:
                try emit(input, path)
            case .string(let text):
                let parsed = try parseJSON(text)
                guard case .number = parsed else { throw typeError(input, "cannot be parsed as a number") }
                try emit(parsed, path)
            default:
                throw typeError(input, "cannot be parsed as a number")
            }
        case .tostring:
            try emit(.string(try tostring(input)), path)
        case .startswith, .endswith:
            try values(arguments, input, env) { arguments in
                guard case .string(let string) = input, case .string(let affix) = arguments[0] else {
                    throw self.fail(native == .startswith ? "startswith() requires string inputs" : "endswith() requires string inputs")
                }
                try emit(.bool(native == .startswith ? Self.hasPrefix(string, affix) : Self.hasSuffix(string, affix)), path)
            }
        case .ltrimstr, .rtrimstr:
            try values(arguments, input, env) { arguments in
                guard case .string(let string) = input, case .string(let affix) = arguments[0] else { return try emit(input, path) }
                let s = string.utf8, a = affix.utf8.count
                if native == .ltrimstr, Self.hasPrefix(string, affix) {
                    try self.produce(s.count - a)
                    return try emit(.string(String(decoding: s.dropFirst(a), as: UTF8.self)), path)
                }
                if native == .rtrimstr, Self.hasSuffix(string, affix) {
                    try self.produce(s.count - a)
                    return try emit(.string(String(decoding: s.dropLast(a), as: UTF8.self)), path)
                }
                try emit(input, path)
            }
        case .split:
            try values(arguments, input, env) { arguments in
                guard case .string(let string) = input, case .string(let separator) = arguments[0] else {
                    throw self.fail("split input and separator must be strings")
                }
                try emit(try self.split(string, separator), path)
            }
        case .explode:
            guard case .string(let string) = input else { throw fail("explode input must be a string") }
            try reserve(ModuleJSONLedger.arrayBytes(capacity: string.utf8.count))
            try charge(string.utf8.count / 8)
            try emit(.array(ModuleJSONArray(string.unicodeScalars.map { .number(Double($0.value)) }, childDepth: 0)), path)
        case .implode:
            try emit(.string(try implode(input)), path)
        case .strindices:
            try values(arguments, input, env) { arguments in
                guard case .string(let string) = input, case .string(let needle) = arguments[0] else {
                    throw self.fail("_strindices requires string inputs")
                }
                var found: [Value] = []
                try self.occurrences(of: needle, in: string, overlapping: true) { start in
                    try self.tick()
                    try self.beforeAppend(to: found)
                    found.append(.number(Double(start)))
                    return true
                }
                try emit(.array(ModuleJSONArray(found, childDepth: 0)), path)
            }
        case .sort:
            guard case .array(let array) = input else { throw typeError(input, "cannot be sorted, as it is not an array") }
            try emit(.array(ModuleJSONArray(try sorted(array.items, keys: array.items).map { $0.value }, childDepth: array.depth - 1)), path)
        case .sortByImpl, .groupByImpl:
            try values(arguments, input, env) { arguments in
                guard case .array(let items) = input, case .array(let keys) = arguments[0], items.count == keys.count else {
                    throw self.typeError(input, arguments[0], native == .sortByImpl
                                         ? "cannot be sorted, as they are not both arrays" : "cannot be grouped, as they are not both arrays")
                }
                let order = try self.sorted(items.items, keys: keys.items)
                if native == .sortByImpl { return try emit(.array(ModuleJSONArray(order.map { $0.value }, childDepth: items.depth - 1)), path) }
                try self.checkDepth(building: items.depth + 1)
                 
                try self.reserve(ModuleJSONLedger.arrayBytes(capacity: items.count) * 2)
                var groups: [Value] = []
                var group: [Value] = []
                var groupKey: Value?
                for entry in order {
                    if let groupKey, ModuleJSONOrder.compare(groupKey, entry.key) == 0 {
                        group.append(entry.value)
                    } else {
                        if !group.isEmpty { groups.append(.array(ModuleJSONArray(group))) }
                        group = [entry.value]
                        groupKey = entry.key
                    }
                }
                if !group.isEmpty { groups.append(.array(ModuleJSONArray(group))) }
                try emit(.array(ModuleJSONArray(groups)), path)
            }
        case .min, .max:
            try emit(try minimumOrMaximum(input, keys: input, minimum: native == .min), path)
        case .minByImpl, .maxByImpl:
            try values(arguments, input, env) { arguments in
                try emit(try self.minimumOrMaximum(input, keys: arguments[0], minimum: native == .minByImpl), path)
            }
        case .infinite:
            try emit(.number(.infinity), path)
        case .nan:
            try emit(.number(.nan), path)
        case .isinfinite, .isnan, .isnormal:
            guard case .number(let number) = input else { throw typeError(input, "number required") }
            let x = number.value
            try emit(.bool(native == .isinfinite ? x.isInfinite : (native == .isnan ? x.isNaN : x.isNormal)), path)
        case .format:
            try values(arguments, input, env) { arguments in
                guard case .string(let name) = arguments[0] else { throw self.typeError(arguments[0], "is not a valid format") }
                try emit(.string(try self.applyFormat(name, input)), path)
            }
        case .matchImpl:
            try values(arguments, input, env) { arguments in
                try emit(try self.match(input, arguments[0], arguments[1], arguments[2]), path)
            }
        case .env:
            try emit(.emptyObject, path)
        case .builtins:
            try emit(.array(ModuleJSONArray(ModuleJQPrelude.names.map { .string($0) }, childDepth: 0)), path)
        case .input:
            throw fail("break")
        case .debug:
            log("[\"DEBUG:\"," + Self.logText(input) + "]")
            try emit(input, path)
        case .stderr:
            log(Self.logText(input))
            try emit(input, path)
        case .inputFilename:
            try emit(.null, path)
        case .inputLineNumber:
            try emit(.number(0), path)
        case .halt:
            throw ModuleJQThrow.halt(nil)
        case .haltError:
            try values(arguments, input, env) { _ in throw ModuleJQThrow.halt(input) }
        case .error:
            throw ModuleJQThrow.raised(input)
        case .range:
            try eval(arguments[0], input, nil, env) { from, _ in
                try self.eval(arguments[1], input, nil, env) { upto, _ in
                    guard case .number(let start) = from, case .number(let end) = upto else {
                        throw self.fail("Range bounds must be numeric")
                    }
                    var current = from
                    var value = start.value
                    while value < end.value {
                        try self.tick()
                        try emit(current, path)
                        value += 1
                        current = .number(value)
                    }
                }
            }
        case .getSearchList:
            try emit(.emptyArray, path)
        case .frexp, .modf, .lgammaR:
            guard case .number(let number) = input else { throw typeError(input, "number required") }
            let x = number.value
            let pair: [Double]
            switch native {
            case .frexp:
                let result = Foundation.frexp(x)
                pair = [result.0, Double(result.1)]
            case .modf:
                let result = Foundation.modf(x)
                pair = [result.1, result.0]
            default:
                var sign: Int32 = 0
                let value = lgamma_r(x, &sign)
                pair = [value, Double(sign)]
            }
            try emit(.array(ModuleJSONArray(pair.map { .number($0) }, childDepth: 0)), path)
        case .math1(let name):
            guard case .number(let number) = input else { throw typeError(input, "number required") }
            try emit(.number(Self.math1(name, number.value)), path)
        case .math2(let name):
            try values(arguments, input, env) { arguments in
                guard case .number(let a) = arguments[0] else { throw self.typeError(arguments[0], "number required") }
                guard case .number(let b) = arguments[1] else { throw self.typeError(arguments[1], "number required") }
                try emit(.number(Self.math2(name, a.value, b.value)), path)
            }
        case .fma:
            try values(arguments, input, env) { arguments in
                var numbers: [Double] = []
                for argument in arguments {
                    guard case .number(let n) = argument else { throw self.typeError(argument, "number required") }
                    numbers.append(n.value)
                }
                try emit(.number(Foundation.fma(numbers[0], numbers[1], numbers[2])), path)
            }
        case .unsupportedTime(let name):
            throw fail("\(name) is not supported: the time and locale functions are left out of a module's jq")

         
        case .map:
            var gathered = ModuleJQGathered()
            try iterate(input, nil) { item, _ in
                try self.eval(arguments[0], item, nil, env) { value, _ in try gathered.append(value, self) }
            }
            try emit(try gathered.array(self), path)
        case .select:
            if arguments[0].isSingle {
                if try single(arguments[0], input, env).isTruthy { try emit(input, path) }
                return
            }
            try eval(arguments[0], input, nil, env) { verdict, _ in
                if verdict.isTruthy { try emit(input, path) }
            }
        case .recurse0:
            try recurseAll(input, path, emit)
        case .recurse1:
            try recurse(arguments[0], input, path, env, emit)
        case .recurseLoop, .recurse2Loop:
             
             
            var value = input
            var at = path
            while true {
                try tick()
                try emit(value, at)
                guard let (next, nextAt) = try atMostOne(arguments[0], value, at, env) else { return }
                if native == .recurse2Loop, !(try single(arguments[1], next, env).isTruthy) { return }
                value = next
                at = nextAt
            }
        case .recurse2:
            try call(ModuleJQPrelude.fallbacks["recurse/2"]!, arguments, nil, input, path, env, emit)
        case .first:
            let label = newLabel()
            do {
                try eval(arguments[0], input, path, env) { value, at in
                    try emit(value, at)
                    throw ModuleJQThrow.breakLabel(label)
                }
            } catch ModuleJQThrow.breakLabel(let target) where target == label {
            }
        case .limit:
            try eval(arguments[0], input, nil, env) { count, _ in
                guard case .number(let n) = count else {
                    return try self.call(ModuleJQPrelude.fallbacks["limit/2"]!, [.literal(count), arguments[1]], nil, input, path, env, emit)
                }
                if n.value == 0 { return }
                if n.value < 0 { return try self.eval(arguments[1], input, path, env, emit) }
                let label = self.newLabel()
                var left = n.value
                do {
                    try self.eval(arguments[1], input, path, env) { value, at in
                        left -= 1
                        try emit(value, at)
                        if left <= 0 { throw ModuleJQThrow.breakLabel(label) }
                    }
                } catch ModuleJQThrow.breakLabel(let target) where target == label {
                }
            }
        case .isempty:
            let label = newLabel()
            var produced = false
            do {
                try eval(arguments[0], input, path, env) { _, _ in
                    produced = true
                    try emit(.bool(false), path)
                    throw ModuleJQThrow.breakLabel(label)
                }
            } catch ModuleJQThrow.breakLabel(let target) where target == label {
            }
            if !produced { try emit(.bool(true), path) }
        case .any0, .any1, .any2, .all0, .all1, .all2:
            let wantsAny = native == .any0 || native == .any1 || native == .any2
            let label = newLabel()
            var decided = false
            do {
                try generatorAndCondition(native, arguments, input, env) { verdict in
                    if verdict.isTruthy == wantsAny {
                        decided = true
                        throw ModuleJQThrow.breakLabel(label)
                    }
                }
            } catch ModuleJQThrow.breakLabel(let target) where target == label {
            }
            try emit(.bool(wantsAny ? decided : !decided), path)
        case .in1, .in2:
             
            let label = newLabel()
            var found = false
            do {
                if native == .in1 {
                    try eval(arguments[0], input, nil, env) { candidate, _ in
                        if candidate == input {
                            found = true
                            throw ModuleJQThrow.breakLabel(label)
                        }
                    }
                } else {
                    try eval(arguments[1], input, nil, env) { candidate, _ in
                        try self.eval(arguments[0], input, nil, env) { source, _ in
                            if source == candidate {
                                found = true
                                throw ModuleJQThrow.breakLabel(label)
                            }
                        }
                    }
                }
            } catch ModuleJQThrow.breakLabel(let target) where target == label {
            }
            try emit(.bool(found), path)
        case .toEntries:
            try emit(try toEntries(input), path)
        case .fromEntries:
            var entries: [Value] = []
            try iterate(input, nil) { entry, _ in
                try self.beforeAppend(to: entries)
                entries.append(entry)
            }
            try emit(try fromEntries(entries), path)
        case .withEntries:
            guard case .array(let entries) = try toEntries(input) else { preconditionFailure("to_entries builds an array") }
            var mapped = ModuleJQGathered()
            for entry in entries.items {
                try eval(arguments[0], entry, nil, env) { value, _ in try mapped.append(value, self) }
            }
            try emit(try fromEntries(mapped.items), path)
        case .add:
            try emit(try add(input), path)
        case .join:
            try values(arguments, input, env) { arguments in try emit(try self.join(input, arguments[0]), path) }
        case .whileLoop:
             
             
            guard path == nil else {
                return try call(ModuleJQPrelude.fallbacks["while/2"]!, arguments, nil, input, path, env, emit)
            }
            var value = input
            while try single(arguments[0], value, env).isTruthy {
                try tick()
                try emit(value, nil)
                guard let (next, _) = try atMostOne(arguments[1], value, nil, env) else { return }
                value = next
            }
        case .whileDefinition:
            try call(ModuleJQPrelude.fallbacks["while/2"]!, arguments, nil, input, path, env, emit)
        case .untilLoop:
             
             
            guard path == nil else {
                return try call(ModuleJQPrelude.fallbacks["until/2"]!, arguments, nil, input, path, env, emit)
            }
            var value = input
            while !(try single(arguments[0], value, env).isTruthy) {
                try tick()
                guard let (next, _) = try atMostOne(arguments[1], value, nil, env) else { return }
                value = next
            }
            try emit(value, nil)
        case .untilDefinition:
            try call(ModuleJQPrelude.fallbacks["until/2"]!, arguments, nil, input, path, env, emit)
        case .range3:
             
             
            guard path == nil else { return try call(ModuleJQPrelude.fallbacks["range/3"]!, arguments, nil, input, path, env, emit) }
            try eachValue(arguments[0], input, env) { from in
                try self.eachValue(arguments[1], input, env) { upto in
                    try self.eachValue(arguments[2], input, env) { by in
                        let direction = ModuleJSONOrder.compare(by, .number(0))
                        guard direction != 0 else { return }
                        var value = from
                        while true {
                            let order = ModuleJSONOrder.compare(value, upto)
                            guard direction > 0 ? order < 0 : order > 0 else { break }
                            try self.tick()
                            try emit(value, nil)
                            value = try self.binary(.plus, value, by)
                        }
                    }
                }
            }
        case .combinations:
             
             
             
            guard path == nil, case .array(let array) = input else {
                return try call(ModuleJQPrelude.fallbacks["combinations/0"]!, arguments, nil, input, path, env, emit)
            }
            var choices: [[Value]] = []
            for element in array.items {
                var values: [Value] = []
                try iterate(element, nil) { value, _ in values.append(value) }
                if values.isEmpty { return }
                try reserve(ModuleJSONLedger.arrayBytes(capacity: values.count))
                choices.append(values)
            }
            var positions = [Int](repeating: 0, count: choices.count)
            while true {
                try tick()
                try reserve(ModuleJSONLedger.arrayBytes(capacity: positions.count))
                try emit(.array(ModuleJSONArray(positions.indices.map { choices[$0][positions[$0]] })), nil)
                var turning = positions.count - 1
                while turning >= 0 {
                    positions[turning] += 1
                    if positions[turning] < choices[turning].count { break }
                    positions[turning] = 0
                    turning -= 1
                }
                if turning < 0 { return }
            }
        case .nwise:
            guard path == nil else { return try call(ModuleJQPrelude.fallbacks["_nwise/1"]!, arguments, nil, input, path, env, emit) }
            try eachValue(arguments[0], input, env) { n in try self.nwise(input, n, emit) }
        case .repeatForever:
            while true {
                try tick()
                try eval(arguments[0], input, path, env, emit)
            }
        case .reverse:
            try emit(try reverse(input), path)
        case .del:
            var list: [Value] = []
            try paths(arguments[0], input, env) { at in
                try self.beforeAppend(to: list)
                list.append(.array(ModuleJSONArray(try self.components(at))))
            }
            try emit(try deletePaths(input, list), path)
        case .asciiDowncase, .asciiUpcase:
            guard case .string(let string) = input else { throw fail("explode input must be a string") }
            try produce(string.utf8.count)
            try charge(string.utf8.count >> 6)
            let lower = native == .asciiDowncase
            let bytes = string.utf8.map { byte -> UInt8 in
                if lower, (0x41...0x5A).contains(byte) { return byte + 32 }
                if !lower, (0x61...0x7A).contains(byte) { return byte - 32 }
                return byte
            }
            try emit(.string(String(decoding: bytes, as: UTF8.self)), path)
        }
    }

     
    func eachValue(_ node: ModuleJQNode, _ input: Value, _ env: ModuleJQEnvironment?, _ body: (Value) throws -> Void) throws {
        if node.isSingle { return try body(try single(node, input, env)) }
        try eval(node, input, nil, env) { value, _ in try body(value) }
    }

     
     
     
    func nwise(_ input: Value, _ n: Value, _ emit: Emit) throws {
        let head = Value.object(ModuleJSONObject(uniqueKeys: ["start", "end"], values: [.number(0), n]))
        let tail = Value.object(ModuleJSONObject(uniqueKeys: ["start", "end"], values: [n, .null]))
        switch input {
        case .array(let array):
            var offset = 0
            while true {
                try tick()
                let rest = array.count - offset
                if ModuleJSONOrder.compare(.number(Double(rest)), n) <= 0 {
                    if offset == 0 { return try emit(input, nil) }
                    try reserve(ModuleJSONLedger.arrayBytes(capacity: rest))
                    return try emit(.array(ModuleJSONArray(Array(array.items[offset...]), childDepth: array.depth - 1)), nil)
                }
                guard let (start, end) = Self.slice(head, length: rest), let (skip, _) = Self.slice(tail, length: rest) else {
                    throw fail("Array/string slice indices must be integers")
                }
                try reserve(ModuleJSONLedger.arrayBytes(capacity: end - start))
                try emit(.array(ModuleJSONArray(Array(array.items[(offset + start)..<(offset + end)]), childDepth: array.depth - 1)), nil)
                offset += skip
            }
        case .string(let string):
            try reserve(string.unicodeScalars.count * 4)
            let scalars = Array(string.unicodeScalars)
            func text(_ range: Range<Int>) throws -> Value {
                var view = String.UnicodeScalarView()
                view.append(contentsOf: scalars[range])
                let piece = String(view)
                try produce(piece.utf8.count)
                return .string(piece)
            }
            var offset = 0
            while true {
                try tick()
                let rest = scalars.count - offset
                if ModuleJSONOrder.compare(.number(Double(rest)), n) <= 0 {
                    return try emit(offset == 0 ? input : try text(offset..<scalars.count), nil)
                }
                guard let (start, end) = Self.slice(head, length: rest), let (skip, _) = Self.slice(tail, length: rest) else {
                    throw fail("Array/string slice indices must be integers")
                }
                try emit(try text((offset + start)..<(offset + end)), nil)
                offset += skip
            }
        default:
            var value = input
            while true {
                try tick()
                if ModuleJSONOrder.compare(try length(value), n) <= 0 { return try emit(value, nil) }
                try emit(try index(value, head), nil)
                value = try index(value, tail)
            }
        }
    }

     
     
    func atMostOne(_ node: ModuleJQNode, _ input: Value, _ path: ModuleJQPath?, _ env: ModuleJQEnvironment?) throws
        -> (Value, ModuleJQPath?)? {
        if path == nil, node.isSingle { return (try single(node, input, env), nil) }
        var found: (Value, ModuleJQPath?)?
        try eval(node, input, path, env) { value, at in found = (value, at) }
        return found
    }

     
    private func recurse(_ step: ModuleJQNode, _ value: Value, _ at: ModuleJQPath?, _ env: ModuleJQEnvironment?,
                         _ emit: Emit) throws {
        try emit(value, at)
        try enter()
        defer { leave() }
        try eval(step, value, at, env) { next, nextAt in
            try self.recurse(step, next, nextAt, env, emit)
        }
    }

     
    private func generatorAndCondition(_ native: ModuleJQNative, _ arguments: [ModuleJQNode], _ input: Value,
                                       _ env: ModuleJQEnvironment?, _ verdict: (Value) throws -> Void) throws {
        switch native {
        case .any0, .all0:
            try iterate(input, nil) { item, _ in try verdict(item) }
        case .any1, .all1:
            try iterate(input, nil) { item, _ in
                try self.eval(arguments[0], item, nil, env) { value, _ in try verdict(value) }
            }
        default:
            try eval(arguments[0], input, nil, env) { item, _ in
                try self.eval(arguments[1], item, nil, env) { value, _ in try verdict(value) }
            }
        }
    }
}
#endif
