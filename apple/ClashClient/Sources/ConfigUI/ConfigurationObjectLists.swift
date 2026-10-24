import Foundation
import ClashClientKit

 
 
 
indirect enum ConfigurationListLocation: Hashable {
    case key([String])
    case inItem(ConfigurationListLocation, index: Int, path: [String])

     
    var steps: [ConfigurationDocumentStep] {
        switch self {
        case .key(let path):
            return path.map(ConfigurationDocumentStep.key)
        case .inItem(let parent, let index, let path):
            return parent.steps + [.index(index)] + path.map(ConfigurationDocumentStep.key)
        }
    }

     
    func items(in document: OrderedJSON) -> [OrderedJSON] {
        switch self {
        case .key(let path):
            if case .array(let items)? = document.node(at: path) { return items }
            return []
        case .inItem(let parent, let index, let path):
            let owners = parent.items(in: document)
            guard owners.indices.contains(index), case .array(let items)? = owners[index].node(at: path) else { return [] }
            return items
        }
    }

     
     
     
     
     
    func edit(writing items: [OrderedJSON], in document: OrderedJSON) -> ConfigurationPageEdit {
        switch self {
        case .key(let path):
            return .set(path: path, to: .array(items))
        case .inItem(let parent, let index, let path):
            var owners = parent.items(in: document)
            if owners.indices.contains(index) {
                owners[index] = owners[index].setting(path: path, to: .array(items))
            }
            return parent.edit(writing: owners, in: document)
        }
    }
}

 
 
enum ConfigurationObjectList {
     
    static func listPath(_ location: ConfigurationListLocation, in document: OrderedJSON,
                         catalog: ConfigurationFieldCatalog) -> String? {
        catalog.catalogPath(of: location.steps, in: document)
    }

     
     
    static func itemPath(_ location: ConfigurationListLocation, index: Int, in document: OrderedJSON,
                         catalog: ConfigurationFieldCatalog) -> String? {
        catalog.catalogPath(of: location.steps + [.index(index)], in: document)
    }

     
     
    static func types(_ location: ConfigurationListLocation, in document: OrderedJSON,
                      catalog: ConfigurationFieldCatalog) -> [String] {
        guard let list = listPath(location, in: document, catalog: catalog) else { return [] }
        return ConfigurationNewItem.types(ofList: list, catalog: catalog)
    }

     
     
    static func newItemForm(_ location: ConfigurationListLocation, type: String?, in document: OrderedJSON,
                            catalog: ConfigurationFieldCatalog) -> ConfigurationNewItem {
        guard let list = listPath(location, in: document, catalog: catalog) else {
            return ConfigurationNewItem(type: type, asked: [])
        }
        return ConfigurationNewItem.make(listPath: list, type: type, in: document, catalog: catalog)
    }

     
    static func fields(under catalogPath: String, catalog: ConfigurationFieldCatalog) -> [ConfigurationField] {
        ConfigurationNewItem.fields(under: catalogPath, catalog: catalog)
    }

     
     
    static func title(of item: OrderedJSON, index: Int) -> String {
        switch item {
        case .object:
            for key in ["name", "type", "username", "address"] {
                if let text = text(item.topLevelValue(key)) { return text }
            }
            return "#\(index + 1)"
        case .string(let text):
            return text
        case .scalar(let token):
            return token
        default:
            return "#\(index + 1)"
        }
    }

    private static func text(_ node: OrderedJSON?) -> String? {
        switch node {
        case .string(let text)?: return text
        case .scalar(let token)? where token != "null": return token
        default: return nil
        }
    }
}

 
 
 
 
 
 
enum ConfigurationListenOff: Equatable {
     
     
    case remove
     
    case fileText
     
    case layerAndFileText
     
     
    case writeEmpty

    static func of(ownLayer: Bool, inLayer: Bool, inFile: Bool, original: Bool,
                   followsSubscription: Bool) -> ConfigurationListenOff? {
        guard ownLayer else { return .remove }
        guard original else { return .writeEmpty }
        switch (inLayer, inFile) {
        case (false, false): return nil
        case (true, false): return .remove
        case (_, true) where followsSubscription: return .writeEmpty
        case (false, true): return .fileText
        case (true, true): return .layerAndFileText
        }
    }

     
    static func of(path: [String], page: ProfilesViewModel.ConfigurationEditorPage) -> ConfigurationListenOff? {
        let original = page.form == .original
        return of(ownLayer: page.ownLayer != nil, inLayer: page.ownLayer?.node(at: path) != nil,
                  inFile: original && page.document.node(at: path) != nil, original: original,
                  followsSubscription: page.followsSubscription)
    }
}

 
 
 
enum ConfigurationRowDeletion: Equatable {
     
    case layer
     
     
    case fileText
     
    case sourceOnly
     
     
     
    case layerAndFileText

    static func of(path: [String], isMapEntry: Bool, page: ProfilesViewModel.ConfigurationEditorPage?,
                   running: OrderedJSON?) -> ConfigurationRowDeletion? {
        guard let page, running?.node(at: path) != nil else { return nil }
         
        guard let ownLayer = page.ownLayer else { return .layer }
        let inLayer = ownLayer.node(at: path) != nil
         
         
        let inFile = isMapEntry && page.form == .original && page.document.node(at: path) != nil
        switch (inLayer, inFile) {
        case (true, false): return .layer
        case (true, true): return page.followsSubscription ? .sourceOnly : .layerAndFileText
        case (false, true): return page.followsSubscription ? .sourceOnly : .fileText
         
         
        case (false, false): return nil
        }
    }
}
