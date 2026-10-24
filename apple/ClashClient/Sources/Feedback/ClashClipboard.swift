import ClashClientUI
import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
#endif

 
 
 
 
@MainActor
enum ClashClipboard {
     
     
    static func copy(
        _ text: String,
        feedback: ClashFeedbackCenter?,
        noun: String? = nil,
        operation: String = "copy"
    ) {
#if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
#else
        UIPasteboard.general.string = text
#endif
        feedback?.show(
            .success(title: noun.map { ClashFeedbackCopy.copied($0) } ?? ClashFeedbackCopy.copied,
                     accessibilityIdentifier: "feedback.copied"),
            operation: operation
        )
    }
}
