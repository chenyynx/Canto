import ClashClientUI
import SwiftUI

struct EgressCard: View {
    let egress: OverviewEgressSnapshot
    let checkEgress: () -> Void

    var body: some View {
        ClashOverviewCard {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                OverviewCardHeader(
                    title: "Egress",
                    symbol: .network,
                    tint: .green
                )

                VStack(spacing: ClashTheme.Spacing.row) {
                    OverviewValueRow(title: "Address", value: .verbatim(egress.address))
                     
                     
                    OverviewValueRow(
                        title: "Country",
                        value: .verbatim(egress.countryDisplay),
                        valueView: AnyView(
                            ClashRegionalFlag.label(egress.countryDisplay, pointSize: 15, relativeTo: .subheadline)
                        )
                    )
                        .accessibilityIdentifier("overview.egress.country")
                    OverviewValueRow(title: "Provider", value: .verbatim(egress.provider))
                    OverviewValueRow(title: "LAN", value: .verbatim(IntranetAddress.current() ?? "—"))
                }

                Button(action: checkEgress) {
                    Label(
                        egress.isChecking ? "Checking…" : "Check Egress",
                        systemImage: ClashSymbol.arrowClockwise.name
                    )
                    .frame(maxWidth: .infinity)
                }
                .clashSecondaryActionButtonStyle()
                .controlSize(.large)
                .disabled(egress.isChecking)
                .accessibilityIdentifier("overview.egress.check")

                Text("Confirms the public address used by the active tunnel.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.card.egress")
    }
}

 
 
 
struct RuntimeCard: View {
    let runtime: OverviewRuntimeSnapshot
    let collectGarbage: () -> Void

    var body: some View {
        ClashOverviewCard {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                OverviewCardHeader(
                    title: "Runtime",
                    symbol: .cpu,
                    tint: .indigo
                )

                VStack(spacing: ClashTheme.Spacing.row) {
                    RuntimeMetricRow(title: "Core", value: .verbatim(runtime.coreVersion), symbol: .cpu)
                    RuntimeMetricRow(
                        title: "Memory",
                        value: .verbatim(String(format: "%.1f MB", runtime.memoryMB)),
                        symbol: .memorychip
                    )
                }

                Button(action: collectGarbage) {
                    Label(
                        runtime.isCollectingMemory ? "Releasing Memory…" : "Release Memory",
                        systemImage: ClashSymbol.arrowClockwise.name
                    )
                    .frame(maxWidth: .infinity)
                }
                .clashSecondaryActionButtonStyle()
                .controlSize(.large)
                .disabled(runtime.isCollectingMemory)
                .accessibilityIdentifier("overview.runtime.gc")

                if !runtime.memoryActionMessage.isEmpty {
                    Text(clash: .copy(runtime.memoryActionMessage))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("overview.runtime.gc.status")
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.card.runtime")
    }
}

struct RuntimeMetricRow: View {
    let title: ClashDisplayText
    let value: ClashDisplayText
    let symbol: ClashSymbol

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashTheme.Spacing.row) {
            Label { Text(clash: title) } icon: { Image(systemName: symbol.name).accessibilityHidden(true) }
                .foregroundStyle(.primary)
            Spacer(minLength: ClashTheme.Spacing.row)
            Text(clash: value)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}
