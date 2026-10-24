import AppKit
import Foundation
import UserNotifications

 
 
 
 
 
 
 
 
 
@MainActor
enum ClashMacScriptNotifications {
     
    struct Actions {
        var open: (URL) -> Void
        var copy: (String) -> Void
        var log: (String) -> Void

        static let system = Actions(
            open: { NSWorkspace.shared.open($0) },
            copy: { text in
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            },
            log: { ClashLogStore.shared.append($0, stream: .app, level: .info) }
        )
    }

     
     
     
     
    static func start(
        delegate: ClashNotificationCenterDelegate = .shared,
        actions: Actions = .system,
        startRelay: () -> Void = { ModuleScriptNotificationRelay.shared.start() }
    ) {
        delegate.register(kind: ModuleScriptNotificationPoster.kind) { tap in handle(tap, actions) }
        startRelay()
    }

     
     
     
    static func handle(_ tap: ClashNotificationTap, _ actions: Actions) {
        guard let asked = ModuleScriptNotificationTap(tap) else { return }
        if let text = asked.copy { actions.copy(text) }
        if let line = asked.refusalLine { actions.log(line) }
        if let url = asked.open { actions.open(url) }
    }
}
