#if os(macOS)
import AppKit
import ClashClientUI
import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
private final class ClashMacAppAppearance: ObservableObject {
    @Published private(set) var colorScheme: ColorScheme
    private var observation: NSKeyValueObservation?

    init() {
        colorScheme = Self.current()
        observation = NSApplication.shared.observe(
            \.effectiveAppearance
        ) { [weak self] _, _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let live = Self.current()
                if live != self.colorScheme {
                    self.colorScheme = live
                }
            }
        }
    }

    private static func current() -> ColorScheme {
        NSApplication.shared.effectiveAppearance
            .bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }
}

 
 
private struct ClashMacPooledAppearance<Content: View>: View {
    @StateObject private var appearance = ClashMacAppAppearance()
    let content: Content

    var body: some View {
        content.environment(\.colorScheme, appearance.colorScheme)
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacRootPoolStore {
    static let shared = ClashMacRootPoolStore()

    private var hosts: [ClashRootDestination: NSHostingView<AnyView>] = [:]
    private var appearanceObservation: NSKeyValueObservation?

    fileprivate func host(
        for destination: ClashRootDestination,
        seededWith seed: () -> AnyView
    ) -> NSHostingView<AnyView> {
        if let existing = hosts[destination] {
            return existing
        }
        let created = NSHostingView(rootView: seed())
        created.autoresizingMask = [.width, .height]
        if #available(macOS 14.0, *) {
            created.sceneBridgingOptions = []
        }
        hosts[destination] = created
         
         
         
         
         
        adoptCurrentAppearance()
        ClashPerf.mark("pool create root=\(destination.rawValue)")
        return created
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
    private func adoptCurrentAppearance() {
        if appearanceObservation == nil {
            appearanceObservation = NSApplication.shared.observe(
                \.effectiveAppearance
            ) { _, _ in
                Task { @MainActor in
                    ClashMacRootPoolStore.shared.adoptCurrentAppearance()
                }
            }
        }
        let wanted = NSApplication.shared.effectiveAppearance
        for host in hosts.values where host.appearance?.name != wanted.name {
             
             
            host.appearance = wanted
        }
    }

     
     
     
    func reset() {
        for host in hosts.values {
            host.removeFromSuperview()
        }
        hosts.removeAll()
    }
}

 
 
 
struct ClashMacPooledRootSlot: NSViewRepresentable {
    let destination: ClashRootDestination
    let visible: Bool
    let channels: ClashRegularRootChannels
    let foldStateSink: ClashBoolSink
    let background: Color
    let content: () -> AnyView

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        apply(to: container, context: context)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        apply(to: container, context: context)
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView: NSView,
        context: Context
    ) -> CGSize? {
         
         
         
        proposal.replacingUnspecifiedDimensions()
    }

    private func apply(to container: NSView, context: Context) {
         
         
         
        if visible || ClashMacRootPoolStore.shared.hasHost(for: destination) {
            let host = ClashMacRootPoolStore.shared.host(
                for: destination,
                seededWith: {
                    AnyView(
                        ClashMacPooledAppearance(
                            content: ClashPooledRootFeed(
                                channels: channels,
                                foldStateSink: foldStateSink,
                                background: background,
                                build: content
                            )
                        )
                         
                         
                         
                         
                         
                         
                         
                        .environment(\.self, context.environment)
                    )
                }
            )
            if host.superview !== container {
                ClashPerf.mark(
                    "pool attach root=\(destination.rawValue)"
                )
                container.addSubview(host)
            }
             
             
             
             
             
             
             
             
             
             
             
            if visible, host.frame != container.bounds {
                ClashPerf.mark(
                    "pool reframe root=\(destination.rawValue) "
                        + "to=\(Int(container.bounds.width))x"
                        + "\(Int(container.bounds.height))"
                )
                host.frame = container.bounds
            }
        }
        let wasVisible = container.alphaValue > 0
        if wasVisible != visible {
             
             
             
             
            ClashPerf.mark(
                "pool \(visible ? "show" : "hide") root=\(destination.rawValue)"
            )
            channels.uiTransitionSink?()
        }
         
         
         
         
         
         
         
         
         
         
         
         
        container.alphaValue = visible ? 1 : 0
         
         
         
         
         
         
         
        channels.latencyPulseGate.setOpen(visible)
    }
}

extension ClashMacRootPoolStore {
    fileprivate func hasHost(for destination: ClashRootDestination) -> Bool {
        hosts[destination] != nil
    }
}
#endif
