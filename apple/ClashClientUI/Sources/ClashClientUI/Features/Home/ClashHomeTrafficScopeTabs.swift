import SwiftUI

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
struct ClashHomeTrafficScopeTabs: View {
    @Environment(\.locale) private var locale
    @Binding var scope: ClashHomeTrafficScope

    var body: some View {
        ClashFullWidthSegmentedPicker(
            selection: $scope,
            options: [
                ClashFullWidthSegmentedOption(
                    selection: .proxiedOnly,
                    title: ClashCopy.string(
                        "Proxied only",
                        locale: locale
                    ),
                    accessibilityIdentifier: "home.traffic.scope.proxied"
                ),
                ClashFullWidthSegmentedOption(
                    selection: .allTraffic,
                    title: ClashCopy.string("All traffic", locale: locale),
                    accessibilityIdentifier: "home.traffic.scope.all"
                ),
            ],
            role: .inlineControl
        )
    }
}
