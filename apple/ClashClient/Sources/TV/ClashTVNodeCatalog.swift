import Foundation
import Clash

 
 
 
 
 
 
 
 
 
 
 
final class ClashTVNodeCatalog: @unchecked Sendable {
    private let catalog: ClashNodeCatalog

    private init(_ catalog: ClashNodeCatalog) { self.catalog = catalog }

    deinit { catalog.close() }

    enum OpeningError: LocalizedError {
        case notOpened
        var errorDescription: String? { "The configuration's nodes could not be read." }
    }

     
     
     
    static func open(container: URL, publishedConfig: String) throws -> ClashTVNodeCatalog {
        try AppCoreSetup.ensure(container: container)
        let map = try ConfigTransforms.resourceMapJSON(
            providerPaths: [:], providerReadPaths: nil, seeds: .init(),
            nodeLibraryDirectory: ClashTVConfigPipeline.nodeLibraryDirectory(container: container))
        var error: NSError?
        guard let catalog = AppCore.openNodeCatalog(publishedConfig, map, "{}", &error) else {
            throw error ?? OpeningError.notOpened
        }
        return ClashTVNodeCatalog(catalog)
    }

     
     
    func summary() -> Data { Data(catalog.summaryJSON().utf8) }

     
    func members(of group: String, offset: Int, limit: Int) -> Data {
        Data(catalog.groupMembersJSON(group, offset: Int32(clamping: offset), limit: Int32(clamping: limit)).utf8)
    }

     
    func proxies(after: String, limit: Int) -> Data {
        Data(catalog.proxiesPageJSON(after, limit: Int32(clamping: limit)).utf8)
    }

    func close() { catalog.close() }
}
