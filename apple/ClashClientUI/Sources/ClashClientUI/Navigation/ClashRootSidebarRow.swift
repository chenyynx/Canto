import SwiftUI

 
 
 
 
 
public struct ClashRootSidebarRow<Icon: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public let destination: ClashRootDestination
    public let isSelected: Bool
    public let minimumHeight: CGFloat
    public let horizontalPadding: CGFloat

    private let icon: Icon

    public init(
        destination: ClashRootDestination,
        isSelected: Bool,
        minimumHeight: CGFloat = ClashTheme.Control.minimumHitTarget,
        horizontalPadding: CGFloat = ClashTheme.Spacing.compact,
        @ViewBuilder icon: () -> Icon
    ) {
        self.destination = destination
        self.isSelected = isSelected
        self.minimumHeight = minimumHeight
        self.horizontalPadding = horizontalPadding
        self.icon = icon()
    }

    public var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize
                && ClashPlatformLayout.sidebarStacksLabelsAtAccessibilitySizes
            {
                VStack(
                    alignment: .leading,
                    spacing: ClashTheme.Spacing.compact
                ) {
                    sidebarIcon
                    title
                }
            } else {
                HStack(spacing: ClashTheme.Spacing.row) {
                    sidebarIcon
                    title
                    Spacer(minLength: ClashTheme.Spacing.compact)
                }
            }
        }
        .frame(minHeight: minimumHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, horizontalPadding)
        .foregroundStyle(contentStyle)
        .background {
            Capsule()
                .fill(
                    isSelected
                        ? Color.primary.opacity(
                            ClashTheme.Opacity.regularSidebarSelection
                        )
                        : Color.clear
                )
        }
        .contentShape(Rectangle())
    }

    private var sidebarIcon: some View {
        icon
            .font(.system(
                size: ClashTheme.Regular.Sidebar.iconSize,
                weight: .semibold
            ))
            .frame(
                width: ClashTheme.Regular.Sidebar.iconSize,
                height: ClashTheme.Regular.Sidebar.iconSize
            )
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    private var contentStyle: AnyShapeStyle {
        isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary)
    }

    private var title: some View {
         
         
         
         
         
         
         
         
        HStack(spacing: 0) {
            Text(clash: .copy(destination.title))
                .lineLimit(1)
                .foregroundStyle(contentStyle)
#if os(macOS)
             
             
             
             
             
             
            if #available(macOS 15, *) {
                EmptyView()
            } else {
                Rectangle()
                    .fill(Color.primary.opacity(0.02))
                    .frame(width: 12, height: 12)
                    .accessibilityHidden(true)
            }
#endif
        }
    }
}
