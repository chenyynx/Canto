import SwiftUI

public struct ClashFullWidthSegmentedPlatformOption: Identifiable {
    public let id: AnyHashable
    public let title: String
    public let accessibilityIdentifier: String?

    public init(
        id: AnyHashable,
        title: String,
        accessibilityIdentifier: String?
    ) {
        self.id = id
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

 
 
 
public struct ClashFullWidthSegmentedPickerAdapter {
    private let makeContent: @MainActor (
        Binding<AnyHashable>,
        [ClashFullWidthSegmentedPlatformOption]
    ) -> AnyView

    public init(
        _ makeContent: @escaping @MainActor (
            Binding<AnyHashable>,
            [ClashFullWidthSegmentedPlatformOption]
        ) -> AnyView
    ) {
        self.makeContent = makeContent
    }

    @MainActor
    public func callAsFunction(
        selection: Binding<AnyHashable>,
        options: [ClashFullWidthSegmentedPlatformOption]
    ) -> AnyView {
        makeContent(selection, options)
    }
}

public struct ClashFullWidthSegmentedPickerAdapterKey: EnvironmentKey {
    nonisolated(unsafe) public static let defaultValue:
        ClashFullWidthSegmentedPickerAdapter? = nil
}

public extension EnvironmentValues {
    var clashFullWidthSegmentedPickerAdapter:
        ClashFullWidthSegmentedPickerAdapter?
    {
        get { self[ClashFullWidthSegmentedPickerAdapterKey.self] }
        set { self[ClashFullWidthSegmentedPickerAdapterKey.self] = newValue }
    }
}

struct ClashFullWidthSegmentedOption<Selection: Hashable>: Identifiable {
    let selection: Selection
    let title: String
    let accessibilityIdentifier: String?

    var id: Selection { selection }
}

 
 
 
 
 
 
 
 
 
 
 
enum ClashFullWidthSegmentedRole {
     
     
    case pageStrip
     
    case inlineControl
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashFullWidthSegmentedPicker<Selection: Hashable>: View {
    @Binding var selection: Selection
    let options: [ClashFullWidthSegmentedOption<Selection>]
     
    let role: ClashFullWidthSegmentedRole
     
     
    var underlineSeparator: Color = .secondary
    @Environment(\.clashFullWidthSegmentedPickerAdapter)
    private var platformAdapter

    @ViewBuilder
    var body: some View {
         
         
         
         
        switch role {
        case .pageStrip:
            underlineTabs
        case .inlineControl:
            if let platformAdapter {
                platformAdapter(
                    selection: erasedSelection,
                    options: options.map {
                        ClashFullWidthSegmentedPlatformOption(
                            id: AnyHashable($0.selection),
                            title: $0.title,
                            accessibilityIdentifier: $0.accessibilityIdentifier
                        )
                    }
                )
            } else {
                segmentedPicker
            }
        }
    }

    private var erasedSelection: Binding<AnyHashable> {
        Binding(
            get: { AnyHashable(selection) },
            set: { candidate in
                guard let typed = candidate.base as? Selection else { return }
                selection = typed
            }
        )
    }

    private var segmentedPicker: some View {
        Picker("", selection: $selection) {
            ForEach(options) { option in
                Text(verbatim: option.title)
                    .tag(option.selection)
                    .accessibilityIdentifier(
                        option.accessibilityIdentifier ?? ""
                    )
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
    }

     
     
     
     
     
    private var underlineTabs: some View {
        HStack(spacing: 0) {
            ForEach(options) { option in
                Button {
                    selection = option.selection
                } label: {
                    Text(verbatim: option.title)
                        .font(
                            .subheadline.weight(
                                selection == option.selection
                                    ? .semibold : .regular
                            )
                        )
                        .foregroundStyle(
                            selection == option.selection
                                ? AnyShapeStyle(.tint)
                                : AnyShapeStyle(.secondary)
                        )
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.vertical, ClashTheme.Spacing.row)
                        .overlay(alignment: .bottom) {
                            Rectangle()
                                .fill(
                                    selection == option.selection
                                        ? AnyShapeStyle(.tint)
                                        : AnyShapeStyle(Color.clear)
                                )
                                .frame(height: 2)
                        }
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                         
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityValue(
                    selection == option.selection ? "Selected" : ""
                )
                .accessibilityIdentifier(
                    option.accessibilityIdentifier ?? ""
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(underlineSeparator.opacity(0.28))
                .frame(height: 1)
                .zIndex(-1)
        }
    }
}
