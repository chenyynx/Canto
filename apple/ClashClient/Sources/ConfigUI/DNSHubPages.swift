import ClashClientUI
import SwiftUI

 
 
 
 

 
 
enum DNSFieldRows {
     
     
     
     
     
     
     
     
     
     
     
    static func overrideMenuRow(
        _ title: String,
        _ selection: Binding<ProfileBooleanOverride>,
        inherited: InheritedBase,
        upstreamDefault: Bool,
        identifier: String
    ) -> some View {
        let state = InheritedBool(
            base: inherited,
            override: selection.wrappedValue.boolValue,
            upstreamDefault: upstreamDefault
        )
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
         
        let adopt: ClashInlineRowAction? = {
            guard state.profileDisagrees else { return nil }
            return ClashInlineRowAction(
                title: .copy("Use the profile's value"),
                identifier: "adopt-profile.\(identifier)"
            ) {
                selection.wrappedValue = .profileDefault
            }
        }()
        return menuRow(
            title: title,
            value: state.primaryTitle,
            subtitle: state.sourceLine,
            adopt: adopt,
            identifier: identifier
        ) {
            Picker(
                ClashCopy.key(title),
                selection: selection
            ) {
                 
                 
                Text(clash: state.followTitle)
                    .tag(
                        ProfileBooleanOverride
                            .profileDefault
                    )
                Text(ClashCopy.key("On"))
                    .tag(
                        ProfileBooleanOverride.enabled
                    )
                Text(ClashCopy.key("Off"))
                    .tag(
                        ProfileBooleanOverride.disabled
                    )
            }
             
             
             
             
             
             
             
             
             
             
             
             
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }


    static func menuRow<Content: View>(
        title: String,
        value: ClashDisplayText,
        subtitle: ClashDisplayText? = nil,
        adopt: ClashInlineRowAction? = nil,
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
#if os(macOS)
        Menu {
             
             
             
             
             
             
             
             
             
             
             
            content()
                .pickerStyle(.inline)
        } label: {
             
             
             
             
             
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(clash: value)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: true, vertical: false)
                    .lineLimit(1)
                Image(
                    systemName:
                        ClashSymbol.chevronUpChevronDown.name
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .frame(
                 
                 
                minHeight: ClashPlatformLayout.pageUsesSystemSettingsIdiom
                    ? 0
                    : ClashClientUI.ClashTheme.Control.fullWidthRowMinHeight
            )
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(title)
            .accessibilityValue(
                subtitle.map { Text(clash: value) + Text(verbatim: ", ") + Text(clash: $0) }
                    ?? Text(clash: value)
            )
            .accessibilityIdentifier(identifier)
        }
        .buttonStyle(.plain)
         
         
         
        .id("\(identifier)-\(value.rawValue)")
        .fixedSize()
        .clashSettingsMenuRow(title, subtitle: subtitle, adopt: adopt)
        .transaction {
            $0.animation = nil
        }
#else
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(ClashCopy.key(title))
                    .foregroundStyle(.primary)
                if let subtitle {
                     
                     
                     
                    HStack(spacing: ClashTheme.Spacing.compact) {
                        Text(clash: subtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        if let adopt {
                            ClashInlineRowActionLink(action: adopt)
                        }
                    }
                }
            }
            Spacer(minLength: ClashTheme.Spacing.compact)
            Menu {
                content()
            } label: {
                HStack(spacing: 4) {
                    Text(clash: value)
                        .fixedSize(
                            horizontal: true,
                            vertical: false
                        )
                        .lineLimit(1)
                    Image(
                        systemName:
                            ClashSymbol
                                .chevronUpChevronDown.name
                    )
                    .font(.caption2)
                }
            }
            .id(value.rawValue)
            .transaction {
                $0.animation = nil
            }
             
             
             
             
            .accessibilityValue(
                subtitle.map { Text(clash: value) + Text(verbatim: ", ") + Text(clash: $0) }
                    ?? Text(clash: value)
            )
            .accessibilityIdentifier(identifier)
        }
#endif
    }
}

 
 
struct DNSHubRow: View {
    let title: String
    let detail: String
    var value: String?

    var body: some View {
#if os(macOS)
         
         
         
         
        HStack(
            alignment: .center,
            spacing: ClashTheme.Spacing.row
        ) {
            Text(ClashCopy.key(title))
            Spacer(minLength: ClashTheme.Spacing.compact)
            if let value {
                Text(clash: .copy(value))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6.5)
#else
        HStack(
            alignment: .center,
            spacing: ClashTheme.Spacing.row
        ) {
            VStack(alignment: .leading, spacing: 2) {
                Text(ClashCopy.key(title))
                if !detail.isEmpty {
                    Text(ClashCopy.key(detail))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }
            }
            Spacer(minLength: ClashTheme.Spacing.compact)
            if let value {
                Text(clash: .copy(value))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
#endif
    }
}
