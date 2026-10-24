import Clash
import ClashClientUI
import Foundation

 
 
 
 
 
enum PublishedRules {
     
     
     
     
    struct Summary: Decodable, Equatable {
        var total: Int
        var byType: [String: Int] = [:]
        var byTarget: [String: Int] = [:]
        var matchTarget: String?
        var ruleSets: [String] = []
        var subRules: [String] = []
        var uidRemoved: Int?

        var written: Int { total + (uidRemoved ?? 0) }
    }

     
    struct Entry: Decodable, Equatable {
        let index: Int
        let text: String
        let rule: String
        let type: String
        let target: String
    }

    struct Page: Decodable, Equatable {
        let total: Int
        let matched: Int
        let offset: Int
        let rules: [Entry]
    }

     
    static let pageLimit = 500

     
     
     
    struct Unreadable: LocalizedError, Equatable {
        var errorDescription: String? {
            ClashCopy.string(for: .copy("These rules could not be read. Try again."), locale: AppPreferences.language().locale)
        }
    }

     
     
    final class Catalog: @unchecked Sendable {
        private let catalog: any KernelRuleCatalog
        private let scratch: URL?

        fileprivate init(_ catalog: any KernelRuleCatalog, scratch: URL?) {
            self.catalog = catalog
            self.scratch = scratch
        }

         
         
        var total: Int { Int(catalog.total()) }

        deinit { close() }

        func summary() throws -> Summary {
            try JSONDecoder().decode(Summary.self, from: Data(catalog.summaryJSON().utf8))
        }

         
         
         
        func page(offset: Int, limit: Int = PublishedRules.pageLimit, query: String = "", target: String = "",
                  types: [String] = []) throws -> Page {
            let typesJSON = types.isEmpty
                ? "" : String(decoding: try JSONSerialization.data(withJSONObject: types), as: UTF8.self)
            let json = catalog.pageJSON(Int32(clamping: offset), limit: Int32(clamping: limit), query: query,
                                        target: target, typesJSON: typesJSON)
            return try JSONDecoder().decode(Page.self, from: Data(json.utf8))
        }

         
         
        func rules(ofTypes types: [String], most: Int) throws -> [Entry] {
            var rules: [Entry] = []
            while rules.count < most {
                let next = try page(offset: rules.count, types: types)
                rules += next.rules
                guard !next.rules.isEmpty, rules.count < next.matched else { break }
            }
            return Array(rules.prefix(most))
        }

         
         
        func lines(most: Int) throws -> [String]? {
            let total = Int(catalog.total())
            guard total <= most else { return nil }
            var lines: [String] = []
            lines.reserveCapacity(total)
            while lines.count < total {
                let next = try page(offset: lines.count)
                guard !next.rules.isEmpty else { break }
                lines += next.rules.map(\.rule)
            }
            return lines
        }

        func close() {
            catalog.close()
            if let scratch { try? FileManager.default.removeItem(at: scratch) }
        }
    }

     
     
     
     
     
     
    static func open(sourceAt path: URL) throws -> Catalog {
        var error: NSError?
        guard let catalog = AppCore.openRuleCatalogAtPath(path.path, &error) else {
            throw error ?? ConfigTransformsError.bridgeReturnedNil("OpenRuleCatalogForIOSAtPath")
        }
        return Catalog(catalog, scratch: nil)
    }

     
    static func open(publishedAt path: URL) throws -> Catalog {
        var error: NSError?
        guard let catalog = AppCore.openPublishedRuleCatalog(path.path, &error) else {
            throw error ?? ConfigTransformsError.bridgeReturnedNil("OpenRuleCatalogForPublishedAtPath")
        }
        return Catalog(catalog, scratch: nil)
    }

     
     
     
     
    static func open(publishedText text: String) throws -> Catalog? {
        guard ConfigTransforms.ruleIndexPath(in: text) != nil else { return nil }
        let scratch = FileManager.default.temporaryDirectory
            .appendingPathComponent("published-rules-\(UUID().uuidString).yaml")
        try Data(text.utf8).write(to: scratch, options: [.atomic])
        var error: NSError?
        guard let catalog = AppCore.openPublishedRuleCatalog(scratch.path, &error) else {
            try? FileManager.default.removeItem(at: scratch)
            throw error ?? ConfigTransformsError.bridgeReturnedNil("OpenRuleCatalogForPublishedAtPath")
        }
        return Catalog(catalog, scratch: scratch)
    }

     
     
    static func summary(ofPublishedText text: String) -> Summary? {
        guard let catalog = try? open(publishedText: text) else { return nil }
        defer { catalog.close() }
        return try? catalog.summary()
    }
}

 
 
protocol KernelRuleCatalog: AnyObject {
    func pageJSON(_ offset: Int32, limit: Int32, query: String?, target: String?, typesJSON: String?) -> String
    func summaryJSON() -> String
    func total() -> Int32
    func close()
}

extension ClashPublishedRuleCatalog: KernelRuleCatalog {}
extension ClashRuleCatalog: KernelRuleCatalog {}
