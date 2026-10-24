import AppKit
import ClashClientUI
import SwiftUI

 
 
 
 
struct ClashMacWindowCloseGuard: NSViewRepresentable {
    @ObservedObject var controller: ClashWindowDepartureController

    func makeNSView(context: Context) -> GuardView {
        let view = GuardView()
        view.install = { [controller] window in
            controller.closeWindow = { [weak window] in window?.close() }
            let delegate = ClashMacWindowCloseGuardDelegate(
                controller: controller,
                forwarding: window.delegate
            )
            window.delegate = delegate
            view.delegate = delegate
        }
        return view
    }

    func updateNSView(_ nsView: GuardView, context: Context) {
        nsView.window?.isDocumentEdited = controller.hasUnsavedChanges
    }

    final class GuardView: NSView {
        var install: ((NSWindow) -> Void)?
         
        var delegate: ClashMacWindowCloseGuardDelegate?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, delegate == nil else { return }
            install?(window)
        }
    }
}

 
 
final class ClashMacWindowCloseGuardDelegate: NSObject, NSWindowDelegate {
    private let controller: ClashWindowDepartureController
    private weak var forwarding: NSWindowDelegate?

    init(controller: ClashWindowDepartureController, forwarding: NSWindowDelegate?) {
        self.controller = controller
        self.forwarding = forwarding
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard controller.shouldClose() else { return false }
        return forwarding?.windowShouldClose?(sender) ?? true
    }

    override func responds(to aSelector: Selector!) -> Bool {
        super.responds(to: aSelector) || (forwarding?.responds(to: aSelector) ?? false)
    }

    override func forwardingTarget(for aSelector: Selector!) -> Any? {
        if super.responds(to: aSelector) { return nil }
        return forwarding
    }
}
