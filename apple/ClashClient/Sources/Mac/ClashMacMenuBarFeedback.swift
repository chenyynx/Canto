import AppKit
import ClashClientUI
import ClashMacClient
import UserNotifications

 
 
 
 
 
 
 
 
@MainActor
enum ClashMacMenuBarFeedback {
     
     
    static let identifier = "menubar.result"

     
     
    static func confirm(_ title: ClashDisplayText, locale: Locale) {
        let center = UNUserNotificationCenter.current()
         
         
        let content = UNMutableNotificationContent()
        content.title = title.resolved(locale: locale)
         
         
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) { _ in }
        }
        ClashMacFeedback.postAnnouncement(title.resolved(locale: locale))
    }

     
    static func fail(_ presentation: ClashFeedbackPresentation, on window: NSWindow?, locale: Locale) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = presentation.title.resolved(locale: locale)
        alert.informativeText = presentation.message?.resolved(locale: locale) ?? ""
        alert.addButton(withTitle: ClashCopy.string("OK", locale: locale))
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.beginSheetModal(for: window)
        } else {
            NSApplication.shared.activate(ignoringOtherApps: true)
            alert.runModal()
        }
    }
}
