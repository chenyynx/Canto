import AppKit
import ClashClientUI
import QuartzCore

 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum ClashMacFrameCounter {
     
     
     
     
    static func install() {
        guard #available(macOS 14.0, *) else { return }
        ClashDisplayLinkHooks.make = { onTick in
            ClashMacDisplayLink(onTick)
        }
    }
}

 
 
 
 
 
 
@available(macOS 14.0, *)
@MainActor
final class ClashMacDisplayLink: ClashDisplayLinkDriving {
    private var link: CADisplayLink?
    private let onTick: (CFTimeInterval, CFTimeInterval) -> Void

    init?(_ onTick: @escaping (CFTimeInterval, CFTimeInterval) -> Void) {
        self.onTick = onTick
         
         
         
        let made: CADisplayLink?
        if let host = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) {
            made = host.displayLink(target: self, selector: #selector(fire(_:)))
        } else if let screen = NSScreen.main {
            made = screen.displayLink(target: self, selector: #selector(fire(_:)))
        } else {
            made = nil
        }
        guard let made else { return nil }
        made.add(to: .main, forMode: .common)
        link = made
    }

    @objc private func fire(_ link: CADisplayLink) {
        onTick(link.timestamp, link.targetTimestamp)
    }

    func invalidate() {
        link?.invalidate()
        link = nil
    }
}
