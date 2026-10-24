#if os(iOS) || os(macOS)
import CryptoKit
import Foundation
import Security

 
 
 
 
 
 
 
 
 

 
 
final class ModuleIdentityLease {
    let hostname: String
     
     
    var identity: SecIdentity? { lock.lock(); defer { lock.unlock() }; return held }
    private let lock = NSLock()
    private var held: SecIdentity?
    private var release: (() -> Void)?

    fileprivate init(hostname: String, identity: SecIdentity, release: @escaping () -> Void) {
        self.hostname = hostname
        self.held = identity
        self.release = release
    }

    func end() {
        lock.lock()
        let pending = release
        release = nil
        held = nil
        lock.unlock()
        pending?()
    }

    deinit {
        release?()
    }
}

enum ModuleLeafStoreError: Error, Equatable {
     
     
     
    case unusableFingerprint(String)
}

final class ModuleLeafStore {
     
    static let resignAfter: TimeInterval = 30 * 86_400

     
     
     
    static let defaultMaximumFiles = 1024

     
    static let maximumFileBytes = 64 * 1024

     
     
     
     
     
    static let passingFailureLimit = 3
    static let passingFailureWindow: TimeInterval = 600

     
     
     
     
    static var defaultKeptAfterRelease: Int { ModuleIdentity.usesKeychainRoute ? 16 : 0 }

     
     
     
     
    static let writeOptions: Data.WritingOptions = ModuleEngineFiles.writeOptions

     
     
     
     
     
     
     
     
     

    let directory: URL
    let caFingerprint: String
    private let ca: ModuleCAMaterial
    private let issuer: ModuleCertificateIssuing
    private let now: () -> Date
    private let makeIdentity: (ModuleLeafMaterial) throws -> SecIdentity
    private let maximumFiles: Int
    private let keychain: ModuleKeychainLedger
    private let keptAfterRelease: Int
    private let log: (String) -> Void
    private let lock = NSLock()
    private var live: [String: (identity: SecIdentity, leases: Int)] = [:]
     
    private var kept: [(host: String, identity: SecIdentity)] = []
    private var knownFileCount: Int?
    private var issued = 0
    private var readFromDisk = 0
    private var made = 0
    private var writeFailures = 0
     
    private var passingFailures: [String: Date] = [:]

     
     
     
    init(directory: URL, ca: ModuleCAMaterial, caFingerprint: String,
         issuer: ModuleCertificateIssuing = ModuleSwiftCertificatesIssuer(), now: @escaping () -> Date = Date.init,
         makeIdentity: @escaping (ModuleLeafMaterial) throws -> SecIdentity = ModuleIdentity.make,
         maximumFiles: Int = ModuleLeafStore.defaultMaximumFiles,
         keychain: ModuleKeychainLedger = .process,
         keptAfterRelease: Int = ModuleLeafStore.defaultKeptAfterRelease,
         log: @escaping (String) -> Void = { _ in }) throws {
        guard caFingerprint.count >= 16, caFingerprint.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
            throw ModuleLeafStoreError.unusableFingerprint(caFingerprint)
        }
        self.directory = directory
        self.ca = ca
        self.caFingerprint = caFingerprint
        self.issuer = issuer
        self.now = now
        self.makeIdentity = makeIdentity
        self.maximumFiles = max(1, maximumFiles)
        self.keychain = keychain
        self.keptAfterRelease = max(0, keptAfterRelease)
        self.log = log
    }

     
    static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("adblock-leaves", isDirectory: true)
    }

     
     
    static func normalized(_ hostname: String) -> String {
        var host = hostname.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        return host
    }

    static func fileName(caFingerprint: String, hostname: String) -> String {
        let hostHash = SHA256.hash(data: Data(normalized(hostname).utf8)).prefix(8)
            .map { String(format: "%02x", $0) }.joined()
        return "\(caFingerprint.prefix(16))_\(hostHash).leaf"
    }

     
     
     
    static func refusesOnlyThisHost(_ error: Error) -> Bool {
        ModuleCertificateError.scope(of: error) == .thisHost
    }

    var activeIdentityCount: Int { locked { live.count } }
     
    var keptIdentityCount: Int { locked { kept.count } }
    var issuedCount: Int { locked { issued } }
    var readFromDiskCount: Int { locked { readFromDisk } }
     
    var madeIdentityCount: Int { locked { made } }
     
     
    var writeFailureCount: Int { locked { writeFailures } }

     
     
     
    var passingFailuresDegrade: Bool {
        locked { passingFailures.count >= Self.passingFailureLimit }
    }

    func lease(hostname: String) throws -> ModuleIdentityLease {
        let host = Self.normalized(hostname)
        return try locked {
            keychain.noteLease()
            if let entry = live[host] {
                live[host] = (entry.identity, entry.leases + 1)
                return makeLease(host, entry.identity)
            }
            if let index = kept.firstIndex(where: { $0.host == host }) {
                let identity = kept.remove(at: index).identity
                live[host] = (identity, 1)
                return makeLease(host, identity)
            }
            let identity: SecIdentity
            do {
                identity = try loadOrIssue(host)
            } catch {
                if ModuleCertificateError.scope(of: error) == .passing {
                    let at = now()
                    passingFailures = passingFailures.filter { at.timeIntervalSince($0.value) < Self.passingFailureWindow }
                    passingFailures[host] = at
                }
                throw error
            }
            passingFailures = [:]
            live[host] = (identity, 1)
            return makeLease(host, identity)
        }
    }

     
     
     
     
     
     
     
     
     
     
     
    @discardableResult
    func sweepOtherCAs() -> ModuleKeychainSweepOutcome {
        let prefix = "\(caFingerprint.prefix(16))_"
        return locked {
            for name in (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [] where !name.hasPrefix(prefix) {
                try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))
            }
            knownFileCount = nil
            trimIfNeeded()
            return keychain.sweepIfNoLease()
        }
    }

    private func locked<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func makeLease(_ host: String, _ identity: SecIdentity) -> ModuleIdentityLease {
        ModuleIdentityLease(hostname: host, identity: identity) { [weak self] in self?.releaseOne(host) }
    }

    private func releaseOne(_ host: String) {
        locked {
            guard let entry = live[host] else { return }
            guard entry.leases <= 1 else {
                live[host] = (entry.identity, entry.leases - 1)
                return
            }
            live[host] = nil
            guard keptAfterRelease > 0 else { return }
            kept.append((host, entry.identity))
            if kept.count > keptAfterRelease { kept.removeFirst(kept.count - keptAfterRelease) }
        }
    }

     
    private func identityOf(_ material: ModuleLeafMaterial) throws -> SecIdentity {
        defer { keychain.takeLeftBehind().forEach { log("leaf \(material.hostname): \($0)") } }
        let identity = try makeIdentity(material)
        made += 1
        return identity
    }

    private func loadOrIssue(_ host: String) throws -> SecIdentity {
        let file = directory.appendingPathComponent(Self.fileName(caFingerprint: caFingerprint, hostname: host))
        if let material = read(file, host: host) {
            do {
                let identity = try identityOf(material)
                readFromDisk += 1
                return identity
            } catch ModuleCertificateError.keychain(let status) {
                 
                 
                throw ModuleCertificateError.keychain(status)
            } catch {
                 
                 
            }
        }
        let material = try issuer.issueLeaf(hostname: host, ca: ca, now: now())
        issued += 1
        let identity = try identityOf(material)
        write(material, to: file)
        return identity
    }

     
     
     
     
    private func read(_ file: URL, host: String) -> ModuleLeafMaterial? {
        let at = now()
        guard let modified = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
              at.timeIntervalSince(modified) < Self.resignAfter,
              let handle = try? FileHandle(forReadingFrom: file) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: Self.maximumFileBytes + 1), data.count <= Self.maximumFileBytes,
              let material = try? PropertyListDecoder().decode(ModuleLeafMaterial.self, from: data),
              material.hostname == host,
              material.issuedAt.timeIntervalSince(at) <= ModuleCertificateAuthority.clockSkewAllowance,
              at.timeIntervalSince(material.issuedAt) < Self.resignAfter,
              material.notAfter.timeIntervalSince(at) > Self.resignAfter else { return nil }
        return material
    }

    private func write(_ material: ModuleLeafMaterial, to file: URL) {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(material) else { writeFailures += 1; return }
        let manager = FileManager.default
         
        try? manager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var excluded = URLResourceValues()
        excluded.isExcludedFromBackup = true
        var directoryURL = directory
        try? directoryURL.setResourceValues(excluded)
         
         
        let temporary = directory.appendingPathComponent(UUID().uuidString + ".tmp")
        let existed = manager.fileExists(atPath: file.path)
        guard (try? ModulePrivateFile.create(data, at: temporary)) != nil, Darwin.rename(temporary.path, file.path) == 0 else {
            try? manager.removeItem(at: temporary)
            writeFailures += 1
            return
        }
        if !existed, let count = knownFileCount { knownFileCount = count + 1 }
        trimIfNeeded()
    }

     
     
     
    private func trimIfNeeded() {
        if let count = knownFileCount, count <= maximumFiles { return }
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: keys)) ?? []
        let files = urls.filter { $0.pathExtension == "leaf" }.map {
            (url: $0, modified: (try? $0.resourceValues(forKeys: Set(keys)).contentModificationDate) ?? Date.distantPast)
        }
        guard files.count > maximumFiles else { knownFileCount = files.count; return }
        let target = max(1, maximumFiles * 3 / 4)
        var remaining = files.count
        for entry in files.sorted(by: { $0.modified < $1.modified }).dropLast(target) {
            if (try? FileManager.default.removeItem(at: entry.url)) != nil { remaining -= 1 }
        }
        knownFileCount = remaining
    }
}
#endif
