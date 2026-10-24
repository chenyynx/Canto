import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
public enum ClashMacSettingsMetrics {
     
     
     
     
     
     
     
     
    public static func rowVerticalInset(touch: CGFloat) -> CGFloat {
        ClashPlatformLayout.pageUsesSystemSettingsIdiom ? 0 : touch
    }

     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static let listRowMinHeight: CGFloat = 36

     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
     
    public static let headerControlHeight: CGFloat = 22
}

public enum ClashMacSettingsType {
     
    public static let title: Font = .body
     
     
    public static let value: Font = .body
     
    public static let mono: Font = .body.monospaced()
     
    public static let footnote: Font = .callout
}

 
public struct ClashMacToggleRow: View {
    private let title: ClashDisplayText
    @Binding private var isOn: Bool
     
     
     
     
    private let identifier: String?

    public init(_ title: ClashDisplayText, isOn: Binding<Bool>, identifier: String? = nil) {
        self.title = title
        _isOn = isOn
        self.identifier = identifier
    }

    public var body: some View {
        Toggle(isOn: $isOn) {
            Text(clash: title).font(ClashMacSettingsType.title)
        }
        .modifier(ClashOptionalIdentifier(identifier: identifier))
    }
}

 
 
 
public struct ClashMacNavigationRowLabel: View {
    private let title: ClashDisplayText
    private let subtitle: ClashDisplayText?
    private let value: ClashDisplayText?

    public init(
        _ title: ClashDisplayText,
        subtitle: ClashDisplayText? = nil,
        value: ClashDisplayText? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.value = value
    }

    public var body: some View {
        HStack(spacing: ClashTheme.Spacing.compact) {
            VStack(alignment: .leading, spacing: 2) {
                Text(clash: title).font(ClashMacSettingsType.title)
                if let subtitle {
                    Text(clash: subtitle)
                        .font(ClashMacSettingsType.value)
                        .foregroundStyle(.secondary)
                }
            }
            if let value {
                Spacer(minLength: ClashTheme.Spacing.compact)
                Text(clash: value)
                    .font(ClashMacSettingsType.value)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

 
 
public struct ClashMacActionRow<Trailing: View>: View {
    private let title: ClashDisplayText
    private let actionTitle: ClashDisplayText
    private let action: () -> Void
    private let trailing: () -> Trailing

    public init(
        _ title: ClashDisplayText,
        actionTitle: ClashDisplayText,
        action: @escaping () -> Void,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.actionTitle = actionTitle
        self.action = action
        self.trailing = trailing
    }

    @ViewBuilder
    public var body: some View {
         
         
         
        if #available(iOS 16.0, macOS 13.0, *) {
        LabeledContent {
            trailing()
            Button(action: action) {
                Text(clash: actionTitle)
            }
            .buttonStyle(.bordered)
             
             
             
             
             
            .tint(.primary)
        } label: {
            Text(clash: title).font(ClashMacSettingsType.title)
        }
        }
    }
}

extension ClashMacActionRow where Trailing == EmptyView {
    public init(
        _ title: ClashDisplayText,
        actionTitle: ClashDisplayText,
        action: @escaping () -> Void
    ) {
        self.init(title, actionTitle: actionTitle, action: action) {
            EmptyView()
        }
    }
}

 
 
 
 
 
 
 
 
public struct ClashMacFieldRow: View {
    private let label: ClashDisplayText
    private let prompt: String
    @Binding private var text: String
    private let mono: Bool
     
    private let identifier: String?

    public init(
        _ label: ClashDisplayText,
        prompt: String,
        text: Binding<String>,
        monospaced: Bool = false,
        identifier: String? = nil
    ) {
        self.label = label
        self.prompt = prompt
        _text = text
        self.mono = monospaced
        self.identifier = identifier
    }

    public var body: some View {
         
         
         
         
         
         
        TextField(
            text: $text,
            prompt: Text(prompt),
            label: { Text(clash: label) }
        )
        .labelsHidden()
        .font(mono ? ClashMacSettingsType.mono : ClashMacSettingsType.value)
        .modifier(ClashOptionalIdentifier(identifier: identifier))
    }
}

 
 
 
 
 
 
 
public struct ClashMacListAddRow: View {
    private let title: ClashDisplayText
    private let action: () -> Void

    public init(_ title: ClashDisplayText, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Label {
                Text(clash: title)
            } icon: {
                Image(systemName: ClashSymbol.plus.rawValue)
            }
        }
        .clashMacListAddChrome()
    }
}

 
 
 
 
 
 
 
 
public struct ClashMacDeletableRow<Content: View>: View {
    private let onDelete: () -> Void
    private let content: () -> Content
    @State private var hovering = false

    public init(
        onDelete: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.onDelete = onDelete
        self.content = content
    }

    public var body: some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            HStack(spacing: ClashTheme.Spacing.compact) {
                content()
                Spacer(minLength: ClashTheme.Spacing.compact)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "minus.circle.fill")
                        .foregroundStyle(
                            hovering
                                ? AnyShapeStyle(Color.red)
                                : AnyShapeStyle(.secondary)
                        )
                }
                .buttonStyle(.borderless)
                .onHover { hovering = $0 }
                .accessibilityLabel(Text(clash: .copy("Remove")))
            }
        } else {
            content()
        }
    }
}

 
 
 

extension View {
     
     
     
     
    @ViewBuilder
    public func clashIdiomFormPickerStyle() -> some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            self
        } else {
            pickerStyle(.segmented)
        }
    }
}

extension View {
     
     
     
     
     
     
     
     
    @ViewBuilder
    public func clashLabelsHiddenInSettingsIdiom() -> some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            labelsHidden()
        } else {
            self
        }
    }

     
     
    @ViewBuilder
    public func clashMacSettingsFootnote() -> some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            font(ClashMacSettingsType.footnote)
        } else {
            self
        }
    }
}

extension View {
     
     
     
    @ViewBuilder
    public func clashMacFormActionChrome() -> some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            buttonStyle(.bordered).tint(.primary)
        } else {
            self
        }
    }

     
     
     
     
     
     
     
     
    @ViewBuilder
    public func clashMacFormDestructiveActionChrome() -> some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            buttonStyle(.bordered).tint(.primary)
        } else {
            self
        }
    }
}

 
 
 
public struct ClashMacFormDestructiveLabel: View {
    private let text: ClashDisplayText
    @Environment(\.isEnabled) private var isEnabled

    public init(_ text: ClashDisplayText) { self.text = text }

    public var body: some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            Text(clash: text).foregroundStyle(isEnabled ? AnyShapeStyle(Color.red) : AnyShapeStyle(.secondary))
        } else {
            Text(clash: text)
        }
    }
}

extension View {
     
     
     
    @ViewBuilder
    public func clashMacListAddChrome() -> some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            buttonStyle(.bordered)
                .controlSize(.small)
                .tint(.primary)
        } else {
            self
        }
    }
}


 
 
 
 
 
 
 
 
 
 
@ViewBuilder
public func clashPromptField(
    _ placeholder: String,
    text: Binding<String>,
     
     
     
    identifier: String? = nil
) -> some View {
    if ClashPlatformLayout.pageUsesSystemSettingsIdiom,
       #available(iOS 16.0, macOS 13.0, *) {
         
         
         
         
         
        TextField(
            text: text,
            prompt: Text(verbatim: placeholder),
            axis: .vertical,
            label: { EmptyView() }
        )
        .lineLimit(1...4)
        .labelsHidden()
        .modifier(ClashOptionalIdentifier(identifier: identifier))
    } else {
        TextField(placeholder, text: text)
            .modifier(ClashOptionalIdentifier(identifier: identifier))
    }
}
