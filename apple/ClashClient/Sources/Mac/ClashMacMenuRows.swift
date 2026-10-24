import AppKit
import ClashClientUI
import SwiftUI

 
 
 
@MainActor
final class ClashMacMenuRowModel: ObservableObject {
    enum Kind: Equatable {
         
        case member
         
        case test
         
         
        case more
    }

    let kind: Kind
    let name: String
     
     
    var emptyNote: String?
    @Published var latency: ClashProxyLatencyState
    @Published var isCurrent: Bool
    @Published var isHighlighted = false
    @Published var isTesting = false

    init(
        kind: Kind,
        name: String,
        latency: ClashProxyLatencyState = .untested,
        isCurrent: Bool = false,
        emptyNote: String? = nil
    ) {
        self.kind = kind
        self.name = name
        self.emptyNote = emptyNote
        self.latency = latency
        self.isCurrent = isCurrent
    }

     
     
     
    var badgeText: String {
        if let emptyNote { return emptyNote }
        return switch latency {
        case .measured(let milliseconds): "\(milliseconds) ms"
        case .failed, .timedOut: "—"
        case .untested, .testing: ""
        }
    }
}

 
 
 
 
struct ClashMacMenuRow: View {
    @ObservedObject var model: ClashMacMenuRowModel
    let pointSize: CGFloat

    var body: some View {
        HStack(spacing: 0) {
             
            Group {
                if model.isCurrent {
                    Image(systemName: ClashSymbol.checkmark.rawValue)
                        .font(.system(size: pointSize - 2, weight: .semibold))
                } else {
                    Color.clear
                }
            }
            .frame(width: ClashMacMenuRowMetrics.leadingColumn, alignment: .center)

            ClashRegionalFlag.label(model.name, pointSize: pointSize, relativeTo: .body)
                .font(.system(size: pointSize))
                .lineLimit(1)
                .truncationMode(.middle)
                 
                 
                 
                 
                 

            Spacer(minLength: 8)

            switch model.kind {
            case .test:
                 
                 
                if model.isTesting {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: ClashSymbol.bolt.rawValue)
                        .font(.system(size: pointSize - 1, weight: .semibold))
                        .foregroundStyle(model.isHighlighted ? .white : .secondary)
                }
            case .member:
                badge
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
            case .more:
                EmptyView()
            }
        }
        .padding(.trailing, 8)
        .frame(height: ClashMacMenuRowHost.rowHeight)
        .background(
            model.isHighlighted
                ? Color(nsColor: .selectedContentBackgroundColor)
                : Color.clear,
            in: RoundedRectangle(cornerRadius: 5, style: .continuous)
        )
        .padding(.horizontal, ClashMacMenuRowMetrics.highlightInset)
        .foregroundStyle(model.isHighlighted ? Color.white : Color(nsColor: .labelColor))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: accessibilityDescription))
         
         
        .accessibilityValue(model.isCurrent ? "Selected" : "")
    }

     
     
     
     
    @ViewBuilder
    private var badge: some View {
        if let note = model.emptyNote {
            Text(verbatim: note)
                .font(.system(size: pointSize - 3, weight: .medium))
                .foregroundStyle(model.isHighlighted ? .white : .secondary)
                .padding(.horizontal, 6)
        } else {
            latencyBadge
        }
    }

    @ViewBuilder
    private var latencyBadge: some View {
        switch model.latency {
        case .measured:
             
             
             
             
             
             
             
            Text(verbatim: model.badgeText)
                .font(.system(size: pointSize - 3, weight: .semibold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(model.isHighlighted ? Color.white : tierInk)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(
                    tierColor.opacity(model.isHighlighted ? 0.45 : 0.22),
                    in: Capsule()
                )
        case .failed, .timedOut:
            Text(verbatim: model.badgeText)
                .font(.system(size: pointSize - 3, weight: .medium, design: .monospaced))
                .foregroundStyle(model.isHighlighted ? .white : .secondary)
                .padding(.horizontal, 6)
        case .testing:
            ProgressView()
                .controlSize(.mini)
        case .untested:
            EmptyView()
        }
    }

     
     
    private var tierColor: Color {
        switch model.latency.tier {
        case .fast: .green
        case .slow: .yellow
        case .slower: .orange
        case nil: .secondary
        }
    }

     
     
     
     
    private var tierInk: Color {
        let tier = tierColor
        return Color(nsColor: NSColor(name: nil) { appearance in
            let base = NSColor(tier)
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua { return base }
            return base.blended(withFraction: 0.4, of: .black) ?? base
        })
    }

    private var accessibilityDescription: String {
        var parts = [model.name]
        if !model.badgeText.isEmpty { parts.append(model.badgeText) }
        return parts.joined(separator: ", ")
    }
}

 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacMenuRowHost: NSHostingView<ClashMacMenuRow> {
     
     
     
     
     
    static let rowHeight: CGFloat = {
        func height(rows: Int) -> CGFloat {
            let menu = NSMenu()
            for _ in 0..<rows {
                menu.addItem(NSMenuItem(title: "Sample", action: nil, keyEquivalent: ""))
            }
            return menu.size.height
        }
        let measured = height(rows: 2) - height(rows: 1)
        return measured > 0 ? measured : 22
    }()

    var model: ClashMacMenuRowModel { rootView.model }
     
     
    var closesMenuOnClick = true
    var onClick: () -> Void = {}

    static func make(
        model: ClashMacMenuRowModel,
        width: CGFloat,
        pointSize: CGFloat,
        closesMenuOnClick: Bool,
        onClick: @escaping () -> Void
    ) -> ClashMacMenuRowHost {
        let host = ClashMacMenuRowHost(rootView: ClashMacMenuRow(model: model, pointSize: pointSize))
        host.closesMenuOnClick = closesMenuOnClick
        host.onClick = onClick
        host.sizingOptions = []
        host.frame = NSRect(x: 0, y: 0, width: width, height: rowHeight)
        host.autoresizingMask = [.width]
        return host
    }

    required init(rootView: ClashMacMenuRow) {
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ClashMacMenuRowHost is built in code")
    }

    override func mouseUp(with event: NSEvent) {
        performClick()
    }

     
     
    func performClick() {
        if closesMenuOnClick {
            enclosingMenuItem?.menu?.cancelTracking()
        }
        onClick()
    }
}

 
 
 
 
 
 
 
@MainActor
enum ClashMacMenuRowMetrics {
    static var font: NSFont { NSFont.menuFont(ofSize: 0) }
    static var pointSize: CGFloat { font.pointSize }

     
     
     
    static let memberCap: CGFloat = 300

     
    static let highlightInset: CGFloat = 5
     
     
    static let leadingColumn: CGFloat = 19

     
     
     
    private static let chrome: CGFloat = highlightInset * 2 + leadingColumn + 8 + 8

    private static func widest(_ strings: [String]) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        return (strings + [""]).map { ($0 as NSString).size(withAttributes: attributes).width }.max() ?? 0
    }

     
     
     
     
    static func memberRowWidth(names: [String], note: String? = nil) -> CGFloat {
        let sample = ClashMacMenuRowModel(kind: .member, name: "", latency: .measured(milliseconds: 999)).badgeText
        let digits = (sample as NSString).size(withAttributes: [
            .font: NSFont.monospacedDigitSystemFont(ofSize: pointSize - 3, weight: .medium),
        ]).width
        let words = ((note ?? "") as NSString).size(withAttributes: [
            .font: NSFont.systemFont(ofSize: pointSize - 3, weight: .medium),
        ]).width
        let badge = max(digits, words) + 12
        return min(memberCap, (chrome + widest(names) + badge).rounded(.up))
    }
}

 
 
 
 
 
 
 
 
@MainActor
final class ClashMacProxySubmenuController: NSObject, NSMenuDelegate {
    private let group: () -> ClashMacMenuProxyCatalog.Group?
    private let actions: ClashMacStatusMenuActions
    private let locale: Locale
    private(set) var rows: [String: ClashMacMenuRowModel] = [:]
    private(set) var testRow: ClashMacMenuRowModel?

     
    var groupName: String? { group()?.name }

    init(
        group: @escaping () -> ClashMacMenuProxyCatalog.Group?,
        actions: ClashMacStatusMenuActions,
        locale: Locale
    ) {
        self.group = group
        self.actions = actions
        self.locale = locale
    }

     
     
     
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.items.isEmpty else { return }
        rows = [:]
        testRow = nil
        guard let group = group() else { return }
        let pointSize = ClashMacMenuRowMetrics.pointSize
        let noNodes = ClashCopy.string("No nodes", locale: locale)
         
         
        let showAll = group.memberTotal.map {
            ClashCopy.format("Show All %@ Nodes…", locale: locale, $0.formatted(.number.locale(locale)))
        }
        let width = ClashMacMenuRowMetrics.memberRowWidth(
            names: group.members + [ClashCopy.string("Test latency", locale: locale)] + (showAll.map { [$0] } ?? []),
            note: group.emptyMembers.isEmpty ? nil : noNodes
        )

        let test = ClashMacMenuRowModel(kind: .test, name: ClashCopy.string("Test latency", locale: locale))
        let testItem = NSMenuItem(title: test.name, action: nil, keyEquivalent: "")
        testItem.setAccessibilityIdentifier("menu-bar.test-group")
        testItem.view = ClashMacMenuRowHost.make(
            model: test, width: width, pointSize: pointSize, closesMenuOnClick: false
        ) { [weak self, weak test] in
            if self?.actions.testGroup(group.name) == true { test?.isTesting = true }
        }
        testRow = test
        menu.addItem(testItem)
        menu.addItem(.separator())

        for member in group.members {
             
            let isCurrent = member == group.checked
            let model = ClashMacMenuRowModel(
                kind: .member,
                name: member,
                latency: group.latency[member] ?? .untested,
                isCurrent: isCurrent,
                emptyNote: group.emptyMembers.contains(member) ? noNodes : nil
            )
            let pick = { [actions] in
                 
                 
                guard !isCurrent || group.pinsOnRepick else { return }
                actions.select(group.name, member)
            }
            let target = ClashMacMenuRowAction(pick)
            let item = NSMenuItem(
                title: member,
                action: #selector(ClashMacMenuRowAction.fire(_:)),
                keyEquivalent: ""
            )
            item.target = target
            item.representedObject = target
            item.state = isCurrent ? .on : .off
            item.view = ClashMacMenuRowHost.make(
                model: model, width: width, pointSize: pointSize, closesMenuOnClick: true, onClick: pick
            )
            rows[member] = model
            menu.addItem(item)
        }
        if let showAll {
            menu.addItem(.separator())
            let more = ClashMacMenuRowModel(kind: .more, name: showAll)
            let open = { [actions] in actions.openGroup(group.name) }
            let target = ClashMacMenuRowAction(open)
            let item = NSMenuItem(title: showAll, action: #selector(ClashMacMenuRowAction.fire(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = target
            item.setAccessibilityIdentifier("menu-bar.show-all-members")
            item.view = ClashMacMenuRowHost.make(
                model: more, width: width, pointSize: pointSize, closesMenuOnClick: true, onClick: open
            )
            menu.addItem(item)
        }
    }

     
     
     
     
     
    func menuDidClose(_ menu: NSMenu) {
        for item in menu.items {
            (item.view as? ClashMacMenuRowHost)?.model.isHighlighted = false
        }
    }

    func menu(_ menu: NSMenu, willHighlight item: NSMenuItem?) {
        for candidate in menu.items {
            (candidate.view as? ClashMacMenuRowHost)?.model.isHighlighted = candidate === item
        }
    }

     
    func apply(latency: [String: ClashProxyLatencyState]) {
        for (name, model) in rows where model.emptyNote == nil {
            if let fresh = latency[name], fresh != model.latency {
                model.latency = fresh
            }
        }
    }

    func setTesting(_ isTesting: Bool) {
        testRow?.isTesting = isTesting
    }
}
