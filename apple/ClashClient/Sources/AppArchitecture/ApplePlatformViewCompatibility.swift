import ClashClientUI
import SwiftUI

 
 
 
 
 
 
let clashAppleRuntimeProfile: ClashAppleRuntimeProfile = {
    guard let profile = ClashAppleRuntimeProfile(rawValue: clashAppleRuntimeProfileName) else {
         
         
         
         
        preconditionFailure("no ClashAppleRuntimeProfile for \(clashAppleRuntimeProfileName)")
    }
    return profile
}()

extension View {
    @ViewBuilder
    func clashStackNavigationViewStyle() -> some View {
#if os(macOS)
        self
#else
        navigationViewStyle(.stack)
#endif
    }

    @ViewBuilder
    func clashInsetGroupedListStyle() -> some View {
#if os(macOS)
         
         
         
         
         
         
        listStyle(.inset)
            .scrollDismissesKeyboard(.immediately)
#else
        listStyle(.insetGrouped)
#endif
    }

    @ViewBuilder
    func clashCapsuleButtonBorderShape() -> some View {
#if os(macOS)
        if #available(macOS 14.0, *) {
            buttonBorderShape(.capsule)
        } else {
            self
        }
#else
        buttonBorderShape(.capsule)
#endif
    }
}

extension ToolbarItemPlacement {
    static var clashNavigationTrailing: ToolbarItemPlacement {
#if os(macOS)
        .primaryAction
#else
        .navigationBarTrailing
#endif
    }
}

struct ClashEditButton: View {
    var body: some View {
#if os(macOS)
        EmptyView()
#else
        EditButton()
#endif
    }
}
