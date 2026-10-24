import Foundation

 
 
 
 
 
 
struct ModuleBackupSection: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    struct Module: Codable, Equatable, Sendable {
        var origin: ModuleRecord.Origin
        var name: String
        var enabled: Bool
        var updateInterval: Int
         
         
         
        var source: Data
         
        var lastUpdatedAt: Date? = nil
         
         
        var argumentValues: [String: String]? = nil
         
         
         
        var storedValues: [String: String]? = nil
    }

    var schemaVersion: Int
    var modules: [Module]

     
     
     
    struct LeftOut: Equatable, Sendable {
        var names: [String]
         
         
        var reason: String
    }

     
     
    struct Lenient: Decodable {
        var section: ModuleBackupSection?
        var leftOut: LeftOut?

        private enum Keys: String, CodingKey { case schemaVersion, modules, name }

         
        private struct Entry: Decodable {
            let module: Module?
            let name: String?
            let failure: String?

            init(from decoder: Decoder) {
                do {
                    module = try Module(from: decoder)
                    failure = nil
                } catch {
                    module = nil
                    failure = String(describing: error)
                }
                name = try? decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .name)
            }
        }

        init(from decoder: Decoder) {
            guard let container = try? decoder.container(keyedBy: Keys.self) else {
                leftOut = LeftOut(names: [], reason: "section-not-an-object")
                return
            }
            let entries = try? container.decode([Entry].self, forKey: .modules)
            guard let version = try? container.decode(Int.self, forKey: .schemaVersion) else {
                leftOut = LeftOut(names: entries?.map { $0.name ?? "" } ?? [], reason: "section-without-version")
                return
            }
            guard version <= ModuleBackupSection.currentSchemaVersion else {
                leftOut = LeftOut(names: entries?.map { $0.name ?? "" } ?? [],
                                  reason: "the section is version \(version); this build reads \(ModuleBackupSection.currentSchemaVersion)")
                return
            }
            guard let entries else {
                leftOut = LeftOut(names: [], reason: "section-modules-not-a-list")
                return
            }
            let read = entries.compactMap(\.module)
            section = read.isEmpty ? nil : ModuleBackupSection(schemaVersion: version, modules: read)
            let unread = entries.filter { $0.module == nil }
            if !unread.isEmpty {
                leftOut = LeftOut(names: unread.map { $0.name ?? "" },
                                  reason: unread.map { "\($0.name ?? "a module without a name"): \($0.failure ?? "")" }.joined(separator: "; "))
            }
        }
    }

     
     
     
     
     
    static func collect(locations: ModuleLocations) -> ModuleBackupSection? {
        guard let data = try? Data(contentsOf: locations.stateFile), !ModuleState.isFromANewerBuild(data),
              let state = try? ModuleJSON.decoder().decode(ModuleState.self, from: data) else { return nil }
        let scripts = ModuleScriptStore(directory: locations.container.appendingPathComponent(ModuleScriptStore.directoryName, isDirectory: true),
                                        log: { _ in })
        let modules = state.modules.compactMap { record -> Module? in
            let source = try? Data(contentsOf: locations.source(record.id))
            switch record.origin {
            case .unknown: return nil
             
            case .local: guard source != nil else { return nil }
             
            case .url: break
            }
            var stored: [String: String] = [:]
            for key in record.storedValues.keys { stored[key] = scripts.readShared(key: key) }
            return Module(origin: record.origin, name: record.name, enabled: record.enabled,
                          updateInterval: record.updateInterval, source: source ?? Data(),
                          lastUpdatedAt: record.lastUpdatedAt,
                          argumentValues: record.argumentValues.isEmpty ? nil : record.argumentValues,
                          storedValues: stored.isEmpty ? nil : stored)
        }
        return modules.isEmpty ? nil : ModuleBackupSection(schemaVersion: currentSchemaVersion, modules: modules)
    }
}
