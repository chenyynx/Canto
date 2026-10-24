import SwiftUI

extension View {
     
     
     
     
     
     
     
    @ViewBuilder
    public func clashMacSettingsForm() -> some View {
         
         
         
         
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom,
           #available(iOS 16.0, macOS 13.0, *) {
            formStyle(.grouped)
                 
                 
                 
                 
                .environment(\.defaultMinListRowHeight, 0)
        } else {
            self
        }
    }
}

 
 
 
 
 
public struct ClashMacSettingsFormContainer<Content: View>: View {
    private let content: () -> Content
    private let restoreDefaults: (() -> Void)?
    private let scopeFooter: ClashDisplayText?

     
     
     
     
     
     
     
     
     
     
     
     
    public init(
        restoreDefaults: (() -> Void)? = nil,
        scopeFooter: ClashDisplayText? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.restoreDefaults = restoreDefaults
        self.scopeFooter = scopeFooter
        self.content = content
    }

    public var body: some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom,
           #available(iOS 16.0, macOS 13.0, *) {
            Form {
                content()
                scopeSection
                restoreSection
            }
                .formStyle(.grouped)
                .environment(\.defaultMinListRowHeight, 0)
        } else {
            Form {
                content()
                scopeSection
                restoreSection
            }
        }
    }

    @ViewBuilder
    private var scopeSection: some View {
        if let scopeFooter {
            Section {
            } footer: {
                Text(clash: scopeFooter)
                    .accessibilityIdentifier("overrides.scope-footer")
            }
        }
    }

    @ViewBuilder
    private var restoreSection: some View {
        if let restoreDefaults {
            Section {
                Button(action: restoreDefaults) {
                    Text(ClashCopy.key("Restore profile values"))
                }
                .accessibilityIdentifier("overrides.restore-profile-values")
            }
        }
    }
}

extension View {
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    public func clashMacSettingsList(
        minRowHeight: CGFloat = 0
    ) -> some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom {
            listStyle(.inset)
                .environment(\.defaultMinListRowHeight, minRowHeight)
        } else {
            self
        }
    }
}

 
 
 
 
 
 
 
public struct ClashMacSettingsContainer<Content: View>: View {
    private let content: () -> Content

    public init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    public var body: some View {
        if ClashPlatformLayout.pageUsesSystemSettingsIdiom,
           #available(iOS 16.0, macOS 13.0, *) {
            Form(content: content)
                .formStyle(.grouped)
                .environment(\.defaultMinListRowHeight, 0)
        } else {
            List(content: content)
        }
    }
}


extension View {
     
     
     
     
     
    @ViewBuilder
    public func clashModalListMargins() -> some View {
        modifier(ClashModalListMarginsModifier())
    }
}

private struct ClashModalListMarginsModifier: ViewModifier {
    @Environment(\.clashNavigationHostContext) private var hostContext
    @Environment(\.clashInsideModalPresentation) private var insideModal

    func body(content: Content) -> some View {
        if hostContext == .modal || insideModal {
            content.padding(.horizontal, ClashTheme.Spacing.standard)
        } else {
            content
        }
    }
}
