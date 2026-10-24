import SwiftUI

private struct ClashHomeIssueOpensAccountKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
     
     
     
     
     
     
     
     
     
    public var clashHomeIssueOpensAccount: Bool {
        get { self[ClashHomeIssueOpensAccountKey.self] }
        set { self[ClashHomeIssueOpensAccountKey.self] = newValue }
    }
}

 
 
 
 
 
 
 
 
struct ClashHomeIssueLineLabel: View {
    let text: ClashDisplayText
     
     
    let offersReason: Bool
    let isAccessibilitySize: Bool
    @Environment(\.clashHomeIssueOpensAccount) private var opensAccount

    var showsReason: Bool { offersReason && opensAccount }

    var body: some View {
        if isAccessibilitySize {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                Text(clash: text)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if showsReason { reason }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: ClashTheme.Spacing.compact) {
                Text(clash: text)
                    .multilineTextAlignment(.leading)
                     
                     
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .truncationMode(.tail)
                if showsReason {
                    Spacer(minLength: 0)
                     
                    reason
                        .fixedSize()
                        .layoutPriority(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reason: some View {
        HStack(spacing: 2) {
            Text(clash: .copy("View Reason"))
            Image(systemName: ClashSymbol.chevronForward.rawValue)
                .font(.footnote.weight(.semibold))
                .imageScale(.small)
        }
         
        .foregroundStyle(.tint)
        .accessibilityHidden(true)
    }
}

 
 
struct ClashHomeIssueLineHint: ViewModifier {
    let resetsVPNProfile: Bool
    @Environment(\.clashHomeIssueOpensAccount) private var opensAccount

    func body(content: Content) -> some View {
        content.accessibilityHint(
            resetsVPNProfile
                ? Text(clash: .copy("Reinstalls the VPN profile"))
                : opensAccount ? Text(clash: .copy("Shows why")) : Text("")
        )
    }
}
