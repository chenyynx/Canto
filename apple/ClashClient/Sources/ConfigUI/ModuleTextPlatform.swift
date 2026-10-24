#if os(iOS) || os(macOS)
import ClashClientUI
import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

 
 
 
 
 
 
 
 
enum ModuleTextPlatform {
    @MainActor
    static func install() {
        ClashModuleText.platformView = { request in
            AnyView(ModuleTextView(request: request))
        }
    }

     
    @MainActor
    static func installIfNeeded() {
        if ClashModuleText.platformView == nil { install() }
    }
}

#if os(iOS)
struct ModuleTextView: UIViewRepresentable {
    let request: ClashModuleText.Request

     
    static func makeTextView() -> UITextView {
        let view = UITextView()
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.smartQuotesType = .no
        view.smartDashesType = .no
        view.smartInsertDeleteType = .no
        view.spellCheckingType = .no
        view.dataDetectorTypes = []
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(
            for: .monospacedSystemFont(ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular))
        view.adjustsFontForContentSizeCategory = true
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.keyboardDismissMode = .interactive
        return view
    }

    func makeUIView(context: Context) -> UITextView {
        let view = Self.makeTextView()
        view.delegate = context.coordinator
        view.text = request.text.wrappedValue
        view.isEditable = request.isEditable
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.text = request.text
        if view.text != request.text.wrappedValue { view.text = request.text.wrappedValue }
        if view.isEditable != request.isEditable { view.isEditable = request.isEditable }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: request.text) }

    final class Coordinator: NSObject, UITextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }
    }
}
#else
struct ModuleTextView: NSViewRepresentable {
    let request: ClashModuleText.Request

     
    static func makeScrollView() -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        if let view = scroll.documentView as? NSTextView {
            configure(view)
        }
        return scroll
    }

    static func configure(_ view: NSTextView) {
        view.isRichText = false
        view.importsGraphics = false
        view.allowsUndo = true
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.isAutomaticDashSubstitutionEnabled = false
        view.isAutomaticTextReplacementEnabled = false
        view.isAutomaticSpellingCorrectionEnabled = false
        view.isContinuousSpellCheckingEnabled = false
        view.isGrammarCheckingEnabled = false
        view.isAutomaticLinkDetectionEnabled = false
        view.isAutomaticDataDetectionEnabled = false
        view.smartInsertDeleteEnabled = false
        view.drawsBackground = false
        view.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        view.textContainerInset = NSSize(width: 0, height: 4)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = Self.makeScrollView()
        if let view = scroll.documentView as? NSTextView {
            view.delegate = context.coordinator
            view.string = request.text.wrappedValue
            view.isEditable = request.isEditable
        }
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.text = request.text
        guard let view = scroll.documentView as? NSTextView else { return }
        if view.string != request.text.wrappedValue { view.string = request.text.wrappedValue }
        if view.isEditable != request.isEditable { view.isEditable = request.isEditable }
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: request.text) }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>

        init(text: Binding<String>) { self.text = text }

        func textDidChange(_ notification: Notification) {
            guard let view = notification.object as? NSTextView else { return }
            text.wrappedValue = view.string
        }
    }
}
#endif
#endif
