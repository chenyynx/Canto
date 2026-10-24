import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashSelectionCircle: View {
    public let isSelected: Bool

    public init(isSelected: Bool) { self.isSelected = isSelected }

    public var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.title3)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(Color.secondary.opacity(0.5)))
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }
}
