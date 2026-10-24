import SwiftUI

 
public struct ClashModuleEntry: Identifiable {
    public let id: String
    public let title: String
    public let action: () -> Void

    public init(id: String, title: String, action: @escaping () -> Void) {
        self.id = id
        self.title = title
        self.action = action
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
public struct ClashModuleEntries: View {
    private let entries: [ClashModuleEntry]
    private let palette: ClashProductPalette
    private let identifier: (ClashModuleEntry) -> String
    private let stacked: Bool

    public init(
        entries: [ClashModuleEntry],
        palette: ClashProductPalette,
        stacked: Bool,
        identifier: @escaping (ClashModuleEntry) -> String
    ) {
        self.entries = entries
        self.palette = palette
        self.stacked = stacked
        self.identifier = identifier
    }

    public var body: some View {
        if stacked {
            VStack(alignment: .trailing, spacing: ClashTheme.Spacing.compact) {
                buttons
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        } else {
            HStack(spacing: ClashTheme.Spacing.compact) {
                Spacer(minLength: 0)
                buttons
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        ForEach(entries) { entry in
            ClashModuleEntryButton(
                title: entry.title,
                palette: palette,
                action: entry.action
            )
            .accessibilityIdentifier(identifier(entry))
        }
    }
}

private struct ClashModuleEntryButton: View {
    let title: String
    let palette: ClashProductPalette
    let action: () -> Void

     
     
     
    var body: AnyView {
#if os(macOS)
        return AnyView(quiet)
#else
        if #available(iOS 26.0, tvOS 26.0, *) {
            return AnyView(
                Button(action: action) { label }
                    .buttonStyle(.glass)
                    .foregroundStyle(.primary)
            )
        }
        return AnyView(quiet)
#endif
    }

    private var quiet: some View {
        Button(action: action) {
            label
                .padding(.horizontal, ClashTheme.Spacing.row)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(
                        cornerRadius: ClashTheme.Radius.control,
                        style: .continuous
                    )
                    .fill(palette.raisedFill)
                )
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var label: some View {
        Text(ClashCopy.key(title))
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
    }
}
