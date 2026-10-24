import AppKit
import Combine
import ClashClientUI

 
 
 
 
 
 
struct ClashMacStatusMenuSnapshot: Equatable {
    var phase: AppleClientConnectionPhase
    var primaryIntent: AppleClientConnectionIntent?
    var outboundMode: AppleClientOutboundMode
    var selectedRouteName: String?
    var proxies: ClashMacMenuProxyCatalog
    var showsSpeedInMenuBar: Bool
    var hidesDockIcon: Bool
    var upLine: String
    var downLine: String
     
     
    var offersQuitLeavingTunnel: Bool
     
     
     
    var offersShellCommand: Bool
    var offersExternalShellCommand: Bool
     
     
     
    var prefersLoopbackShellCommand: Bool
     
     
     
    var speedIsPaused = false
     
     
     
    var runsPreviousRevision = false
     
    var runningPreviousProfileName: String?
}

 
 
struct ClashMacStatusMenuActions {
    var primary: () -> Void = {}
    var cancelStart: () -> Void = {}
    var setOutboundMode: (AppleClientOutboundMode) -> Void = { _ in }
    var select: (_ group: String, _ member: String) -> Void = { _, _ in }
     
     
     
    var testGroup: (_ group: String) -> Bool = { _ in false }
     
     
    var openGroup: (_ group: String) -> Void = { _ in }
    var setShowsSpeedInMenuBar: (Bool) -> Void = { _ in }
    var setHidesDockIcon: (Bool) -> Void = { _ in }
    var openSettings: () -> Void = {}
    var openApp: () -> Void = {}
    var quitLeavingTunnel: () -> Void = {}
    var quit: () -> Void = {}
     
     
    var copyShellCommand: (_ externalIP: Bool) -> Void = { _ in }

    static let none = ClashMacStatusMenuActions()
}

 
 
 
final class ClashMacMenuRowAction: NSObject {
    private let perform: () -> Void

    init(_ perform: @escaping () -> Void) {
        self.perform = perform
    }

    @objc func fire(_ sender: Any?) {
        perform()
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum ClashMacStatusMenuBuilder {
    static func makeMenu(
        _ snapshot: ClashMacStatusMenuSnapshot,
        actions: ClashMacStatusMenuActions,
        locale: Locale = .current
    ) -> NSMenu {
        let menu = plainMenu()

        func copy(_ key: String) -> String {
            ClashCopy.string(key, locale: locale)
        }

        if snapshot.runsPreviousRevision {
            let notice = label(snapshot.runningPreviousProfileName.map {
                ClashCopy.format("Still running %@", locale: locale, $0)
            } ?? copy("Still running the previous version"))
            notice.setAccessibilityIdentifier("menu-bar.previous-revision")
            menu.addItem(notice)
            menu.addItem(.separator())
        }

         
         
         
         
        switch ClashMacMenuPrimaryRow.resolve(
            phase: snapshot.phase,
            intent: snapshot.primaryIntent
        ) {
        case .intent(let intent):
            menu.addItem(row(copy(intent.toolbarTitle), actions.primary))
        case .cancelStart:
            menu.addItem(row(copy("Cancel"), identifier: "menu-bar.cancel-start", actions.cancelStart))
        case .none:
            menu.addItem(label(copy(snapshot.phase.statusTitle)))
        }

         
         
         
         
         
         
        let mode = NSMenuItem(title: copy("Mode"), action: nil, keyEquivalent: "")
        mode.setAccessibilityIdentifier("menu-bar.outbound-mode")
        setTrailing(copy(snapshot.outboundMode.menuTitle), on: mode)
        let modes = plainMenu()
        for candidate in AppleClientOutboundMode.allCases {
            modes.addItem(row(
                copy(candidate.menuTitle),
                state: candidate == snapshot.outboundMode ? .on : .off
            ) { actions.setOutboundMode(candidate) })
        }
        mode.submenu = modes
        menu.addItem(mode)

        if let route = snapshot.selectedRouteName {
            menu.addItem(label(route))
        }

         
         
         
         
         
        if !snapshot.proxies.groups.isEmpty {
            menu.addItem(.separator())
            for group in snapshot.proxies.groups {
                let item = NSMenuItem(title: group.name, action: nil, keyEquivalent: "")
                item.setAccessibilityIdentifier("menu-bar.proxy-group")
                item.attributedTitle = groupTitle(name: group.name, type: group.type)
                if group.isEmpty {
                     
                    setTrailing(copy("No nodes"), on: item)
                    item.isEnabled = false
                    menu.addItem(item)
                    continue
                }
                setTrailing(group.checked ?? "", on: item)
                let submenu = plainMenu()
                let lazy = ClashMacProxySubmenuController(
                    group: { group }, actions: actions, locale: locale
                )
                submenu.delegate = lazy
                 
                item.representedObject = lazy
                item.submenu = submenu
                menu.addItem(item)
            }
        }

         
         
         
         
         
        menu.addItem(.separator())
        if snapshot.prefersLoopbackShellCommand {
            let loopback = row(
                copy("Copy Shell Command (127.0.0.1)"),
                identifier: "menu-bar.copy-shell-command-loopback"
            ) { actions.copyShellCommand(false) }
            loopback.isEnabled = snapshot.offersShellCommand
            menu.addItem(loopback)
        } else {
            let external = snapshot.offersExternalShellCommand
            let line = row(
                copy("Copy Shell Command"),
                identifier: "menu-bar.copy-shell-command"
            ) { actions.copyShellCommand(external) }
            line.isEnabled = snapshot.offersShellCommand
            menu.addItem(line)
        }

         
         
        menu.addItem(.separator())
        menu.addItem(row(
            copy("Show Speed in Menu Bar"),
            identifier: "menu-bar.shows-speed",
            state: snapshot.showsSpeedInMenuBar ? .on : .off
        ) { actions.setShowsSpeedInMenuBar(!snapshot.showsSpeedInMenuBar) })
        menu.addItem(row(
            copy("Hide Dock Icon"),
            identifier: "menu-bar.hides-dock-icon",
            state: snapshot.hidesDockIcon ? .on : .off
        ) { actions.setHidesDockIcon(!snapshot.hidesDockIcon) })
        if !snapshot.showsSpeedInMenuBar, !snapshot.speedIsPaused {
            menu.addItem(label(snapshot.upLine))
            menu.addItem(label(snapshot.downLine))
        }

         
        menu.addItem(.separator())
        menu.addItem(row(copy("Settings…"), identifier: "menu-bar.settings", actions.openSettings))
        menu.addItem(row(copy("Open Clash"), actions.openApp))

         
        menu.addItem(.separator())
        if snapshot.offersQuitLeavingTunnel {
            menu.addItem(row(
                copy("Quit (Leave VPN Active)"),
                identifier: "menu-bar.quit-leaving-tunnel",
                actions.quitLeavingTunnel
            ))
        }
        menu.addItem(row(copy("Quit Clash"), identifier: "menu-bar.quit", actions.quit))
        return menu
    }

     
     
    private static func plainMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        return menu
    }

     
     
     
     
     
    private static func setTrailing(_ text: String, on item: NSMenuItem) {
        guard !text.isEmpty else { return }
        if #available(macOS 14, *) {
            item.badge = NSMenuItemBadge(string: text)
        }
    }

     
     
     
    static func groupTitle(name: String, type: String) -> NSAttributedString {
        let font = ClashMacMenuRowMetrics.font
        let title = NSMutableAttributedString(string: name, attributes: [.font: font])
        guard !type.isEmpty else { return title }
        title.append(NSAttributedString(string: " · \(type)", attributes: [
            .font: NSFont.menuFont(ofSize: font.pointSize - 2),
            .foregroundColor: NSColor.secondaryLabelColor,
        ]))
        return title
    }

     
    private static func label(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func row(
        _ title: String,
        identifier: String? = nil,
        state: NSControl.StateValue = .off,
        _ perform: @escaping () -> Void
    ) -> NSMenuItem {
        let target = ClashMacMenuRowAction(perform)
        let item = NSMenuItem(
            title: title,
            action: #selector(ClashMacMenuRowAction.fire(_:)),
            keyEquivalent: ""
        )
        item.target = target
        item.representedObject = target
        item.state = state
        if let identifier {
            item.setAccessibilityIdentifier(identifier)
        }
        return item
    }
}

extension AppleClientConnectionPhase {
     
     
     
    var statusTitle: String {
        switch self {
        case .disconnected: "Disconnected"
        case .preparing: "STARTING"
        case .connected: "Connected"
        case .disconnecting: "STOPPING"
        case .unavailable: "Unavailable"
        }
    }
}

extension AppleClientConnectionIntent {
    var toolbarTitle: String {
        switch self {
        case .connect: "START"
        case .disconnect: "STOP"
        case .installConfiguration: "Set Up"
        case .activateSystemExtension: "Activate"
        case .updateSystemExtension: "Update"
        }
    }
}

extension AppleClientOutboundMode {
    var menuTitle: String {
        switch self {
        case .global: "Global"
        case .rule: "Rule"
        case .direct: "Direct"
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
final class ClashMacStatusMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    private let snapshot: () -> ClashMacStatusMenuSnapshot
    private let actions: ClashMacStatusMenuActions
    private let locale: Locale
    private let optionIsHeld: () -> Bool
    private let tunnelIsUp: () -> Bool
    private let latency: AnyPublisher<[String: [String: ClashProxyLatencyState]], Never>?
    private let testing: AnyPublisher<Bool, Never>?
    private let listenerUpdates: AnyPublisher<Void, Never>?
    private var listening: Set<AnyCancellable> = []

     
     
    var isListening: Bool { !listening.isEmpty }

    init(
        snapshot: @escaping () -> ClashMacStatusMenuSnapshot,
        actions: ClashMacStatusMenuActions,
        locale: Locale = .current,
        optionIsHeld: @escaping () -> Bool = { NSEvent.modifierFlags.contains(.option) },
        tunnelIsUp: @escaping () -> Bool = { false },
        latency: AnyPublisher<[String: [String: ClashProxyLatencyState]], Never>? = nil,
        testing: AnyPublisher<Bool, Never>? = nil,
        listenerUpdates: AnyPublisher<Void, Never>? = nil
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.locale = locale
        self.optionIsHeld = optionIsHeld
        self.tunnelIsUp = tunnelIsUp
        self.latency = latency
        self.testing = testing
        self.listenerUpdates = listenerUpdates
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
    }

     
     
     
     
     
     
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.items.isEmpty else { return }
        var current = snapshot()
        current.offersQuitLeavingTunnel = optionIsHeld() && tunnelIsUp()
         
        current.prefersLoopbackShellCommand = optionIsHeld()
        let built = ClashMacStatusMenuBuilder.makeMenu(current, actions: actions, locale: locale)
        for item in built.items {
            built.removeItem(item)
            menu.addItem(item)
        }
    }

     
     
     
    func menuWillOpen(_ menu: NSMenu) {
         
         
         
         
        if let container = ClashAppIdentifiers.appGroupContainer, ModuleEngineReadinessSource.observesInThisProcess {
            ModuleEngineReadinessSource.shared(container).scheduleRecheck()
        }
        listening.removeAll()
        listenerUpdates?
            .sink { [weak self] in self?.refreshCopyCommand() }
            .store(in: &listening)
         
        if listenerUpdates != nil { refreshCopyCommand() }
        latency?
            .sink { [weak self] latency in self?.apply(latency: latency) }
            .store(in: &listening)
        testing?
            .sink { [weak self] isTesting in self?.setTesting(isTesting) }
            .store(in: &listening)
    }

    private func refreshCopyCommand() {
        guard let item = menu.items.first(where: {
            ["menu-bar.copy-shell-command", "menu-bar.copy-shell-command-loopback"].contains($0.accessibilityIdentifier())
        }) else { return }
        let current = snapshot()
        let external = item.accessibilityIdentifier() != "menu-bar.copy-shell-command-loopback"
            && current.offersExternalShellCommand
        let copy = actions.copyShellCommand
        let target = ClashMacMenuRowAction { copy(external) }
        item.target = target
        item.representedObject = target
        item.isEnabled = current.offersShellCommand
    }

    func menuDidClose(_ menu: NSMenu) {
        listening.removeAll()
        menu.removeAllItems()
    }

     
     
     
     
    func apply(latency: [String: [String: ClashProxyLatencyState]]) {
        for item in menu.items {
            guard let submenu = item.representedObject as? ClashMacProxySubmenuController,
                  let name = submenu.groupName else { continue }
            submenu.apply(latency: latency[name] ?? [:])
        }
    }

     
    func setTesting(_ isTesting: Bool) {
        for item in menu.items {
            (item.representedObject as? ClashMacProxySubmenuController)?.setTesting(isTesting)
        }
    }
}

 
 
 
 
 
 
 
 
 
 
 
 
 
@MainActor
enum ClashMacStatusItemLabel {
     
     
    static let dimmedCatAlpha: CGFloat = 0.5

    static func image(showsSpeed: Bool, upLine: String, downLine: String, tunnelIsUp: Bool) -> NSImage? {
        let catAlpha: CGFloat = tunnelIsUp ? 1 : dimmedCatAlpha
        if showsSpeed,
           let drawn = ClashMacMenuBarSpeed.menuBarImage(upLine: upLine, downLine: downLine, catAlpha: catAlpha) {
            drawn.isTemplate = true
            return drawn
        }
         
         
        guard let cat = NSImage(named: ClashMacAsset.menuBarTemplate.rawValue) else { return nil }
        cat.isTemplate = true
        if catAlpha == 1 { return cat }
        let dimmed = NSImage(size: cat.size, flipped: false) { rect in
            cat.draw(in: rect, from: .zero, operation: .sourceOver, fraction: catAlpha)
            return true
        }
        dimmed.isTemplate = true
        return dimmed
    }

    static func accessibilityLabel(showsSpeed: Bool, upLine: String, downLine: String) -> String {
        showsSpeed ? "Clash — \(upLine), \(downLine)" : "Clash"
    }
}

extension ClashMacStatusMenuSnapshot {
     
    static let empty = ClashMacStatusMenuSnapshot(
        phase: .unavailable,
        primaryIntent: nil,
        outboundMode: .rule,
        selectedRouteName: nil,
        proxies: ClashMacMenuProxyCatalog(groups: []),
        showsSpeedInMenuBar: false,
        hidesDockIcon: false,
        upLine: "",
        downLine: "",
        offersQuitLeavingTunnel: false,
        offersShellCommand: false,
        offersExternalShellCommand: false,
        prefersLoopbackShellCommand: false
    )
}

