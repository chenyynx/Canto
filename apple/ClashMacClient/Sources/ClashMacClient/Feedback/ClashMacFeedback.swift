import AppKit
import ClashClientUI
import Foundation

 
 
public enum ClashMacFeedback {
     
     
     
     
     
    public static let lifetime = ClashFeedbackLifetime(
        reading: .init(base: 0.5, perCharacter: 0.06, minimum: 2, maximum: 5),
        undo: 10,
        warning: nil,
        error: nil,
        withAction: nil,
        batchSummary: nil
    )

     
    @MainActor
    public static func makeCenter() -> ClashFeedbackCenter {
        ClashFeedbackCenter(lifetime: lifetime, announce: postAnnouncement)
    }

     
     
    public static func postAnnouncement(_ text: String) {
        guard !text.isEmpty else { return }
        DispatchQueue.main.async {
            NSAccessibility.post(
                element: NSApp as Any,
                notification: .announcementRequested,
                userInfo: [
                    .announcement: text,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ]
            )
        }
    }
}

public extension ClashFeedbackCenter {
     
     
     
     
     
    @discardableResult
    func say(
        _ presentation: ClashFeedbackPresentation,
        operation: String,
        perform: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) -> Int {
        for entry in [state.current, state.covered].compactMap({ $0 }) where entry.operation == operation {
            dismiss(entry.id)
        }
        return show(presentation, operation: operation, perform: perform, onDismiss: onDismiss)
    }

     
     
    func withdraw(_ operation: String) {
        for entry in [state.current, state.covered].compactMap({ $0 }) where entry.operation == operation {
            dismiss(entry.id)
        }
    }
}
