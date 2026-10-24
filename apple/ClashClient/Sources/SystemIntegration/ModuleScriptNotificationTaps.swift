#if os(iOS)
import Foundation
import UIKit
import UserNotifications

 
 
 
 
 
 
 
 
 
@MainActor
enum ModuleScriptNotificationTaps {
     
     
     
     
     
     
    struct Reading: Equatable, Sendable {
        var clipboardText: String?
        var openURL: URL?
         
        var refusals: [String] = []
    }

    static func register(
        on delegate: ClashNotificationCenterDelegate = .shared,
        read: @escaping @MainActor (ClashNotificationTap) -> Reading = minimalRead,
        copy: @escaping @MainActor (String) -> Void = { UIPasteboard.general.string = $0 },
        open: @escaping @MainActor (URL) -> Void = { UIApplication.shared.open($0) },
        log: @escaping @MainActor (String) -> Void = { ClashLogStore.shared.append($0, stream: .app, level: .info) }
    ) {
        delegate.register(kind: ModuleScriptNotificationPoster.kind) { tap in
            answer(tap, read: read, copy: copy, open: open, log: log)
        }
    }

    static func answer(
        _ tap: ClashNotificationTap,
        read: @MainActor (ClashNotificationTap) -> Reading,
        copy: @MainActor (String) -> Void,
        open: @MainActor (URL) -> Void,
        log: @MainActor (String) -> Void
    ) {
        guard tap.action == UNNotificationDefaultActionIdentifier else { return }
        let reading = read(tap)
        reading.refusals.forEach(log)
         
         
        if let text = reading.clipboardText { copy(text) }
        if let url = reading.openURL { open(url) }
    }

     
    static func minimalRead(_ tap: ClashNotificationTap) -> Reading {
        var reading = Reading(clipboardText: tap.info["clipboardText"].flatMap { $0.isEmpty ? nil : $0 })
        guard let written = tap.info["openURL"]?.trimmingCharacters(in: .whitespacesAndNewlines), !written.isEmpty else {
            return reading
        }
        let name = tap.info["scriptName"] ?? ""
        guard let url = URL(string: written), let scheme = url.scheme, !scheme.isEmpty else {
            reading.refusals.append(#"module script \#(name): its notification's link \#(written) does not read as a link; not opened"#)
            return reading
        }
        guard scheme.lowercased() != "file" else {
            reading.refusals.append(#"module script \#(name): its notification's link \#(written) is a file link; not opened"#)
            return reading
        }
        reading.openURL = url
        return reading
    }
}
#endif
