import ClashClientUI
import SwiftUI

struct ConnectionCard: View {
    let connection: ConnectionPresentation
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        ClashOverviewCard {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.row) {
                OverviewCardHeader(
                    title: "Connection",
                    symbol: connection.symbol,
                    tint: .blue,
                    badge: OverviewBadge(title: connection.badgeTitle, tint: connection.statusTint)
                )

                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    Text(clash: .copy(connection.title))
                        .font(.headline)
                    Text(clash: .copy(connection.subtitle))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                connectionAction
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.card.connection")
    }

    @ViewBuilder
    private var connectionAction: some View {
        if connection.isBusy {
            HStack(spacing: ClashTheme.Spacing.compact) {
                ProgressView()
                Text("Working…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(
                minHeight: ClashClientUI.ClashTheme.Control.minimumHitTarget
            )
        } else if connection.isConnected {
            Button(role: .destructive, action: stop) {
                Label("Disconnect", systemImage: ClashSymbol.power.name)
                    .frame(maxWidth: .infinity)
            }
            .clashSecondaryActionButtonStyle()
            .controlSize(.large)
            .accessibilityIdentifier("overview.connection.action")
        } else {
            Button(action: start) {
                Label(connection.actionTitle, systemImage: ClashSymbol.power.name)
                    .frame(maxWidth: .infinity)
            }
            .clashPrimaryActionButtonStyle()
            .controlSize(.large)
            .accessibilityIdentifier("overview.connection.action")
        }
    }
}

struct OverviewErrorCard: View {
    let message: String

    var body: some View {
        ClashOverviewCard {
            Label {
                Text(clash: .verbatim(message))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: ClashSymbol.exclamationmarkTriangleFill.name)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.red)
            .accessibilityElement(children: .combine)
        }
    }
}

struct OverviewNoticeCard: View {
    let message: String

    var body: some View {
        ClashOverviewCard {
            Label {
                Text(clash: .verbatim(message))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: ClashSymbol.exclamationmarkTriangleFill.name)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.orange)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("overview.configuration.notice")
        }
    }
}

struct TrafficCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.clashThroughputUnit) private var throughputUnit

    let traffic: OverviewTrafficSnapshot

    var body: some View {
        ClashOverviewCard {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                OverviewCardHeader(
                    title: "Live Traffic",
                    symbol: .waveformPathEcg,
                    tint: .orange
                )

                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: ClashTheme.Spacing.row) {
                        uploadMetric
                        downloadMetric
                    }
                } else {
                    HStack(alignment: .top, spacing: ClashTheme.Spacing.row) {
                        uploadMetric
                        downloadMetric
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.card.traffic")
    }

    private var uploadMetric: some View {
        TrafficMetric(
            title: "Upload",
            symbol: .arrowUp,
            rate: ByteRateFormatter.string(traffic.upload, unit: throughputUnit),
            total: ByteCountFormatter.string(traffic.uploadTotal)
        )
    }

    private var downloadMetric: some View {
        TrafficMetric(
            title: "Download",
            symbol: .arrowDown,
            rate: ByteRateFormatter.string(traffic.download, unit: throughputUnit),
            total: ByteCountFormatter.string(traffic.downloadTotal)
        )
    }
}

private struct TrafficMetric: View {
    let title: String
    let symbol: ClashSymbol
    let rate: String
    let total: String

    var body: some View {
        VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
            Label { Text(clash: .copy(title)) } icon: { Image(systemName: symbol.name).accessibilityHidden(true) }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(rate)
                .font(.system(.headline, design: .monospaced))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text("Total \(total)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(ClashTheme.Spacing.row)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: ClashTheme.Radius.control, style: .continuous)
                .fill(ClashTheme.raisedFill)
        )
        .accessibilityElement(children: .combine)
    }
}

 
 
 
 
struct RoutingCard: View {
    let routing: OverviewRoutingSnapshot
    let setMode: (String) -> Void

    private var normalizedMode: String {
        Self.validModes.contains(routing.mode.lowercased()) ? routing.mode.lowercased() : "rule"
    }

    var body: some View {
        ClashOverviewCard {
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.standard) {
                OverviewCardHeader(
                    title: "Outbound Mode",
                    symbol: .arrowTriangleBranch,
                    tint: .purple
                )

                VStack(alignment: .leading, spacing: ClashTheme.Spacing.compact) {
                    ForEach(RoutingMode.options) { option in
                        RoutingModeRow(
                            option: option,
                            isSelected: option.id == normalizedMode,
                            select: { setMode(option.id) }
                        )
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("overview.card.routing")
    }

    private static let validModes = Set(RoutingMode.options.map(\.id))
}

struct RoutingMode: Identifiable {
    let id: String
    let title: String
    let subtitle: String

    static let options = [
        RoutingMode(id: "rule", title: "Rule-Based Proxy", subtitle: "Match the configured routing rules"),
        RoutingMode(id: "global", title: "Global Proxy", subtitle: "Send traffic through the selected proxy"),
        RoutingMode(id: "direct", title: "Direct Outbound", subtitle: "Send traffic to its destination directly"),
    ]
}

struct RoutingModeRow: View {
    let option: RoutingMode
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(alignment: .top, spacing: ClashTheme.Spacing.row) {
                ClashSelectionMark(isSelected: isSelected)

                VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                    Text(clash: .copy(option.title))
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(clash: .copy(option.subtitle))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(ClashTheme.Spacing.row)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.title)
        .accessibilityValue(isSelected ? "Selected" : "")
        .accessibilityIdentifier("overview.mode.\(option.id)")
    }
}
