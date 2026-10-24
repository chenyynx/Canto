import AppKit
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashMacSidebarLock: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> LockView {
        LockView()
    }

    public func updateNSView(_ nsView: LockView, context: Context) {
        nsView.engage()
    }

     
    @MainActor
    public final class Hold: NSObject {
        private nonisolated(unsafe) weak var item: NSSplitViewItem?
        private nonisolated(unsafe) static var context = 0

        var heldItem: NSSplitViewItem? { item }

        init(item: NSSplitViewItem) {
            self.item = item
            super.init()
            item.addObserver(
                self,
                forKeyPath: #keyPath(NSSplitViewItem.canCollapse),
                options: [.new],
                context: &Self.context
            )
            item.canCollapse = false
        }

        deinit {
            item?.removeObserver(
                self,
                forKeyPath: #keyPath(NSSplitViewItem.canCollapse),
                context: &Self.context
            )
        }

         
         
         
         
        nonisolated public override func observeValue(
            forKeyPath keyPath: String?,
            of object: Any?,
            change: [NSKeyValueChangeKey: Any]?,
            context: UnsafeMutableRawPointer?
        ) {
            guard context == &Self.context else {
                super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
                return
            }
            MainActor.assumeIsolated {
                if let item, item.canCollapse {
                    item.canCollapse = false
                }
            }
        }
    }

     
     
     
    @MainActor
    public static func sidebarItem(under root: NSView?) -> NSSplitViewItem? {
        guard let root else { return nil }
        if let splitView = root as? NSSplitView,
           let controller = splitView.delegate as? NSSplitViewController,
           let sidebar = controller.splitViewItems.first(where: { $0.behavior == .sidebar }) {
            return sidebar
        }
        for child in root.subviews {
            if let found = sidebarItem(under: child) {
                return found
            }
        }
        return nil
    }

    public final class LockView: NSView {
        private(set) var hold: Hold?

        public override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            engage()
        }

        public override func layout() {
            super.layout()
            engage()
        }

         
         
        @MainActor
        func engage() {
            if let held = hold?.heldItem, held.viewController.view.window === window {
                return
            }
            hold = nil
            guard let item = Self.locate(in: window) else { return }
            hold = Hold(item: item)
        }

        static func locate(in window: NSWindow?) -> NSSplitViewItem? {
            ClashMacSidebarLock.sidebarItem(under: window?.contentView)
        }
    }
}
