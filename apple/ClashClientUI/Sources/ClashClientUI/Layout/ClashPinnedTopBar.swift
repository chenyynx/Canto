import SwiftUI

public extension View {
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    func clashPinnedTopBar<Bar: View>(
        @ViewBuilder _ bar: @escaping () -> Bar
    ) -> AnyView {
        if ClashPinnedTopBarPolicy.usesSystemScrollPocket {
             
             
             
             
             
             
             
             
             
            if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
                return AnyView(safeAreaBar(edge: .top, spacing: 0, content: bar))
            }
            return AnyView(self)
        }
#if os(macOS)
         
         
        return AnyView(
            modifier(ClashMacScrollEdgeFade())
                .safeAreaInset(edge: .top, spacing: 0, content: bar)
        )
#else
        return AnyView(
            safeAreaInset(edge: .top, spacing: 0) {
                bar().modifier(ClashPreScrollEdgeBarGround())
            }
        )
#endif
    }

     
     
     
     
     
     
     
    @ViewBuilder
    func clashStablePinnedTopBar<Footprint: View, Bar: View>(
        @ViewBuilder footprint: @escaping () -> Footprint,
        @ViewBuilder bar: @escaping () -> Bar
    ) -> some View {
        if ClashPinnedTopBarPolicy.usesSystemScrollPocket {
            clashPinnedTopBar {
                footprint()
                    .hidden()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .overlay(alignment: .top) {
                        bar()
                    }
            }
             
             
             
             
             
             
             
            .overlay(alignment: .top) {
                 
                 
                 
                 
                bar()
                    .opacity(0.001)
                    .allowsHitTesting(true)
                    .accessibilityHidden(true)
                    .accessibilityRepresentation { Color.clear }
            }
        } else {
            clashPinnedTopBar {
                footprint()
                    .hidden()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
                    .overlay(alignment: .top) {
                         
                         
                         
                         
                        bar().modifier(ClashPreScrollEdgeBarGround())
                    }
            }
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
enum ClashPinnedTopBarPolicy {
    static var usesSystemScrollPocket: Bool {
#if os(macOS)
        return false
#else
        if #available(iOS 26.0, tvOS 26.0, *) { return true }
        return false
#endif
    }
}

private struct ClashPreScrollEdgeBarGround: ViewModifier {
    @Environment(\.clashDetailCanvas) private var canvas
    @Environment(\.clashRegularShellOwnsCanvas) private var shellOwnsCanvas

    func body(content: Content) -> some View {
#if os(macOS)
         
        content
#else
        if shellOwnsCanvas, let canvas {
            content.background(canvas)
        } else {
            content.background(.bar)
        }
#endif
    }
}

#if os(macOS)
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
private struct ClashMacScrollEdgeFade: ViewModifier {
     
     
     
    private static let overflow: CGFloat = 64
     
    private static let ramp = Gradient(stops: [
        .init(color: .black.opacity(0.02), location: 0),
        .init(color: .black.opacity(0.04), location: 0.35),
        .init(color: .black.opacity(0.08), location: 0.6),
        .init(color: .black.opacity(0.14), location: 0.75),
        .init(color: .black.opacity(0.24), location: 0.86),
        .init(color: .black.opacity(0.4), location: 0.93),
        .init(color: .black.opacity(0.64), location: 0.975),
        .init(color: .black, location: 1),
    ])
     
     
    private static let opaqueRamp = Gradient(stops: [
        .init(color: .clear, location: 0),
        .init(color: .clear, location: 0.85),
        .init(color: .black, location: 1),
    ])

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

     
     
     
    @State private var reach: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                max(0, proxy.frame(in: .global).minY)
            } action: { reach = $0 }
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    LinearGradient(
                        gradient: reduceTransparency ? Self.opaqueRamp : Self.ramp,
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: reach)
                    Color.black
                }
                .padding(.top, -reach)
                .padding(.horizontal, -Self.overflow)
                .padding(.bottom, -Self.overflow)
            }
    }
}
#endif
