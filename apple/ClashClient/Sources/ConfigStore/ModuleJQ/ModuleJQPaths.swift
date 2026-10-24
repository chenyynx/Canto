#if os(iOS) || os(macOS)
import Foundation

 
 
 

extension ModuleJQMachine {
     
    func index(_ t: Value, _ k: Value) throws -> Value {
        switch (t, k) {
        case (.object(let object), .string(let key)):
            return object[key] ?? .null
        case (.array(let array), .number(let number)):
            if number.value.isNaN { return .null }
            var index = Self.int32(number.value)
            if index < 0 { index += array.count }
            return index >= 0 && index < array.count ? array[index] : .null
        case (.array(let array), .object):
            guard let (start, end) = Self.slice(k, length: array.count) else {
                throw fail("Array/string slice indices must be integers")
            }
            try reserve(ModuleJSONLedger.arrayBytes(capacity: end - start))
            return .array(ModuleJSONArray(Array(array.items[start..<end]), childDepth: array.depth - 1))
        case (.string(let string), .object):
            let scalars = string.unicodeScalars
            guard let (start, end) = Self.slice(k, length: scalars.count) else {
                throw fail("Array/string slice indices must be integers")
            }
            let from = scalars.index(scalars.startIndex, offsetBy: start)
            let to = scalars.index(from, offsetBy: end - start)
            let slice = String(scalars[from..<to])
            try produce(slice.utf8.count)
            return .string(slice)
        case (.array(let array), .array(let needle)):
            return .array(ModuleJSONArray(try arrayIndices(of: needle.items, in: array.items).map { .number(Double($0)) }, childDepth: 0))
        case (.null, .string), (.null, .number), (.null, .object):
            return .null
        case (_, .string(let key)):
            throw fail("Cannot index \(t.typeName) with string \"\(key)\"")
        default:
            throw fail("Cannot index \(t.typeName) with \(k.typeName)")
        }
    }

     

    static func int32(_ x: Double) -> Int {
        if x.isNaN { return 0 }
        if x >= 2_147_483_647 { return Int(Int32.max) }
        if x <= -2_147_483_648 { return Int(Int32.min) }
        return Int(x.rounded(.towardZero))
    }

     

    static func slice(_ key: Value, length: Int) -> (Int, Int)? {
         
        guard case .object(let object) = key, var start = object["start"], var end = object["end"] else { return nil }
        if case .null = start { start = .number(0) }
        if case .null = end { end = .number(Double(length)) }
        guard case .number(let s) = start, case .number(let e) = end else { return nil }
        var dstart = s.value, dend = e.value
        let len = Double(length)
        if dstart < 0 { dstart += len }
        if dend < 0 { dend += len }
        if dstart < 0 { dstart = 0 }
        if dstart > len { dstart = len }
        if dend > len { dend = len }
        if dend < dstart { dend = dstart }
        if dstart.isNaN { dstart = 0 }
        if dend.isNaN { dend = dstart }
        let startIndex = Int(dstart)
        var endIndex = Int(dend)
        if dend > Double(endIndex) { endIndex += 1 }
        return (startIndex, min(max(endIndex, startIndex), length))
    }

     

    func getPathValue(_ t: Value, _ path: Value) throws -> Value {
        if case .null = path { return t }
        guard case .array(let components) = path else { throw fail("Path must be specified as an array") }
        return try getPath(t, components.items[...])
    }

    func getPath(_ t: Value, _ path: ArraySlice<Value>) throws -> Value {
        var current = t
        for component in path { current = try index(current, component) }
        return current
    }

     
     
     
     
     

    func setPath(_ root: inout Value, _ path: ArraySlice<Value>, _ value: Value) throws {
        guard !path.isEmpty else {
            root = value
            return
        }
        try checkDepth(building: path.count + value.depth)
        var spine: [Value] = []
        spine.reserveCapacity(path.count)
        var current = root
        root = .null
        for key in path {
            let sub = try index(current, key)
             
            if case .object = key {} else { try setIndex(&current, key, .null) }
            spine.append(current)
            current = sub
        }
        current = value
        var position = path.endIndex
        while var parent = spine.popLast() {
            position -= 1
            try setIndex(&parent, path[position], current)
            current = parent
        }
        root = current
    }

     
     

    func setIndex(_ t: inout Value, _ k: Value, _ v: Value) throws {
        try checkDepth(building: v.depth + 1)
        switch k {
        case .string(let key):
            var object: ModuleJSONObject
            switch t {
            case .object(let existing): object = existing
            case .null: object = ModuleJSONObject()
            default: throw fail("Cannot update field at object index of \(t.typeName)")
            }
            t = .null
            object.set(key, v)
            t = .object(object)
        case .number(let number):
            var array: ModuleJSONArray
            switch t {
            case .array(let existing): array = existing
            case .null: array = ModuleJSONArray()
            default: throw fail("Cannot update field at object index of \(t.typeName)")
            }
            var index = Self.int32(number.value)
            if index < 0 { index += array.count }
            if index < 0 { throw fail("Out of bounds negative array index") }
            if index > (Int(Int32.max) >> 2) { throw fail("Array index too large") }
            if index >= array.count {
                try reserve((index - array.count) * MemoryLayout<Value>.stride)
                try charge((index - array.count) / 64)
            }
            t = .null
            if index >= array.count {
                array.modify { items in
                    items.append(contentsOf: repeatElement(.null, count: index - items.count))
                    items.append(v)
                }
            } else {
                array.set(index, v)
            }
            t = .array(array)
        case .object:
            var array: ModuleJSONArray
            switch t {
            case .array(let existing): array = existing
            case .null: array = ModuleJSONArray()
            default: throw fail("Cannot update field at object index of \(t.typeName)")
            }
            guard let (start, end) = Self.slice(k, length: array.count) else {
                throw fail("Array/string slice indices must be integers")
            }
            guard case .array(let insert) = v else { throw fail("A slice of an array can only be assigned another array") }
            t = .null
            array.modify { items in items.replaceSubrange(start..<end, with: insert.items) }
            t = .array(array)
        default:
            throw fail("Cannot update field at object index of \(t.typeName)")
        }
    }

     

    func deletePaths(_ object: Value, _ paths: [Value]) throws -> Value {
        var list = paths
        for path in list {
            guard case .array = path else { throw fail("Path must be specified as array, not \(path.typeName)") }
        }
        if list.isEmpty { return object }
        list = try sorted(list, keys: list).map { $0.value }
        if case .array(let first) = list[0], first.isEmpty { return .null }
        return try deleteSorted(object, list, 0)
    }

    private func deleteSorted(_ object: Value, _ paths: [Value], _ start: Int) throws -> Value {
        try guardStack()
        var object = object
        var deleteKeys: [Value] = []
        var i = 0
        while i < paths.count {
            guard case .array(let first) = paths[i] else { break }
            let key = first[start]
            let deleteKey = first.count == start + 1
            var j = i
            while j < paths.count, case .array(let candidate) = paths[j], candidate[start] == key { j += 1 }
            if deleteKey {
                deleteKeys.append(key)
            } else {
                let sub = try index(object, key)
                if case .null = sub {
                } else {
                    let newSub = try deleteSorted(sub, Array(paths[i..<j]), start + 1)
                    try setIndex(&object, key, newSub)
                }
            }
            i = j
        }
        return try deleteKeysFrom(object, deleteKeys)
    }

     

    private func deleteKeysFrom(_ t: Value, _ keys: [Value]) throws -> Value {
        if keys.isEmpty { return t }
        switch t {
        case .null:
            return t
        case .array(let array):
            var negative: [Int] = [], nonNegative: [Int] = [], starts: [Int] = [], ends: [Int] = []
            for key in keys {
                switch key {
                case .number(let number):
                    if number.value < 0 { negative.append(Self.int32(number.value)) } else { nonNegative.append(Self.int32(number.value)) }
                case .object:
                    guard let (start, end) = Self.slice(key, length: array.count) else {
                        throw fail("Array/string slice indices must be integers")
                    }
                    starts.append(start)
                    ends.append(end)
                default:
                    throw fail("Cannot delete \(key.typeName) element of array")
                }
            }
            let length = array.count
            var negativeIndex = 0, nonNegativeIndex = 0
            var kept: [Value] = []
            try reserve(ModuleJSONLedger.arrayBytes(capacity: length))
            kept.reserveCapacity(length)
            for (i, element) in array.items.enumerated() {
                var delete = false
                while negativeIndex < negative.count {
                    let target = length + negative[negativeIndex]
                    if i == target { delete = true }
                    if i < target { break }
                    negativeIndex += 1
                }
                while nonNegativeIndex < nonNegative.count {
                    let target = nonNegative[nonNegativeIndex]
                    if i == target { delete = true }
                    if i < target { break }
                    nonNegativeIndex += 1
                }
                var slice = 0
                while !delete, slice < starts.count {
                    if starts[slice] <= i && i < ends[slice] { delete = true }
                    slice += 1
                }
                if !delete { kept.append(element) }
            }
            return .array(ModuleJSONArray(kept))
        case .object(var object):
            var names: [String] = []
            for key in keys {
                guard case .string(let name) = key else { throw fail("Cannot delete field at index of \(key.typeName)") }
                names.append(name)
            }
            object.remove(keys: names)
            return .object(object)
        default:
            throw fail("Cannot delete fields from \(t.typeName)")
        }
    }
}
#endif
