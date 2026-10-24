import SwiftUI

extension View {
     
     
     
     
     
     
     
     
     
     
     
     
    public func clashMacGroupRow(first: Bool, last: Bool,
                                margin: CGFloat = ClashMacGroupMetrics.margin,
                                inset: CGFloat = ClashMacGroupMetrics.inset) -> some View {
        modifier(ClashMacGroupRow(first: first, last: last, margin: margin, inset: inset))
    }

     
     
    public func clashMacGroupHeader(first: Bool = false, margin: CGFloat = ClashMacGroupMetrics.margin) -> some View {
         
        font(.body.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, first ? 0 : ClashMacGroupMetrics.groupGap)
            .padding(.bottom, ClashMacGroupMetrics.headerGap)
            .padding(.horizontal, margin + ClashTheme.Spacing.tight)
            .clashMacPlainRow()
    }

     
     
    public func clashMacPlainRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .modifier(ClashMacHiddenRowSeparator())
    }
}

 
public enum ClashMacGroupMetrics {
    public static let rowHeight: CGFloat = 30
    public static let inset: CGFloat = 12
    public static let verticalPadding: CGFloat = 7
     
    public static let margin: CGFloat = 20
     
    public static let groupGap: CGFloat = 20
     
    public static let headerGap: CGFloat = 6
}

extension EnvironmentValues {
     
     
     
    public var clashMacGroupedList: Bool {
        get { self[ClashMacGroupedListKey.self] }
        set { self[ClashMacGroupedListKey.self] = newValue }
    }
}

private struct ClashMacGroupedListKey: EnvironmentKey {
    static let defaultValue = false
}

private struct ClashMacGroupRow: ViewModifier {
    let first: Bool
    let last: Bool
    let margin: CGFloat
    let inset: CGFloat
    @Environment(\.pixelLength) private var pixel

    func body(content: Content) -> some View {
        let shape = ClashMacGroupShape(roundsTop: first, roundsBottom: last, radius: ClashTheme.Radius.card)
        content
            .padding(.horizontal, inset)
            .padding(.vertical, ClashMacGroupMetrics.verticalPadding)
            .frame(maxWidth: .infinity, minHeight: ClashMacGroupMetrics.rowHeight, alignment: .leading)
            .background(shape.fill(Self.card))
            .overlay(alignment: .top) {
                if !first {
                    Rectangle()
                        .fill(Self.separator)
                        .frame(height: pixel)
                        .padding(.leading, inset)
                        .padding(.trailing, ClashMacGroupMetrics.inset)
                }
            }
            .padding(.horizontal, margin)
            .clashMacPlainRow()
    }

#if os(macOS)
    private static let card = ClashTheme.MacOS.groupedCard
    private static let separator = ClashTheme.MacOS.groupedSeparator
#else
     
    private static let card = Color.clear
    private static let separator = Color.clear
#endif
}

 
 
 
 
 
 
 
 
 
public struct ClashMacHardTopEdge: ViewModifier {
    public init() {}

    public func body(content: Content) -> some View {
#if os(macOS)
        content.safeAreaInset(edge: .top, spacing: 0) {
            Divider()
                .background(alignment: .bottom) {
                    Color(nsColor: .controlBackgroundColor)
                        .ignoresSafeArea(.container, edges: .top)
                }
        }
#else
        content
#endif
    }
}

 
private struct ClashMacHiddenRowSeparator: ViewModifier {
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        content.listRowSeparator(.hidden)
#endif
    }
}

 
 
 
struct ClashMacGroupShape: InsettableShape {
    var roundsTop: Bool
    var roundsBottom: Bool
    var radius: CGFloat
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let r = rect.insetBy(dx: insetAmount, dy: insetAmount)
        let top = roundsTop ? max(0, min(radius - insetAmount, r.height / 2)) : 0
        let bottom = roundsBottom ? max(0, min(radius - insetAmount, r.height / 2)) : 0
        var path = Path()
        path.move(to: CGPoint(x: r.minX + top, y: r.minY))
        path.addLine(to: CGPoint(x: r.maxX - top, y: r.minY))
        if top > 0 {
            path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY + top), radius: top)
        }
        path.addLine(to: CGPoint(x: r.maxX, y: r.maxY - bottom))
        if bottom > 0 {
            path.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX - bottom, y: r.maxY), radius: bottom)
        }
        path.addLine(to: CGPoint(x: r.minX + bottom, y: r.maxY))
        if bottom > 0 {
            path.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY - bottom), radius: bottom)
        }
        path.addLine(to: CGPoint(x: r.minX, y: r.minY + top))
        if top > 0 {
            path.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.minX + top, y: r.minY), radius: top)
        }
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> ClashMacGroupShape {
        var shape = self
        shape.insetAmount += amount
        return shape
    }
}
