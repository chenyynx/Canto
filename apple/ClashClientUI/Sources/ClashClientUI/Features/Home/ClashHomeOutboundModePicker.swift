import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
public enum ClashHomeOutboundModeStyle: String, CaseIterable, Sendable {
    case spacious
    case compact

     
     
    public static let storageKey = "clash.home.outboundModeStyle"

    public var title: String {
        switch self {
        case .spacious: "Spacious"
        case .compact: "Compact"
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashHomeOutboundModePicker<Icon: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
     
    @Namespace private var segments

    let mode: AppleClientOutboundMode
     
    let symbol: (AppleClientOutboundMode) -> ClashSymbol
    let icon: (ClashSymbol) -> Icon
    let setMode: (AppleClientOutboundMode) -> Void

     
     
    @State private var wide: AppleClientOutboundMode?
     
    @State private var lensAt: AppleClientOutboundMode
     
    @State private var change = 0
     
     
    @State private var reported: AppleClientOutboundMode
     
     
    @State private var destination: AppleClientOutboundMode
     
     
     
     
    @State private var awaiting: AppleClientOutboundMode?
     
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
        _destination = State(initialValue: mode)
    }

     
     
    static var modes: [AppleClientOutboundMode] { [.global, .rule, .direct] }

     
     
    static func title(for mode: AppleClientOutboundMode) -> String {
        switch mode {
        case .global: "Global Mode"
        case .rule: "Rule Mode"
        case .direct: "Direct Mode"
        }
    }

     
    static var inset: CGFloat { 4 }

     
    private var selection: Capsule { Capsule(style: .continuous) }

     
     
     
     
     
     
     
    static var shrink: Animation { .easeOut(duration: 0.05) }
    static var shrinkTime: Double { 0.045 }
    static var slide: Animation { .easeInOut(duration: 0.07) }
    static var slideTime: Double { 0.06 }
    static var grow: Animation { .spring(response: 0.14, dampingFraction: 0.8) }

     
     
     
     
     
     
     
    static var handOnAfter: Double { 0.8 }

     
     
     
    var body: some View {
        if #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            return AnyView(glassRow)
        }
        return AnyView(ClashHomeOutboundModePlainButtons(
            mode: mode, symbol: symbol, icon: icon, setMode: setMode
        ))
    }

    @available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
    private var glassRow: some View {
        segmentRow
        .padding(Self.inset)
         
         
         
        .background {
            ClashHomeModeSelection(shape: selection)
                .matchedGeometryEffect(id: lensAt, in: segments, isSource: false)
        }
        .onChange(of: mode) { target in
            reported = target
            if let pending = awaiting {
                if target == pending { awaiting = nil }
            } else if target != destination {
                move(to: target)
            }
        }
         
        .onDisappear { handOn() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ClashCopy.key("Outbound Mode"))
        .accessibilityIdentifier("home.mode.picker")
    }

     
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, *)
    private var segmentRow: some View {
        ClashHomeModeSegmentsLayout(
            selectedIndex: wide.flatMap { Self.modes.firstIndex(of: $0) }
        ) {
            ForEach(Self.modes, id: \.self) { candidate in
                segment(candidate)
            }
        }
    }

    private func choose(_ candidate: AppleClientOutboundMode) {
         
         
         
         
         
        move(to: candidate)
        awaiting = candidate
        unsent = candidate
         
         
        let request = change
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.handOnAfter) {
            guard change == request else { return }
            handOn()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                guard change == request, awaiting == candidate else { return }
                awaiting = nil
                if reported != candidate {
                    move(to: reported)
                }
            }
        }
    }

     
     
     
     
    private func handOn() {
        guard let chosen = unsent else { return }
        unsent = nil
         
         
        withAnimation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)
        ) {
            setMode(chosen)
        }
    }

     
     
    private func move(to target: AppleClientOutboundMode) {
        destination = target
        change += 1
        let this = change
        guard !reduceMotion else {
            wide = target
            lensAt = target
            return
        }
        guard lensAt != target else {
            withAnimation(Self.grow) { wide = target }
            return
        }
        withAnimation(Self.shrink) { wide = nil }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.shrinkTime) {
            guard change == this else { return }
            withAnimation(Self.slide) { lensAt = target }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.slideTime) {
                guard change == this else { return }
                withAnimation(Self.grow) { wide = target }
            }
        }
    }

    private func segment(_ candidate: AppleClientOutboundMode) -> some View {
         
        let isSelected = destination == candidate
        let isWide = wide == candidate
        let isLit = lensAt == candidate
        return Button {
            choose(candidate)
        } label: {
            HStack(spacing: ClashTheme.Spacing.compact) {
                icon(symbol(candidate))
                    .font(.body.weight(.semibold))
                if isWide {
                    Text(ClashCopy.key(Self.title(for: candidate)))
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                         
                         
                        .transition(
                            .asymmetric(
                                insertion: .opacity.animation(
                                    .easeOut(duration: 0.09)
                                ),
                                removal: .opacity.animation(
                                    .easeOut(duration: 0.035)
                                )
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
        .buttonStyle(ClashHomeModeSegmentButtonStyle())
        .clashPointerHelp(Text(ClashCopy.key(Self.title(for: candidate))))
        .accessibilityLabel(ClashCopy.key(Self.title(for: candidate)))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("home.mode.\(candidate.rawValue)")
    }
}

 
 
 
 
@available(iOS 16.0, macOS 13.0, tvOS 16.0, *)
struct ClashHomeModeSegmentsLayout: Layout {
    var selectedIndex: Int?
     
     
    var spacing: CGFloat = 0

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let width = proposal.width ?? idealWidth(subviews)
         
        let height = proposal.height.flatMap { $0.isFinite ? $0 : nil }
            ?? zip(subviews, widths(for: width, count: subviews.count))
                .map { $0.sizeThatFits(ProposedViewSize(width: $1, height: nil)).height }
                .max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        for (subview, width) in zip(
            subviews,
            widths(for: bounds.width, count: subviews.count)
        ) {
            subview.place(
                at: CGPoint(x: x, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
            x += width + spacing
        }
    }

    private func weight(_ index: Int) -> CGFloat {
        ClashHomeModeSegmentWidths.weight(index, selectedIndex: selectedIndex)
    }

    private func widths(for total: CGFloat, count: Int) -> [CGFloat] {
        ClashHomeModeSegmentWidths.widths(
            total: total - spacing * CGFloat(max(0, count - 1)),
            count: count,
            selectedIndex: selectedIndex
        )
    }

     
    private func idealWidth(_ subviews: Subviews) -> CGFloat {
        let sum = (0..<subviews.count).map(weight).reduce(0, +)
        let unit = subviews.indices.map {
            subviews[$0].sizeThatFits(.unspecified).width / weight($0)
        }.max() ?? 0
        return unit * sum + spacing * CGFloat(max(0, subviews.count - 1))
    }
}

 
 
 
 
 
private struct ClashHomeModeSelection: View {
    let shape: Capsule

    var body: some View {
        Button(action: {}) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .clashPrimaryActionButtonStyle()
        .modifier(ClashCapsuleButtonShape())
         
         
        .clipShape(shape)
        .modifier(ClashSelectionGlassRim(shape: shape))
         
         
        .modifier(ClashNotFocusable())
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

 
 
 
 
 
 
 
private struct ClashSelectionGlassRim: ViewModifier {
    let shape: Capsule

    func body(content: Content) -> some View {
#if os(iOS)
        content.overlay(
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.6), .white.opacity(0.08), .white.opacity(0.28)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.2
            )
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        )
#else
        content
#endif
    }
}

 
private struct ClashHomeModeSegmentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.6 : 1)
    }
}

 
 
enum ClashHomeModeSegmentWidths {
    static func weight(_ index: Int, selectedIndex: Int?) -> CGFloat {
        index == selectedIndex ? 2 : 1
    }

    static func widths(
        total: CGFloat,
        count: Int,
        selectedIndex: Int?
    ) -> [CGFloat] {
        guard count > 0 else { return [] }
        let weights = (0..<count).map { weight($0, selectedIndex: selectedIndex) }
        let sum = weights.reduce(0, +)
        return weights.map { max(0, total) * $0 / sum }
    }
}

 
 
 
 
private struct ClashHomeOutboundModePlainButtons<Icon: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let mode: AppleClientOutboundMode
    let symbol: (AppleClientOutboundMode) -> ClashSymbol
    let icon: (ClashSymbol) -> Icon
    let setMode: (AppleClientOutboundMode) -> Void

    var body: some View {
        row
        .padding(ClashHomeOutboundModePicker<Icon>.inset)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ClashCopy.key("Outbound Mode"))
        .accessibilityIdentifier("home.mode.picker")
    }

     
     
     
     
    private var row: AnyView {
        let modes = ClashHomeOutboundModePicker<Icon>.modes
        if #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
            return AnyView(ClashHomeModeSegmentsLayout(
                selectedIndex: modes.firstIndex(of: mode),
                spacing: ClashTheme.Spacing.compact
            ) {
                ForEach(modes, id: \.self) { candidate in
                    button(candidate, fills: true)
                }
            })
        }
        return AnyView(HStack(spacing: ClashTheme.Spacing.compact) {
            ForEach(modes, id: \.self) { candidate in
                button(candidate, fills: mode == candidate)
            }
        })
    }

    @ViewBuilder
    private func button(
        _ candidate: AppleClientOutboundMode,
        fills: Bool
    ) -> some View {
        let title = ClashHomeOutboundModePicker<Icon>.title(for: candidate)
        let base = Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.86)) {
                setMode(candidate)
            }
        } label: {
             
             
             
            HStack(spacing: 4) {
                icon(symbol(candidate))
                if mode == candidate {
                    Text(ClashCopy.key(title))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .font(.subheadline.weight(.semibold))
             
             
             
            .frame(
                minWidth: ClashTheme.Control.minimumHitTarget,
                maxWidth: fills ? .infinity : nil,
                maxHeight: .infinity
            )
        }
        .modifier(ClashCapsuleButtonShape())
        .clashPointerHelp(Text(ClashCopy.key(title)))
        .accessibilityLabel(ClashCopy.key(title))
        .accessibilityAddTraits(mode == candidate ? .isSelected : [])
        .accessibilityIdentifier("home.mode.\(candidate.rawValue)")
        if mode == candidate {
             
             
            base.clashPrimaryActionButtonStyle()
        } else {
             
             
             
             
            base.buttonStyle(.borderless)
                .tint(.primary)
                .contentShape(Capsule())
        }
    }
}

 
 
private struct ClashNotFocusable: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 17.0, macOS 12.0, tvOS 17.0, *) {
            content.focusable(false)
        } else {
            content
        }
    }
}

 
 
private struct ClashCapsuleButtonShape: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 15.0, macOS 14.0, tvOS 15.0, *) {
            content.buttonBorderShape(.capsule)
        } else {
            content
        }
    }
}
