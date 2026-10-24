import SwiftUI

extension View {
     
     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashAlwaysEditing() -> some View {
#if os(macOS)
        self
#else
        environment(\.editMode, .constant(.active))
#endif
    }

     
     
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashSelectionRowFill(_ chosen: Bool) -> some View {
#if os(iOS)
        listRowBackground(chosen ? Color(uiColor: .systemFill) : nil)
#else
        self
#endif
    }

     
     
     
     
     
     
    @ViewBuilder
    public func clashBackButtonHidden(_ hidden: Bool) -> some View {
#if os(macOS)
        self
#else
        navigationBarBackButtonHidden(hidden)
#endif
    }
}

extension View {
     
     
     
     
     
     
     
     
    @ViewBuilder
    func clashEditorFormContainer<Rows: View>(
        @ViewBuilder rows: () -> Rows
    ) -> some View {
#if os(macOS)
        Form { rows() }
            .formStyle(.grouped)
#else
        List { rows() }
#endif
    }
}

 
 
extension View {
    @ViewBuilder
    public func clashConfigurationFormSpacing() -> some View {
        #if os(iOS)
        if #available(iOS 17.0, *) {
            self.listSectionSpacing(ClashTheme.Spacing.standard)
                .contentMargins(.top, ClashTheme.Spacing.tight, for: .scrollContent)
        } else { self }
        #else
        self
        #endif
    }
}

 
 
 
struct ClashProfilesRootTitleModifier: ViewModifier {
    let showsDismissControl: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if showsDismissControl {
#if os(iOS)
            content.clashPageTitle("Profile Center")
#else
            content.clashPageTitle("Profiles")
#endif
        } else {
            content
        }
    }
}


 
struct ClashConfigurationLibraryList<Content: View>: View {
    let palette: ClashProductPalette
    let accessibilityIdentifier: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        List { content() }
            .modifier(ClashConfigurationLibraryListStyle())
            .clashConfigurationFormSpacing()
            .background(palette.canvas)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}
private struct ClashConfigurationLibraryListStyle: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
#if os(iOS)
        content.listStyle(.insetGrouped)
#else
        content
#endif
    }
}

public extension View {
     
     
    func clashDeleteConfirmation(_ name: String, isPresented: Binding<Bool>,
                                actionTitle: ClashDisplayText = .copy("Delete"),
                                message: ClashDisplayText,
                                identifier: String,
                                action: @escaping () -> Void) -> some View {
        alert(Text(clash: .format("Delete %@?", [name])), isPresented: isPresented) {
            Button(role: .destructive, action: action) { Text(clash: actionTitle) }
                .accessibilityIdentifier(identifier)
            Button("Cancel", role: .cancel) {}
        } message: { Text(clash: message) }
    }
}
