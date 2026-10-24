#if os(iOS) || os(macOS)
import Foundation

 
 

 

final class ModuleJQEnvironment {
    enum Entry {
        case value(ModuleJSONValue)
        case closure(ModuleJQNode, ModuleJQEnvironment?)
        case function(ModuleJQFunction)
        case label(Int)
    }

     
    private(set) var parent: ModuleJQEnvironment?
    let entry: Entry
     
     
    private var run: UInt32 = 0
    private var charged = 0

    init(_ parent: ModuleJQEnvironment?, _ entry: Entry) {
        self.parent = parent
        self.entry = entry
        if case .value(.string(let string)) = entry {
            let bytes = ModuleJSONLedger.stringBytes(string)
            if bytes > 0, let ledger = ModuleJSONLedger.current {
                run = ledger.run
                charged = bytes
                ledger.live &+= bytes
            }
        }
    }

    deinit {
        if run != 0, let ledger = ModuleJSONLedger.current, ledger.run == run { ledger.live &-= charged }
        ModuleJQEnvironment.unlink(&parent)
    }

     
    static func unlink(_ head: inout ModuleJQEnvironment?) {
        var next = head
        head = nil
        while isKnownUniquelyReferenced(&next) {
            let following = next!.parent
            next!.parent = nil
            next = following
        }
    }

    @inline(__always)
    static func up(_ environment: ModuleJQEnvironment?, _ hops: Int) -> ModuleJQEnvironment {
        var node = environment!
        var left = hops
        while left > 0 {
            node = node.parent!
            left -= 1
        }
        return node
    }
}

 
 
final class ModuleJQPath {
     
    private(set) var parent: ModuleJQPath?
    let component: ModuleJSONValue
    let value: ModuleJSONValue
    let length: Int

    init(root value: ModuleJSONValue) {
        parent = nil
        component = .null
        self.value = value
        length = 0
    }

    init(_ parent: ModuleJQPath, _ component: ModuleJSONValue, _ value: ModuleJSONValue) {
        self.parent = parent
        self.component = component
        self.value = value
        length = parent.length + 1
    }

    deinit {
        var next = parent
        parent = nil
        while isKnownUniquelyReferenced(&next) {
            let following = next!.parent
            next!.parent = nil
            next = following
        }
    }

     
    static let bytes = 96

    var components: [ModuleJSONValue] {
        var result = [ModuleJSONValue](repeating: .null, count: length)
        var node: ModuleJQPath? = self
        while let current = node, current.length > 0 {
            result[current.length - 1] = current.component
            node = current.parent
        }
        return result
    }

    func appending(_ components: [ModuleJSONValue], value: ModuleJSONValue) -> ModuleJQPath {
        var node = self
        for (offset, component) in components.enumerated() {
            node = ModuleJQPath(node, component, offset == components.count - 1 ? value : .null)
        }
        return components.isEmpty ? ModuleJQPath(parent: parent, component: component, value: value, length: length) : node
    }

    private init(parent: ModuleJQPath?, component: ModuleJSONValue, value: ModuleJSONValue, length: Int) {
        self.parent = parent
        self.component = component
        self.value = value
        self.length = length
    }
}

 

 
 
 
indirect enum ModuleJQThrow: Error {
    case raised(ModuleJSONValue)
    case breakLabel(Int)
     
    case downstream(ModuleJQThrow, owner: Int)
    case halt(ModuleJSONValue?)
    case stop(String)
}
#endif
