#if os(iOS) || os(macOS)
import ClashClientKit
import ClashClientUI
import Foundation

 
 
 
 
 
 

extension ModuleCertificateError {
    var authoredText: AuthoredText {
        switch self {
         
         
        case .invalidHostname(let host):
            return .app("%@ isn't affected by modules.", arguments: [host])
        case .encryptionFailed, .pkcs12ImportFailed, .noIdentity, .keyRejected, .keychain:
            return .app("The certificate wasn't created; try again.")
        }
    }
}

extension ModuleCertificateError: ClashAuthoredError {
    var displayText: ClashDisplayText { authoredText.displayText }
}

 
 
extension ModuleCertificateUnavailable: ClashAuthoredError {
    var displayText: ClashDisplayText { AuthoredText.app("The certificate wasn't created; try again.").displayText }
}
#endif
