import Foundation

 
 
 
 
 
public enum ConfigurationPageEdit: Equatable, Sendable {
     
    case set(path: [String], to: OrderedJSON)
     
    case remove(path: [String])
     
    case insert(path: [String], at: Int, value: OrderedJSON)
     
    case replace(path: [String], at: Int, value: OrderedJSON)
     
    case delete(path: [String], at: IndexSet)
     
     
    case move(path: [String], from: IndexSet, to: Int)
     
     
    case insertKey(path: [String], key: String, value: OrderedJSON, before: String?)
     
    case renameKey(path: [String], from: String, to: String)
     
     
    case moveKeys(path: [String], keys: [String], before: String?)
}

public enum ConfigurationPageEditError: Error, Equatable, Sendable {
     
     
     
    case doesNotFit([String])
}

public extension OrderedJSON {
    func applying(_ edit: ConfigurationPageEdit) throws -> OrderedJSON {
        switch edit {
        case let .set(path, value):
            return setting(path: path, to: value)
        case let .remove(path):
            return setting(path: path, to: nil)
        case let .insert(path, index, value):
            var items = try list(at: path, creating: true)
            guard index >= 0, index <= items.count else { throw ConfigurationPageEditError.doesNotFit(path) }
            items.insert(value, at: index)
            return setting(path: path, to: .array(items))
        case let .replace(path, index, value):
            var items = try list(at: path, creating: false)
            guard items.indices.contains(index) else { throw ConfigurationPageEditError.doesNotFit(path) }
            items[index] = value
            return setting(path: path, to: .array(items))
        case let .delete(path, offsets):
            let items = try list(at: path, creating: false)
            guard offsets.allSatisfy(items.indices.contains) else { throw ConfigurationPageEditError.doesNotFit(path) }
            return setting(path: path, to: .array(items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)))
        case let .move(path, offsets, destination):
            let items = try list(at: path, creating: false)
            guard offsets.allSatisfy(items.indices.contains), destination >= 0, destination <= items.count else {
                throw ConfigurationPageEditError.doesNotFit(path)
            }
            let moving = offsets.map { items[$0] }
            var rest = items.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
            let at = destination - offsets.filter { $0 < destination }.count
            rest.insert(contentsOf: moving, at: at)
            return setting(path: path, to: .array(rest))
        case let .insertKey(path, key, value, before):
            var entries = try mapping(at: path, creating: true)
            guard !entries.contains(where: { $0.key == key }) else { throw ConfigurationPageEditError.doesNotFit(path + [key]) }
            let at = before.flatMap { target in entries.firstIndex { $0.key == target } } ?? entries.count
            entries.insert((key: key, value: value), at: at)
            return setting(path: path, to: .object(entries))
        case let .renameKey(path, old, new):
            var entries = try mapping(at: path, creating: false)
            guard let index = entries.firstIndex(where: { $0.key == old }),
                  old == new || !entries.contains(where: { $0.key == new }) else {
                throw ConfigurationPageEditError.doesNotFit(path + [old])
            }
            entries[index] = (key: new, value: entries[index].value)
            return setting(path: path, to: .object(entries))
        case let .moveKeys(path, keys, before):
            let entries = try mapping(at: path, creating: false)
            let moving = Set(keys)
            guard moving.allSatisfy({ key in entries.contains { $0.key == key } }) else {
                throw ConfigurationPageEditError.doesNotFit(path)
            }
            let moved = entries.filter { moving.contains($0.key) }
            var rest = entries.filter { !moving.contains($0.key) }
            let at = before.flatMap { target in rest.firstIndex { $0.key == target } } ?? rest.count
            rest.insert(contentsOf: moved, at: at)
            return setting(path: path, to: .object(rest))
        }
    }

    private func list(at path: [String], creating: Bool) throws -> [OrderedJSON] {
        switch node(at: path) {
        case .array(let items)?: return items
        case nil where creating: return []
        default: throw ConfigurationPageEditError.doesNotFit(path)
        }
    }

    private func mapping(at path: [String], creating: Bool) throws -> [(key: String, value: OrderedJSON)] {
        switch node(at: path) {
        case .object(let entries)?: return entries
        case nil where creating: return []
        default: throw ConfigurationPageEditError.doesNotFit(path)
        }
    }
}
