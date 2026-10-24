#if os(iOS) || os(macOS)
import ClashClientKit
import ClashClientUI
import CryptoKit
import Foundation
import Security

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 

 
enum ModuleCertificateState: Equatable, Sendable {
    case notGenerated
    case notInstalled
     
     
    case installedNotTrusted
    case ready
}

 
 
enum ModuleCertificatePlatform: Equatable, Sendable {
    case ios
    case mac

    static var current: ModuleCertificatePlatform {
        #if os(macOS)
        return .mac
        #else
        return .ios
        #endif
    }
}

 
 
 
enum ModuleKeychainFallback: Equatable, Sendable {
    case install
    case trust
}

 
 
 
enum ModuleCertificateInstallOutcome: Equatable, Sendable {
    case trusted
     
     
    case cancelled
     
    case failed(ModuleKeychainFallback, status: OSStatus)

     
    var added: Bool {
        if case .failed(.install, _) = self { return false }
        return true
    }

     
    static func afterAdding(_ status: OSStatus) -> ModuleCertificateInstallOutcome? {
        status == errSecSuccess || status == errSecDuplicateItem ? nil : .failed(.install, status: status)
    }

     
     
    static func afterTrusting(_ status: OSStatus) -> ModuleCertificateInstallOutcome {
        switch status {
        case errSecSuccess: return .trusted
        case errSecUserCanceled, -60006: return .cancelled
        default: return .failed(.trust, status: status)
        }
    }
}

 
 
 
enum ModuleCertificateRemoval: Equatable, Sendable {
    case removed
     
    case cancelled
     
    case failed(status: OSStatus)

     
     
    static func afterRemovingTrust(_ status: OSStatus) -> ModuleCertificateRemoval? {
        switch status {
        case errSecSuccess, errSecItemNotFound: return nil
        case errSecUserCanceled, -60006: return .cancelled
        default: return .failed(status: status)
        }
    }

     
    static func afterDeleting(_ status: OSStatus) -> ModuleCertificateRemoval {
        status == errSecSuccess || status == errSecItemNotFound ? .removed : .failed(status: status)
    }
}

 
 
enum ModuleCertificateCopy {
    static func action(_ state: ModuleCertificateState, platform: ModuleCertificatePlatform) -> AuthoredText {
        switch (state, platform) {
        case (.notGenerated, _): return .app("Create Certificate")
        case (.notInstalled, _): return .app("Install Certificate")
         
         
         
         
         
        case (.installedNotTrusted, .ios): return .app("Download Again")
        case (.installedNotTrusted, .mac): return .app("Install Certificate")
        case (.ready, _): return .app("Make a New Certificate")
        }
    }

     
     
    static let openInKeychainAccess: AuthoredText = .app("Open in Keychain Access")

     
     
     
     
     
     
     
     
     
     
    static func steps(platform: ModuleCertificatePlatform, naming button: AuthoredText,
                      certificate name: String? = nil) -> [ClashDisplayText] {
        [stepOne(platform, naming: key(button)), stepTwo(platform, certificate: name)]
    }

     
     
     
     
     
     
    static func steps(_ state: ModuleCertificateState, platform: ModuleCertificatePlatform,
                      certificate name: String? = nil, fallback: ModuleKeychainFallback? = nil) -> [ClashDisplayText] {
        switch state {
        case .notGenerated, .ready: return []
        case .notInstalled, .installedNotTrusted:
            switch (platform, fallback) {
            case (.ios, _): return steps(platform: .ios, naming: action(state, platform: .ios), certificate: name)
            case (.mac, nil): return []
            case (.mac, .install?): return steps(platform: .mac, naming: openInKeychainAccess, certificate: name)
            case (.mac, .trust?): return [.format(macTrustStep, [name ?? ModuleCertificateAuthority.caCommonNamePrefix])]
            }
        }
    }

     
     
     
     
     
    static func steps(_ state: ModuleCertificateState, platform: ModuleCertificatePlatform, certificate name: String? = nil,
                      fallback: ModuleKeychainFallback? = nil, resolvedIn locale: Locale) -> [ClashDisplayText] {
        steps(state, platform: platform, certificate: name, fallback: fallback)
            .map { .verbatim(ClashCopy.string(for: $0, locale: locale)) }
    }

     
     
     
    static func pageSteps(platform: ModuleCertificatePlatform, certificate name: String? = nil) -> [ClashDisplayText] {
        let button = key(pageButton(platform: platform))
        switch platform {
        case .ios: return [stepOne(.ios, naming: button), stepTwo(.ios, certificate: name)]
        case .mac: return [.formatCopy(macPageStepOne, [button]), stepTwo(.mac, certificate: name)]
        }
    }

    private static func stepOne(_ platform: ModuleCertificatePlatform) -> String {
        switch platform {
        case .ios: return "Step 1: Tap %@ and allow the download, then install %@ in Settings > General > VPN & Device Management."
        case .mac: return "Step 1: Click %@, choose login, then click Add."
        }
    }

     
    private static func stepOne(_ platform: ModuleCertificatePlatform, naming button: String) -> ClashDisplayText {
        switch platform {
        case .ios: return .formatCopy(stepOne(.ios), [button, key(pageTitle)])
        case .mac: return .formatCopy(stepOne(.mac), [button])
        }
    }

    private static let macPageStepOne = "Step 1: Click %@, open the downloaded certificate, choose login, then click Add."

     
     
     
    private static func stepTwoRow(_ platform: ModuleCertificatePlatform) -> String {
        switch platform {
        case .ios: return "Step 2: In Settings > General > About > Certificate Trust Settings, turn on %@."
        case .mac: return "Step 2: Click Certificates, double-click %@, choose Always Trust under Trust, then enter your Mac password."
        }
    }

     
     
    private static let macTrustStep =
        "Click Open in Keychain Access, then Certificates, double-click %@, choose Always Trust under Trust, then enter your Mac password."

    private static func stepTwo(_ platform: ModuleCertificatePlatform, certificate name: String?) -> ClashDisplayText {
        .format(stepTwoRow(platform), [name ?? ModuleCertificateAuthority.caCommonNamePrefix])
    }

     
     
     
    static func deleteOldCertificate(_ name: String) -> AuthoredText {
        .app(deleteOldCertificateRow, arguments: [name])
    }

    private static let deleteOldCertificateRow = "Open Keychain Access, click Certificates, then delete the old certificate %@."

    private static func key(_ text: AuthoredText) -> String {
        switch text {
        case .app(let key, _): return key
        case .verbatim(let text): return text
        }
    }

     
     
     
    static func regenerateWarning(platform: ModuleCertificatePlatform) -> AuthoredText {
        .app("The old certificate stops working. After making the new one, install and trust the new one.")
    }

    static let profileDescription: AuthoredText = .app("Lets Clash's modules work fully on this device.")
     
    static let pageTitle: AuthoredText = .app("Clash Module Certificate")
    static let pageFooter: AuthoredText = .app("This page comes from Clash on this device.")

    static func pageButton(platform: ModuleCertificatePlatform) -> AuthoredText {
        platform == .ios ? .app("Download the Profile") : .app("Download the Certificate")
    }

     
    static var every: [AuthoredText] {
        let states: [ModuleCertificateState] = [.notGenerated, .notInstalled, .installedNotTrusted, .ready]
        let platforms: [ModuleCertificatePlatform] = [.ios, .mac]
        return platforms.flatMap { platform in
            states.map { action($0, platform: platform) }
                + [.app(stepOne(platform)), .app(stepTwoRow(platform)), regenerateWarning(platform: platform), pageButton(platform: platform)]
        } + [.app(macPageStepOne), .app(macTrustStep), .app(deleteOldCertificateRow), openInKeychainAccess, profileDescription, pageTitle, pageFooter]
    }
}

protocol ModuleTrustEvaluating: Sendable {
    func isTrusted(leafDER: Data, caDER: Data, hostname: String) -> Bool
}

 
 
 
 
struct ModuleSystemTrust: ModuleTrustEvaluating {
    init() {}

    func isTrusted(leafDER: Data, caDER: Data, hostname: String) -> Bool {


        guard let leaf = SecCertificateCreateWithData(nil, leafDER as CFData),
              let ca = SecCertificateCreateWithData(nil, caDER as CFData) else { return false }
        var trust: SecTrust?
        guard SecTrustCreateWithCertificates([leaf, ca] as CFArray, SecPolicyCreateSSL(true, hostname as CFString), &trust) == errSecSuccess,
              let trust else { return false }
        SecTrustSetNetworkFetchAllowed(trust, false)
        return SecTrustEvaluateWithError(trust, nil)
    }
}

enum ModuleCertificateProfile {
     
     
    static let identifier = "org.example.canto.adblock.ca"

     
     
     
    static func mobileconfig(caDER: Data, fingerprint: String, commonName: String, displayName: String,
                             description: String) throws -> Data {
        let plist: [String: Any] = [
            "PayloadContent": [[
                "PayloadCertificateFileName": ModuleEngineLocations.certificateFileName,
                "PayloadContent": caDER,
                "PayloadDescription": description,
                "PayloadDisplayName": commonName,
                "PayloadIdentifier": identifier + ".root",
                "PayloadType": "com.apple.security.root",
                "PayloadUUID": uuid(fingerprint, salt: "payload"),
                "PayloadVersion": 1,
            ]],
            "PayloadDescription": description,
            "PayloadDisplayName": displayName,
            "PayloadIdentifier": identifier,
            "PayloadRemovalDisallowed": false,
            "PayloadType": "Configuration",
            "PayloadUUID": uuid(fingerprint, salt: "profile"),
            "PayloadVersion": 1,
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

     
    static func uuid(_ fingerprint: String, salt: String) -> String {
        var bytes = Array(SHA256.hash(data: Data((salt + fingerprint).utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return bytes.withUnsafeBufferPointer { NSUUID(uuidBytes: $0.baseAddress).uuidString }
    }
}

enum ModuleCertificatePageBuilder {
     
     
     
     
     
     
     
    static func html(platform: ModuleCertificatePlatform, locale: Locale, certificate name: String? = nil,
                     link given: String? = nil, downloadsAtOnce: Bool = false) -> Data {
        func text(_ display: ClashDisplayText) -> String {
            ClashCopy.string(for: display, locale: locale)
                .replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        let link = given ?? (platform == .ios ? ModuleEngineLocations.certificateProfilePath : ModuleEngineLocations.certificateFilePath)
        let steps = ModuleCertificateCopy.pageSteps(platform: platform, certificate: name).map { "<p>\(text($0))</p>" }.joined()
        let title = text(ModuleCertificateCopy.pageTitle.displayText)
        let button = text(ModuleCertificateCopy.pageButton(platform: platform).displayText)
        let footer = text(ModuleCertificateCopy.pageFooter.displayText)
         
        let refresh = downloadsAtOnce ? "<meta http-equiv=\"refresh\" content=\"0;url=\(link)\">" : ""
        let page = #"""
        <!doctype html>
        <html lang="\#(language(of: locale))"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">\#(refresh)
        <title>\#(title)</title>
        <style>
        body { font: 17px -apple-system, system-ui, sans-serif; margin: 0 auto; max-width: 34em; padding: 24px 16px; color: #1c1c1e; background: #ffffff; }
        @media (prefers-color-scheme: dark) { body { color: #f2f2f7; background: #000000; } }
        a.button { display: block; text-align: center; padding: 14px; border-radius: 12px; background: #0a84ff; color: #ffffff; text-decoration: none; font-weight: 600; margin: 24px 0; }
        p { margin: 12px 0; } small { color: #8e8e93; }
        </style></head>
        <body><h1>\#(title)</h1>
        <a class="button" href="\#(link)">\#(button)</a>
        \#(steps)
        <small>\#(footer)</small></body></html>
        """#
        return Data(page.utf8)
    }

     
     
     
    static func language(of locale: Locale) -> String {
        var candidate = locale.identifier.replacingOccurrences(of: "_", with: "-")
        while !candidate.isEmpty {
            if Bundle.main.path(forResource: candidate, ofType: "lproj") != nil { return candidate }
            guard let cut = candidate.lastIndex(of: "-") else { break }
            candidate = String(candidate[candidate.startIndex..<cut])
        }
        return Bundle.main.preferredLocalizations.first ?? "en"
    }
}

 
 
 
struct ModuleCertificateUnavailable: Error, Equatable {
    let reason: String
}

 
struct ModuleCertificateHandOut: Sendable {
    let profile: Data
     
    let commonName: String
     
    let page: @Sendable (_ profilePath: String) -> Data
}

final class ModuleCertificateStore: @unchecked Sendable {
    static let trustProbeHost = "trust-check.cert.clash"

    private struct Export: Codable {
        let fingerprintSHA256: String
        let at: Date
    }

     
     
    private struct Retired: Codable {
        var certificates: [Data]
    }

    let locations: ModuleEngineLocations
    private let issuer: ModuleCertificateIssuing
    private let trust: ModuleTrustEvaluating
    private let now: () -> Date
    private let platform: ModuleCertificatePlatform
    private let locale: () -> Locale
    private let log: (String) -> Void

     
     
    private static let lock = NSLock()
     
     
    private static var probe: (fingerprint: String, leafDER: Data)?

    init(locations: ModuleEngineLocations, issuer: ModuleCertificateIssuing = ModuleSwiftCertificatesIssuer(),
         trust: ModuleTrustEvaluating = ModuleSystemTrust(), now: @escaping () -> Date = Date.init,
         platform: ModuleCertificatePlatform = .current, locale: @escaping () -> Locale = { AppPreferences.language().locale },
         log: @escaping (String) -> Void = { ClashLogStore.shared.append($0, stream: .app) }) {
        self.locations = locations
        self.issuer = issuer
        self.trust = trust
        self.now = now
        self.platform = platform
        self.locale = locale
        self.log = log
    }

     
    static let production: ModuleCertificateStore? = ModuleEngineLocations.production.map { ModuleCertificateStore(locations: $0) }

    private var exportRecord: URL { locations.certificateDirectory.appendingPathComponent("exported.json") }
    private var retiredRecord: URL { locations.certificateDirectory.appendingPathComponent("retired.json") }
     
    private var pageLanguageRecord: URL { locations.certificateDirectory.appendingPathComponent("page-language") }

     
    func metadata() -> ModuleCAMetadata? {
        guard case .ready(_, let metadata) = ModuleCAFiles.status(locations) else { return nil }
        return metadata
    }

     
     
     
     
     
     
    @discardableResult
    func ensureCertificate() throws -> ModuleCAMetadata {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        switch ModuleCAFiles.status(locations) {
        case .ready(let material, let metadata):
            try writeServedFiles(caDER: material.certificateDER, metadata: metadata)
            return metadata
        case .unavailable(let why):
            log(#"the modules' CA could not be read just now (\#(why)): nothing was made, nothing changed"#)
            throw ModuleCertificateUnavailable(reason: why)
        case .absent:
            let made = try makeLocked()
            log(#"a new modules' CA \#(made.commonName) \#(made.fingerprintSHA256) was made"#)
            return made
        case .needsRegeneration(let why):
            let made = try makeLocked()
            log(#"the modules' CA files are not one CA (\#(why)): a new CA \#(made.commonName) \#(made.fingerprintSHA256) was made"#)
            return made
        }
    }

     
     
     
     
     
    @discardableResult
    func ensureCertificate(republishing modules: ModuleStore) async throws -> ModuleCAMetadata {
        let metadata = try ensureCertificate()
        if let published = await modules.publishedGlobalManifest(), published.caFingerprintSHA256 != metadata.fingerprintSHA256 {
            try await modules.republish()
        }
        return metadata
    }

     
     
     
     
     
     
    @discardableResult
    func regenerate(republishing modules: ModuleStore) async throws -> ModuleCAMetadata {
        let made: ModuleCAMetadata = try {
            Self.lock.lock()
            defer { Self.lock.unlock() }
            let old: String
            switch ModuleCAFiles.status(locations) {
            case .ready(_, let metadata): old = metadata.commonName + " " + metadata.fingerprintSHA256
            case .absent: old = #"none"#
            case .needsRegeneration(let why), .unavailable(let why): old = #"one that could not be used (\#(why))"#
            }
             
             
            let replaced = platform == .mac ? ModuleEngineFiles.data(from: locations.caCertificate, maximumBytes: 64 << 10) : nil
            let made = try makeLocked()
            log(#"a new modules' CA \#(made.commonName) \#(made.fingerprintSHA256) was made on request, in place of \#(old)"#)
            if let replaced, SecCertificateCreateWithData(nil, replaced as CFData) != nil {
                writeRetiredLocked(readRetiredLocked().filter { $0 != replaced } + [replaced])
            }
            return made
        }()
        if await modules.publishedGlobalManifest() != nil { try await modules.republish() }
        return made
    }

     
     
    func retiredCertificates() -> [Data] {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        return readRetiredLocked()
    }

     
    func forgetRetired(_ certificateDER: Data) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        writeRetiredLocked(readRetiredLocked().filter { $0 != certificateDER })
    }

     
    static func commonName(_ certificateDER: Data) -> String? {
        SecCertificateCreateWithData(nil, certificateDER as CFData).flatMap { SecCertificateCopySubjectSummary($0) as String? }
    }

     
     
    func isTrusted() -> Bool {
        guard case .ready(let material, let metadata) = ModuleCAFiles.status(locations) else { return false }
        return isTrusted(material, fingerprint: metadata.fingerprintSHA256)
    }

     
     
     
     
    func state(report: ModuleEngineReport?) -> ModuleCertificateState {
        guard case .ready(let material, let metadata) = ModuleCAFiles.status(locations) else { return .notGenerated }
        if isTrusted(material, fingerprint: metadata.fingerprintSHA256) { return .ready }
        let exported = ModuleEngineFiles.read(Export.self, from: exportRecord)?.fingerprintSHA256 == metadata.fingerprintSHA256
        let handedOut = report?.certificateServedAt[metadata.fingerprintSHA256] != nil
        return exported || handedOut ? .installedNotTrusted : .notInstalled
    }

     
     
    func exportFile() throws -> URL {
        try ensureCertificate()
        return platform == .ios ? locations.certificateProfile : locations.certificateFile
    }

     
    func noteExported() {
        guard let metadata = metadata(),
              let data = try? ModuleJSON.encoder().encode(Export(fingerprintSHA256: metadata.fingerprintSHA256, at: now()))
        else { return }
        try? ModuleEngineFiles.write(data, to: exportRecord)
    }

     
     
     
     
     
     
    func handOut() throws -> ModuleCertificateHandOut {
        guard let metadata = metadata(),
              let profile = ModuleEngineFiles.data(from: locations.certificateProfile, maximumBytes: 64 * 1024) else {
            throw ModuleCertificateUnavailable(reason: #"no profile to hand out"#)
        }
        let platform = self.platform, locale = self.locale(), name = metadata.commonName
        return ModuleCertificateHandOut(profile: profile, commonName: name) { path in
            ModuleCertificatePageBuilder.html(platform: platform, locale: locale, certificate: name, link: path, downloadsAtOnce: true)
        }
    }

     

     
     
     
    @discardableResult
    func rewriteForTheLanguage() -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let language = locale().identifier
        guard ModuleEngineFiles.data(from: pageLanguageRecord, maximumBytes: 256).map({ String(decoding: $0, as: UTF8.self) }) != language,
              case .ready(let material, let metadata) = ModuleCAFiles.status(locations) else { return false }
        do {
            try writeServedFiles(caDER: material.certificateDER, metadata: metadata)
            return true
        } catch {
            log(#"the modules' certificate page could not be rewritten in \#(language) (\#(error))"#)
            return false
        }
    }

    private static let following: Void = {
        NotificationCenter.default.addObserver(forName: NSLocale.currentLocaleDidChangeNotification, object: nil, queue: nil) { _ in
            languageChanged()
        }
    }()

     
     
    static func followTheLanguage() {
        _ = following
        languageChanged()
    }

     
    static func languageChanged() {


        DispatchQueue.global(qos: .utility).async { production?.rewriteForTheLanguage() }
    }

    private func isTrusted(_ material: ModuleCAMaterial, fingerprint: String) -> Bool {
        guard let leaf = probeLeaf(material, fingerprint: fingerprint) else { return false }
        return trust.isTrusted(leafDER: leaf, caDER: material.certificateDER, hostname: Self.trustProbeHost)
    }

    private func probeLeaf(_ material: ModuleCAMaterial, fingerprint: String) -> Data? {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        if let probe = Self.probe, probe.fingerprint == fingerprint { return probe.leafDER }
        guard let leaf = try? issuer.issueLeaf(hostname: Self.trustProbeHost, ca: material, now: now()) else { return nil }
        Self.probe = (fingerprint, leaf.certificateDER)
        return leaf.certificateDER
    }

     

    private func makeLocked() throws -> ModuleCAMetadata {
        let made = now()
        let ca = try issuer.makeCA(now: made)
         
        try ModuleCAFiles.write(ca, createdAt: made, to: locations, log: log)
        var directory = locations.certificateDirectory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? directory.setResourceValues(values)
         
         
        switch ModuleCAFiles.status(locations) {
        case .ready(_, let metadata):
            try writeServedFiles(caDER: ca.certificateDER, metadata: metadata)
            return metadata
        case .absent: throw ModuleCertificateUnavailable(reason: #"the CA just written is not there"#)
        case .needsRegeneration(let why), .unavailable(let why): throw ModuleCertificateUnavailable(reason: why)
        }
    }

    private func readRetiredLocked() -> [Data] {
        ModuleEngineFiles.read(Retired.self, from: retiredRecord)?.certificates ?? []
    }

    private func writeRetiredLocked(_ certificates: [Data]) {
        do {
            if certificates.isEmpty {
                if FileManager.default.fileExists(atPath: retiredRecord.path) { try FileManager.default.removeItem(at: retiredRecord) }
            } else {
                try ModuleEngineFiles.write(try ModuleJSON.encoder().encode(Retired(certificates: certificates)), to: retiredRecord)
            }
        } catch {
            log(#"the modules' retired certificates could not be noted (\#(error))"#)
        }
    }

    private func writeServedFiles(caDER: Data, metadata: ModuleCAMetadata) throws {
        let locale = self.locale()
        try writeIfChanged(ModuleCertificatePageBuilder.html(platform: platform, locale: locale, certificate: metadata.commonName),
                           to: locations.certificatePage)
        try writeIfChanged(caDER, to: locations.certificateFile)
        if platform == .ios {
            let profile = try ModuleCertificateProfile.mobileconfig(
                caDER: caDER, fingerprint: metadata.fingerprintSHA256, commonName: metadata.commonName,
                displayName: ClashCopy.string(for: ModuleCertificateCopy.pageTitle.displayText, locale: locale),
                description: ClashCopy.string(for: ModuleCertificateCopy.profileDescription.displayText, locale: locale))
            try writeIfChanged(profile, to: locations.certificateProfile)
        }
        try writeIfChanged(Data(locale.identifier.utf8), to: pageLanguageRecord)
    }

    private func writeIfChanged(_ data: Data, to url: URL) throws {
        if let current = ModuleEngineFiles.data(from: url, maximumBytes: data.count), current == data { return }
        try ModuleEngineFiles.write(data, to: url)
    }
}
#endif
