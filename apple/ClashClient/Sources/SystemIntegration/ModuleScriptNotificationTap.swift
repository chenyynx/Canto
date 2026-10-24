#if os(iOS) || os(macOS)
import Foundation
import UserNotifications

 
 
 
 
 
 
 
struct ModuleScriptNotificationTap: Equatable {
     
    enum Refusal: Equatable {
        case notALink(String)
        case file(String)
    }

    var scriptName: String
     
    var copy: String?
     
    var open: URL?
    var refusal: Refusal?

     
    init?(_ tap: ClashNotificationTap) {
        guard tap.action == UNNotificationDefaultActionIdentifier else { return nil }
        scriptName = tap.info[#"scriptName"#] ?? #""#
        copy = tap.info[#"clipboardText"#].flatMap { $0.isEmpty ? nil : $0 }
        guard let written = tap.info[#"openURL"#], !written.isEmpty else { return }
        guard let url = URL(string: written), let scheme = url.scheme, !scheme.isEmpty else {
            refusal = .notALink(written)
            return
        }
        guard !url.isFileURL, scheme.lowercased() != #"file"# else {
            refusal = .file(written)
            return
        }
        open = url
    }

     
    var refusalLine: String? {
        switch refusal {
        case .notALink(let written)?:
            return #"module script notification from \#(scriptName): its link "\#(written)" is not one; not opened"#
        case .file(let written)?:
            return #"module script notification from \#(scriptName): its link "\#(written)" is a file; not opened"#
        case nil:
            return nil
        }
    }
}
#endif
