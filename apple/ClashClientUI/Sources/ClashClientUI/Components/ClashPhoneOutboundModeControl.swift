import SwiftUI

public extension View {
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashPhoneOutboundMode<Icon: View>(
        mode: AppleClientOutboundMode,
        symbol: @escaping (AppleClientOutboundMode) -> ClashSymbol,
        icon: @escaping (ClashSymbol) -> Icon,
        setMode: @escaping (AppleClientOutboundMode) -> Void
    ) -> some View {
#if os(iOS)
        modifier(ClashPhoneOutboundModeOverride(mode: mode, symbol: symbol, icon: icon, setMode: setMode))
#else
        self
#endif
    }
}

#if os(iOS)
private struct ClashPhoneOutboundModeOverride<Icon: View>: ViewModifier {
    let mode: AppleClientOutboundMode
    let symbol: (AppleClientOutboundMode) -> ClashSymbol
    let icon: (ClashSymbol) -> Icon
    let setMode: (AppleClientOutboundMode) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
             
             
             
            return AnyView(
                ClashPhoneOutboundModeControl(mode: mode, symbol: symbol, icon: icon, setMode: setMode)
            )
        }
        return AnyView(content)
    }
}

 
 
 
 
 
 
@available(iOS 26.0, *)
private struct ClashPhoneOutboundModeControl<Icon: View>: View {
    @Namespace private var segments

    let mode: AppleClientOutboundMode
    let symbol: (AppleClientOutboundMode) -> ClashSymbol
    let icon: (ClashSymbol) -> Icon
    let setMode: (AppleClientOutboundMode) -> Void

     
    @State private var wide: AppleClientOutboundMode?
     
    @State private var lensAt: AppleClientOutboundMode
     
    @State private var change = 0
     
    @State private var reported: AppleClientOutboundMode
     
     
    @State private var awaiting: AppleClientOutboundMode?
     
    @State private var tap = 0
     
    @State private var unsent: AppleClientOutboundMode?

    init(
        mode: AppleClientOutboundMode,
        symbol: @escaping (AppleClientOutboundMode) -> ClashSymbol,
        icon: @escaping (ClashSymbol) -> Icon,
        setMode: @escaping (AppleClientOutboundMode) -> Void
    ) {
        self.mode = mode
        self.symbol = symbol
        self.icon = icon
        self.setMode = setMode
        _wide = State(initialValue: mode)
        _lensAt = State(initialValue: mode)
        _reported = State(initialValue: mode)
    }

    private typealias Shared = ClashHomeOutboundModePicker<Icon>
    private var selection: Capsule { Capsule(style: .continuous) }

     
     
     
     
     
     
     
    private static var handOnAfter: Double { 0.8 }

    var body: some View {
        ClashHomeModeSegmentsLayout(selectedIndex: wide.flatMap { Shared.modes.firstIndex(of: $0) }) {
            ForEach(Shared.modes, id: \.self) { candidate in
                segment(candidate)
            }
        }
        .padding(Shared.inset)
        .background {
            ClashPhoneModeSelection(shape: selection)
                .matchedGeometryEffect(id: lensAt, in: segments, isSource: false)
        }
        .onChange(of: mode) { target in
            reported = target
            if let pending = awaiting {
                if target == pending { awaiting = nil }
            } else if target != lensAt {
                move(to: target)
            }
        }
         
        .onDisappear { handOn() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ClashCopy.key("Outbound Mode"))
        .accessibilityIdentifier("home.mode.picker")
    }

    private func segment(_ candidate: AppleClientOutboundMode) -> some View {
        let isWide = wide == candidate
        let isLit = lensAt == candidate
        return Button {
            choose(candidate)
        } label: {
            HStack(spacing: ClashTheme.Spacing.compact) {
                icon(symbol(candidate))
                    .font(.body.weight(.semibold))
                if isWide {
                    Text(ClashCopy.key(Shared.title(for: candidate)))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                         
                         
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(.easeOut(duration: 0.09)),
                                removal: .opacity.animation(.easeOut(duration: 0.035))
                            )
                        )
                }
            }
            .clashOnProminentForeground(isLit)
            .padding(.horizontal, ClashTheme.Spacing.compact)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .matchedGeometryEffect(id: candidate, in: segments, isSource: true)
        }
        .buttonStyle(ClashPhoneModeSegmentStyle())
        .accessibilityLabel(ClashCopy.key(Shared.title(for: candidate)))
         
         
        .accessibilityAddTraits((awaiting ?? mode) == candidate ? .isSelected : [])
        .accessibilityIdentifier("home.mode.\(candidate.rawValue)")
    }

    private func choose(_ candidate: AppleClientOutboundMode) {
         
         
         
        move(to: candidate)
        awaiting = candidate
        unsent = candidate
        tap += 1
        let this = tap
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handOnAfter) {
            guard tap == this else { return }
            handOn()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard tap == this, awaiting == candidate else { return }
                awaiting = nil
                if reported != candidate, lensAt == candidate { move(to: reported) }
            }
        }
    }

    private func handOn() {
        guard let chosen = unsent else { return }
        unsent = nil
        setMode(chosen)
    }

     
     
     
    private func move(to target: AppleClientOutboundMode) {
        change += 1
        let this = change
        guard lensAt != target else {
            withAnimation(Shared.grow) { wide = target }
            return
        }
        withAnimation(Shared.shrink) { wide = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + Shared.shrinkTime) {
            guard change == this else { return }
            withAnimation(Shared.slide) { lensAt = target }
            DispatchQueue.main.asyncAfter(deadline: .now() + Shared.slideTime) {
                guard change == this else { return }
                withAnimation(Shared.grow) { wide = target }
            }
        }
    }
}

 
 
 
 
@available(iOS 26.0, *)
private struct ClashPhoneModeSelection: View {
    let shape: Capsule

    var body: some View {
        Button(action: {}) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clashPrimaryActionButtonStyle()
        .buttonBorderShape(.capsule)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.6), .white.opacity(0.08), .white.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.2
            )
        )
        .focusable(false)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

 
private struct ClashPhoneModeSegmentStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}
#endif
