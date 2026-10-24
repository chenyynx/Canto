import ClashClientUI
import SwiftUI

 
 
 
public struct ClashMacSecondaryUnavailableView: View {
    private let destination: ClashMacSecondaryDestination

    public init(destination: ClashMacSecondaryDestination) {
        self.destination = destination
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ClashClientUI.ClashTheme.Spacing.section) {
                Text(destination.title)
                    .font(.largeTitle.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                ClashClientUI.ClashFeatureCard(
                    palette: ClashMacPlatformPresentation.palette
                ) {
                    ClashClientUI.ClashEmptyState(
                        title: "Not Available on This Mac Yet",
                        message: unavailableMessage
                    ) {
                        ClashSymbolImage(symbol: symbol)
                    }
                }
            }
            .frame(
                maxWidth: ClashClientUI.ClashTheme.Regular.Detail.maximumContentWidth,
                alignment: .leading
            )
            .padding(.horizontal, ClashClientUI.ClashTheme.Spacing.standard)
            .padding(.vertical, ClashClientUI.ClashTheme.Spacing.section)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(ClashMacPlatformPresentation.palette.canvas)
        .navigationTitle(destination.title)
        .accessibilityIdentifier("clash.mac.secondary.\(identifier)")
    }

    private var unavailableMessage: String {
        switch destination {
        case .rules, .activeRules, .dnsQuery,
             .runtimeConfiguration, .configuration:
            "This page needs the active profile configuration surface before it can make changes."
        case .utility:
            "This page needs a live, bounded diagnostic data source from the macOS Packet Tunnel."
        case .more:
            "This page needs its macOS platform capability before settings can be changed."
        case .profiles, .proxies:
            "This page needs its macOS product data source before it can be used."
        }
    }

    private var symbol: ClashSymbol {
        switch destination {
        case .profiles:
            .rectangleStackFill
        case .proxies:
            .proxyDomain
        case .rules:
            .ruleDomain
        case .activeRules:
            .listBulletRectangle
        case .dnsQuery:
            .globeAsiaAustralia
        case .runtimeConfiguration:
            .docText
        case .configuration:
            .gearshape
        case .utility(let destination):
            destination.symbol
        case .more(let destination):
            destination.symbol
        }
    }

    private var identifier: String {
        switch destination {
        case .profiles:
            "profiles"
        case .proxies:
            "proxies"
        case .rules:
            "rules"
        case .activeRules:
            "active-rules"
        case .dnsQuery:
            "dns-query"
        case .runtimeConfiguration:
            "runtime-configuration"
        case .configuration:
            "configuration"
        case .utility(let destination):
            "utility.\(destination.rawValue)"
        case .more(let destination):
            "more.\(destination.rawValue)"
        }
    }
}
