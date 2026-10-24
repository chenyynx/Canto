import CryptoKit
import Foundation

struct ExternalResourceImportFile: Equatable {
    let fileName: String
    let data: Data
}

struct PreparedExternalResourceImport {
    let yaml: String
    let references: [ProfileExternalResourceReference]
    let publicResources: [String: Data]
}

enum ProfileExternalResourceError: LocalizedError, Equatable {
    case missingSelection(field: String)
    case ambiguousSelection(field: String)
    case emptyResource(field: String)
    case resourceTooLarge(field: String)
    case resourceIsNotText(field: String)
    case storedResourceMissing(field: String)
    case storedResourceChanged(field: String)
    case invalidConfiguration

    var errorDescription: String? {
        switch self {
        case .missingSelection(let field):
            return "Select the file referenced by \(field) together with the YAML configuration."
        case .ambiguousSelection(let field):
            return "More than one selected file could satisfy \(field). Keep only the intended file and try again."
        case .emptyResource(let field):
            return "The selected file for \(field) is empty."
        case .resourceTooLarge(let field):
            return "The selected file for \(field) exceeds Clash’s 16 MB safety limit."
        case .resourceIsNotText(let field):
            return "The selected file for \(field) is not UTF-8 text."
        case .storedResourceMissing(let field):
            return "The saved resource for \(field) is missing. Re-import the profile and its resource files."
        case .storedResourceChanged(let field):
            return "The saved resource reference for \(field) no longer matches this configuration. Re-import the intended file."
        case .invalidConfiguration:
            return "The configuration resource structure is invalid."
        }
    }
}

enum ProfileExternalResourceImporter {
     
    static let maximumResourceBytes = Int.max

    static func prepare(
        yaml: String,
        profileID: String,
        source: IOSExternalResourceSource,
        files: [ExternalResourceImportFile],
        existingReferences: [ProfileExternalResourceReference] = [],
        existingPublicResources: [String: Data] = [:],
        requiringAllFiles: Bool = true
    ) throws -> PreparedExternalResourceImport {
        try PerfLedger.measure("ProfileExternalResourceImporter.prepare") {
            try prepareMeasured(yaml: yaml, profileID: profileID, source: source, files: files,
                                existingReferences: existingReferences, existingPublicResources: existingPublicResources,
                                requiringAllFiles: requiringAllFiles)
        }
    }

     
     
    private static func prepareMeasured(
        yaml: String,
        profileID: String,
        source: IOSExternalResourceSource,
        files: [ExternalResourceImportFile],
        existingReferences: [ProfileExternalResourceReference],
        existingPublicResources: [String: Data],
        requiringAllFiles: Bool
    ) throws -> PreparedExternalResourceImport {
        let json = try ConfigTransforms.yamlToJSON(yaml)
        guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8))
                as? [String: Any] else {
            throw ProfileExternalResourceError.invalidConfiguration
        }
        let findings = IOSExternalResourceCatalog.inspect(root: root, source: source)
        if requiringAllFiles, let blocked = findings.first(where: { finding in
            switch finding.resolution {
            case .localImportRequired, .managedRuntimeStateRequired:
                return false
            case .subscriptionCannotReadFile, .fileProviderUnavailable,
                 .bundleArchiveRequired:
                return true
            }
        }) {
            throw blocked
        }

        let requirements = IOSExternalResourceCatalog.requirements(root: root)
            .filter {
                $0.capability.disposition == .publicFileOrInline
                    || $0.capability.disposition == .secretFileOrInline
            }
        guard !requiringAllFiles || source == .localFile || requirements.isEmpty else {
            if let finding = findings.first { throw finding }
            throw ProfileExternalResourceError.invalidConfiguration
        }

        let filesByBasename = Dictionary(grouping: files) {
            basename($0.fileName).lowercased()
        }
        var references: [ProfileExternalResourceReference] = []
        var publicResources: [String: Data] = [:]
        var proxies = root["proxies"] as? [[String: Any]] ?? []
        var changedYAML = false
        var inlined: [ExternalResourceEdit] = []

        for requirement in requirements {
            let field = requirement.capability.fieldPath.joined(separator: ".")
            let name = basename(requirement.rawValue).lowercased()
            let candidates = filesByBasename[name] ?? []
            guard candidates.count <= 1 else {
                throw ProfileExternalResourceError.ambiguousSelection(field: field)
            }
            let expectedReference = reference(
                profileID: profileID,
                requirement: requirement
            )
            let selected: ExternalResourceImportFile
            if let candidate = candidates.first {
                selected = candidate
            } else if requirement.capability.confidentiality == .publicData,
                      existingReferences.contains(expectedReference),
                      let data = existingPublicResources[expectedReference.storageKey] {
                selected = ExternalResourceImportFile(
                    fileName: name,
                    data: data
                )
            } else if !requiringAllFiles {
                 
                 
                 
                continue
            } else {
                throw ProfileExternalResourceError.missingSelection(field: field)
            }
            guard !selected.data.isEmpty else {
                throw ProfileExternalResourceError.emptyResource(field: field)
            }
            guard selected.data.count <= maximumResourceBytes else {
                throw ProfileExternalResourceError.resourceTooLarge(field: field)
            }
             
             
             
            let decodedText = String(data: selected.data, encoding: .utf8)
            if requirement.expectedFormat != "mrs", decodedText == nil {
                throw ProfileExternalResourceError.resourceIsNotText(field: field)
            }

            switch requirement.capability.confidentiality {
            case .publicData:
                let reference = expectedReference
                if let previous = publicResources[reference.storageKey],
                   previous != selected.data {
                    throw ProfileExternalResourceError.ambiguousSelection(field: field)
                }
                publicResources[reference.storageKey] = selected.data
                references.append(reference)
            case .secret:
                guard let text = decodedText else {
                    throw ProfileExternalResourceError.resourceIsNotText(field: field)
                }
                guard let index = proxies.firstIndex(where: {
                    ($0["name"] as? String) == requirement.proxyName
                }) else {
                    throw ProfileExternalResourceError.invalidConfiguration
                }
                var proxy: Any = proxies[index]
                guard IOSExternalResourceCatalog.set(
                    text,
                    at: requirement.capability.fieldPath,
                    in: &proxy
                ), let dictionary = proxy as? [String: Any] else {
                    throw ProfileExternalResourceError.invalidConfiguration
                }
                proxies[index] = dictionary
                inlined.append(.proxy(index: index, name: requirement.proxyName,
                                      path: requirement.capability.fieldPath, value: text))
                changedYAML = true
            case .runtimeState:
                break
            }
        }

        let preparedYAML: String
        if changedYAML {
             
             
             
             
            preparedYAML = try ExternalResourceEdit.applying(inlined, toYAML: yaml)
        } else {
            preparedYAML = yaml
        }
        return PreparedExternalResourceImport(
            yaml: preparedYAML,
            references: Array(Set(references)).sorted { $0.storageKey < $1.storageKey },
            publicResources: publicResources
        )
    }

     
     
     
     
     
    static func prepareLeavingPaths(
        yaml: String,
        mapping document: OrderedJSON,
        profileID: String,
        source: IOSExternalResourceSource,
        files: [ExternalResourceImportFile]
    ) throws -> PreparedExternalResourceImport {
        if files.isEmpty, case .object = document {
            return PreparedExternalResourceImport(yaml: yaml, references: [], publicResources: [:])
        }
        return try prepare(yaml: yaml, profileID: profileID, source: source, files: files,
                           requiringAllFiles: false)
    }

    static func reference(
        profileID: String,
        requirement: IOSExternalResourceRequirement
    ) -> ProfileExternalResourceReference {
        ProfileExternalResourceReference(
            capabilityID: requirement.capability.id,
            proxy: requirement.proxyName,
            fieldPath: requirement.capability.fieldPath,
            sourceValueSHA256: sha256(Data(requirement.rawValue.utf8)),
            storageKey: storageKey(profileID: profileID, capabilityID: requirement.capability.id,
                                   proxy: requirement.proxyName, fieldPath: requirement.capability.fieldPath)
        )
    }

     
     
     
     
    static func reference(
        profileID: String,
        rekeying reference: ProfileExternalResourceReference
    ) -> ProfileExternalResourceReference {
        ProfileExternalResourceReference(
            capabilityID: reference.capabilityID,
            proxy: reference.proxy,
            fieldPath: reference.fieldPath,
            sourceValueSHA256: reference.sourceValueSHA256,
            storageKey: storageKey(profileID: profileID, capabilityID: reference.capabilityID,
                                   proxy: reference.proxy, fieldPath: reference.fieldPath)
        )
    }

    private static func storageKey(profileID: String, capabilityID: String, proxy: String, fieldPath: [String]) -> String {
        let identity = ([profileID, capabilityID, proxy] + fieldPath).joined(separator: "\u{0}")
        return "resource-\(sha256(Data(identity.utf8)).prefix(32))"
    }

    private static func basename(_ value: String) -> String {
        let normalized = value.replacingOccurrences(of: "\\", with: "/")
        return normalized.split(separator: "/").last.map(String.init) ?? normalized
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum ProfileExternalResourceStore {
    static func replace(
        _ resources: [String: Data],
        profileID: String,
        coreHomeDir: URL,
        fileManager: FileManager = .default
    ) throws {
        let staged = try stage(resources, profileID: profileID, coreHomeDir: coreHomeDir, fileManager: fileManager)
        let retired: URL?
        do { retired = try swapIn(staged, fileManager: fileManager) } catch {
            discard(staged, fileManager: fileManager)
            throw error
        }
        if let retired { try? fileManager.removeItem(at: retired) }
    }

     
     
     
    struct Staged {
        let profileDirectory: URL
        let staging: URL
    }

     
     
    static let publicationPrefix = ".resources-publishing-"

    static func stage(
        _ resources: [String: Data],
        profileID: String,
        coreHomeDir: URL,
        prefix: String = ".resources-",
        fileManager: FileManager = .default
    ) throws -> Staged {
        let profileDirectory = coreHomeDir
            .appendingPathComponent("store/\(profileID)", isDirectory: true)
        try fileManager.createDirectory(
            at: profileDirectory,
            withIntermediateDirectories: true
        )
         
         
         
        ProfileSourceStore.sweepStaging(in: profileDirectory, prefixes: [prefix], olderThan: 600)
        let staging = profileDirectory.appendingPathComponent(ProfileSourceStore.stagingName(prefix), isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for key in resources.keys.sorted() {
                guard key.hasPrefix("resource-"),
                      !key.contains("/"),
                      let data = resources[key],
                      !data.isEmpty,
                      data.count <= ProfileExternalResourceImporter.maximumResourceBytes else {
                    throw ProfileExternalResourceError.invalidConfiguration
                }
                try data.write(
                    to: staging.appendingPathComponent(key),
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
                )
            }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var protectedStaging = staging
            try protectedStaging.setResourceValues(values)
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
        return Staged(profileDirectory: profileDirectory, staging: staging)
    }

     
     
     
     
     
     
    static func swapIn(_ staged: Staged, fileManager: FileManager = .default) throws -> URL? {
        let target = staged.profileDirectory.appendingPathComponent("resources", isDirectory: true)
        guard fileManager.fileExists(atPath: target.path) else {
            try fileManager.moveItem(at: staged.staging, to: target)
            return nil
        }
         
         
         
         
        guard renamex_np(staged.staging.path, target.path, UInt32(RENAME_SWAP)) == 0 else {
            throw CocoaError(.fileWriteUnknown)
        }
        return staged.staging
    }

    static func discard(_ staged: Staged, fileManager: FileManager = .default) {
        try? fileManager.removeItem(at: staged.staging)
    }
}

enum ProfileExternalResourceMaterializer {
     
     
    static func materialize(
        yaml: String,
        root known: [String: Any]? = nil,
        profile: Profile,
        coreHomeDir: URL,
        candidate: ConfigurationCandidate,
        fileManager: FileManager = .default
    ) throws -> String {
        guard var root = try known ?? ConfigTransforms.foundationRoot(ofYAML: yaml) else {
            throw ProfileExternalResourceError.invalidConfiguration
        }
         
         
         
         
         
         
         
         
        var edits: [ExternalResourceEdit] = []
        var proxies = root["proxies"] as? [[String: Any]] ?? []
        for index in proxies.indices
        where (proxies[index]["type"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() == "tailscale" {
            guard let proxyName = proxies[index]["name"] as? String,
                  !proxyName.isEmpty else {
                throw ProfileExternalResourceError.invalidConfiguration
            }
            let proxyDigest = ProfileExternalResourceImporter.sha256(
                Data(proxyName.utf8)
            ).prefix(24)
            let stateDirectory = coreHomeDir
                .appendingPathComponent("store/\(profile.id)/runtime/tailscale/\(proxyDigest)",
                                      isDirectory: true)
            try fileManager.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
            proxies[index]["state-dir"] = stateDirectory.path
            edits.append(.proxy(index: index, name: proxyName, path: ["state-dir"], value: stateDirectory.path))
        }
        root["proxies"] = proxies
        let references = profile.externalResources ?? []
        let requirements = IOSExternalResourceCatalog.requirements(root: root)
        let stagingResources = candidate.stagingDirectory
            .appendingPathComponent("resources", isDirectory: true)
        let publishedResources = candidate.publishedDirectory
            .appendingPathComponent("resources", isDirectory: true)
        var createdResourcesDirectory = false

         
         
         
         
         
         
         
        func materializedPublicPath(
            for requirement: IOSExternalResourceRequirement
        ) throws -> String? {
            let valueDigest = ProfileExternalResourceImporter.sha256(
                Data(requirement.rawValue.utf8)
            )
            guard let reference = references.first(where: {
                $0.capabilityID == requirement.capability.id
                    && $0.proxy == requirement.proxyName
                    && $0.fieldPath == requirement.capability.fieldPath
                    && $0.sourceValueSHA256 == valueDigest
            }) else {
                return nil
            }
            let source = coreHomeDir
                .appendingPathComponent("store/\(profile.id)/resources/\(reference.storageKey)")
            guard let data = try? Data(contentsOf: source, options: [.mappedIfSafe]),
                  !data.isEmpty,
                  data.count <= ProfileExternalResourceImporter.maximumResourceBytes else {
                return nil
            }
            if !createdResourcesDirectory {
                try fileManager.createDirectory(
                    at: stagingResources,
                    withIntermediateDirectories: true
                )
                createdResourcesDirectory = true
            }
            try data.write(
                to: stagingResources.appendingPathComponent(reference.storageKey),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
            )
            return publishedResources.appendingPathComponent(reference.storageKey).path
        }

        for requirement in requirements {
            let field = requirement.capability.fieldPath.joined(separator: ".")
            if requirement.capability.section != .proxy {
                guard requirement.capability.disposition == .publicFileOrInline else {
                    continue
                }
                let key = requirement.capability.section == .proxyProvider
                    ? "proxy-providers"
                    : "rule-providers"
                guard var providers = root[key] as? [String: Any],
                      var provider = providers[requirement.proxyName] as? [String: Any]
                else { throw ProfileExternalResourceError.invalidConfiguration }
                if let path = try materializedPublicPath(for: requirement) {
                    provider["path"] = path
                    providers[requirement.proxyName] = provider
                    root[key] = providers
                    edits.append(.provider(section: key, name: requirement.proxyName, value: path))
                }
                continue
            }
            guard let index = proxies.firstIndex(where: {
                ($0["name"] as? String) == requirement.proxyName
            }) else { throw ProfileExternalResourceError.invalidConfiguration }
            var proxy: Any = proxies[index]

            switch requirement.capability.disposition {
            case .managedRuntimeState:
                let proxyDigest = ProfileExternalResourceImporter.sha256(
                    Data(requirement.proxyName.utf8)
                ).prefix(24)
                let stateDirectory = coreHomeDir
                    .appendingPathComponent("store/\(profile.id)/runtime/tailscale/\(proxyDigest)",
                                          isDirectory: true)
                try fileManager.createDirectory(
                    at: stateDirectory,
                    withIntermediateDirectories: true
                )
                guard IOSExternalResourceCatalog.set(
                    stateDirectory.path,
                    at: requirement.capability.fieldPath,
                    in: &proxy
                ) else { throw ProfileExternalResourceError.invalidConfiguration }
                edits.append(.proxy(index: index, name: requirement.proxyName,
                                    path: requirement.capability.fieldPath, value: stateDirectory.path))
            case .publicFileOrInline:
                if let path = try materializedPublicPath(for: requirement) {
                    guard IOSExternalResourceCatalog.set(
                        path,
                        at: requirement.capability.fieldPath,
                        in: &proxy
                    ) else { throw ProfileExternalResourceError.invalidConfiguration }
                    edits.append(.proxy(index: index, name: requirement.proxyName,
                                        path: requirement.capability.fieldPath, value: path))
                }
            case .secretFileOrInline, .secretInlineOnly, .fileProviderUnavailable, .bundleArchiveMember:
                 
                 
                break
            }
            guard let dictionary = proxy as? [String: Any] else {
                throw ProfileExternalResourceError.invalidConfiguration
            }
            proxies[index] = dictionary
        }

         
        guard !edits.isEmpty else { return yaml }
        return try ExternalResourceEdit.applying(edits, toYAML: yaml)
    }

    private static func source(for source: Profile.Source) -> IOSExternalResourceSource {
        switch source {
        case .url: return .subscription
        case .file: return .localFile
        case .clipboard: return .clipboard
        }
    }
}

 
 
 
 
 
 
fileprivate enum ExternalResourceEdit {
     
    case proxy(index: Int, name: String, path: [String], value: String)
     
    case provider(section: String, name: String, value: String)

    static func applying(_ edits: [ExternalResourceEdit], toYAML yaml: String) throws -> String {
        var tree = try OrderedJSON.parse(try ConfigTransforms.yamlToJSON(yaml))
        for edit in edits {
            switch edit {
            case let .proxy(index, name, path, value):
                guard case var .array(items)? = tree.topLevelValue("proxies"),
                      items.indices.contains(index),
                      items[index].topLevelValue("name") == .string(name),
                      let edited = items[index].settingExisting(path, to: .string(value))
                else { throw ProfileExternalResourceError.invalidConfiguration }
                items[index] = edited
                tree = tree.settingTopLevel("proxies", to: .array(items))
            case let .provider(section, name, value):
                guard case var .object(providers)? = tree.topLevelValue(section),
                      let at = providers.firstIndex(where: { $0.key == name }),
                      case .object = providers[at].value
                else { throw ProfileExternalResourceError.invalidConfiguration }
                providers[at].value = providers[at].value.settingTopLevel("path", to: .string(value))
                tree = tree.settingTopLevel(section, to: .object(providers))
            }
        }
        return try ConfigTransforms.jsonToYAML(tree.serialized())
    }
}

fileprivate extension OrderedJSON {
     
     
     
    func settingExisting(_ path: [String], to value: OrderedJSON) -> OrderedJSON? {
        guard let head = path.first, case .object = self else { return nil }
        if path.count == 1 { return settingTopLevel(head, to: value) }
        guard let child = topLevelValue(head),
              let edited = child.settingExisting(Array(path.dropFirst()), to: value) else { return nil }
        return settingTopLevel(head, to: edited)
    }
}
