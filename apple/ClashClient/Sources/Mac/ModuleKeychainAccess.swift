#if os(macOS)
import AppKit
import Security

 
 
 
 
 
 
 
 
enum ModuleKeychainAccess {
    static let bundleIdentifier = "com.apple.keychainaccess"

     
     
     
     
     
     
    static func installAndTrust(_ certificateDER: Data) -> ModuleCertificateInstallOutcome {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else {
            return .failed(.install, status: errSecDecode)
        }
        let add: [String: Any] = [kSecClass as String: kSecClassCertificate, kSecValueRef as String: certificate]
        if let stopped = ModuleCertificateInstallOutcome.afterAdding(SecItemAdd(add as CFDictionary, nil)) { return stopped }
        return ModuleCertificateInstallOutcome.afterTrusting(SecTrustSettingsSetTrustSettings(certificate, .user, nil))
    }

     
     
     
     
     
     
    static func remove(_ certificateDER: Data) -> ModuleCertificateRemoval {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let certificate = SecCertificateCreateWithData(nil, certificateDER as CFData) else { return .removed }
        if isTrusted(certificate),
           let stopped = ModuleCertificateRemoval.afterRemovingTrust(SecTrustSettingsRemoveTrustSettings(certificate, .user)) {
            return stopped
        }
        for copy in copies(of: certificateDER) {
            let delete: [String: Any] = [kSecClass as String: kSecClassCertificate, kSecValueRef as String: copy]
            let deleted = ModuleCertificateRemoval.afterDeleting(SecItemDelete(delete as CFDictionary))
            if deleted != .removed { return deleted }
        }
        return .removed
    }

     
     
    static func isInKeychain(_ certificateDER: Data) -> Bool {
        !copies(of: certificateDER).isEmpty
    }

    private static func isTrusted(_ certificate: SecCertificate) -> Bool {
        var settings: CFArray?
        return SecTrustSettingsCopyTrustSettings(certificate, .user, &settings) == errSecSuccess
    }

     
     
     
    private static func copies(of certificateDER: Data) -> [SecCertificate] {
        let query: [String: Any] = [kSecClass as String: kSecClassCertificate, kSecMatchLimit as String: kSecMatchLimitAll,
                                    kSecReturnRef as String: true]
        var found: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess, let items = found as? [SecCertificate] else { return [] }
        return items.filter { SecCertificateCopyData($0) as Data == certificateDER }
    }

     
    static func openApplication() {
        let workspace = NSWorkspace.shared
        guard let keychainAccess = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.openApplication(at: keychainAccess, configuration: configuration) { _, error in
            guard let error else { return }
            ClashLogStore.shared.append("modules: Keychain Access did not open: \(error.localizedDescription)", stream: .app)
        }
    }

    static func open(_ file: URL) {
        let workspace = NSWorkspace.shared
        guard let keychainAccess = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
             
            workspace.activateFileViewerSelecting([file])
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        workspace.open([file], withApplicationAt: keychainAccess, configuration: configuration) { _, error in
            guard let error else { return }
            ClashLogStore.shared.append("modules: Keychain Access did not open \(file.path): \(error.localizedDescription)", stream: .app)
            DispatchQueue.main.async { workspace.activateFileViewerSelecting([file]) }
        }
    }
}
#endif
