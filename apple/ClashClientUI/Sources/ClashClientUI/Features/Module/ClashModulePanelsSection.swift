import ClashClientKit
import SwiftUI

 
 
 
 
struct ClashModulePanelsSection: View {
    let panels: [ClashModuleDetailSnapshot.Panel]
    let refresh: (String) -> Void

    var body: some View {
        Section {
            ForEach(panels) { panel in
                ClashModulePanelRow(panel: panel) { refresh(panel.id) }
            }
        } header: {
            Text("Panels")
        }
        .accessibilityIdentifier("modules.detail.panels")
    }
}

 
 
 
struct ClashModulePanelRow: View {
    let panel: ClashModuleDetailSnapshot.Panel
    let refresh: () -> Void
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

     
     
#if os(macOS)
    private static let circle: CGFloat = 22
    private static let titleFont = Font.body.weight(.semibold)
    private static let contentFont = Font.body
#else
    private static let titleFont = Font.headline
    private static let contentFont = Font.subheadline
#endif

    var body: some View {
        HStack(alignment: .top, spacing: ClashTheme.Spacing.row) {
            icon
            VStack(alignment: .leading, spacing: ClashTheme.Spacing.tight) {
                Text(verbatim: panel.title)
                    .font(Self.titleFont)
                    .fixedSize(horizontal: false, vertical: true)
                if panel.isRefreshing {
                    Text("Refreshing…")
                        .font(Self.contentFont)
                        .foregroundStyle(.secondary)
                } else if let content = panel.content, !content.isEmpty {
                    Text(verbatim: content)
                        .font(Self.contentFont)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !panel.isRefreshing, let line = footnote {
                    line
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if panel.refreshes {
                button
            }
        }
        .padding(.vertical, ClashMacSettingsMetrics.rowVerticalInset(touch: ClashTheme.Spacing.tight))
        .accessibilityIdentifier("modules.detail.panel.\(panel.id)")
    }

     
     
    private var footnote: Text? {
        if let status = panel.status {
            return Text(clash: status).foregroundColor(panel.statusIsFailure ? .red : .secondary)
        }
        guard let updated = panel.updatedAt else { return nil }
        return Text(verbatim: Self.updatedLine(updated, locale: locale)).foregroundColor(.secondary)
    }

     
     
    private var button: some View {
#if os(macOS)
        Button(action: refresh) {
            Text("Refresh")
        }
        .controlSize(.small)
        .clashMacFormActionChrome()
        .disabled(!panel.canRefresh || panel.isRefreshing)
        .accessibilityLabel(Text(clash: .format("Refresh %@", [panel.title])))
        .accessibilityIdentifier("modules.detail.panel.\(panel.id).refresh")
#else
        Button(action: refresh) {
            ZStack {
                if panel.isRefreshing {
                    ProgressView()
                } else {
                    Image(systemName: ClashSymbol.arrowClockwise.rawValue)
                        .font(.body.weight(.semibold))
                }
            }
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .disabled(!panel.canRefresh || panel.isRefreshing)
        .accessibilityLabel(Text(clash: .format("Refresh %@", [panel.title])))
        .accessibilityIdentifier("modules.detail.panel.\(panel.id).refresh")
#endif
    }

     
     
    private var circleSide: CGFloat {
#if os(macOS)
        Self.circle
#else
        dynamicTypeSize.isAccessibilitySize ? 44 : 30
#endif
    }

     
     
    @ViewBuilder
    private var icon: some View {
        if let name = panel.icon {
            let side = circleSide
            Image(systemName: name)
                 
                 
                .font(.system(size: side * 0.52, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: side, height: side)
                .background(Circle().fill(Self.color(panel.iconColor).map(AnyShapeStyle.init) ?? AnyShapeStyle(.tint)))
                .accessibilityHidden(true)
        }
    }

     
     
    nonisolated static func updatedLine(_ date: Date, locale: Locale, now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .full
        return formatter.localizedString(for: min(date, now.addingTimeInterval(-1)), relativeTo: now)
    }

     
    nonisolated static func color(_ written: String?) -> Color? {
        guard var hex = written?.trimmingCharacters(in: .whitespaces), hex.hasPrefix("#") else { return nil }
        hex.removeFirst()
        if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255,
                     blue: Double(value & 0xFF) / 255)
    }
}
