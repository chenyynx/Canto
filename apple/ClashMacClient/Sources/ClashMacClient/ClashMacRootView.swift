import ClashClientUI
import SwiftUI

private enum CantoMacSheet: String, Identifiable {
    case profiles
    case configuration

    var id: String { rawValue }
}

public struct ClashMacRootView: View {
    private let snapshot: AppleClientSnapshot
    private let actions: AppleClientActions
    private let secondaryContent: @MainActor (ClashMacSecondaryDestination) -> AnyView
     
     
     
    private let detailOverlay:
        @MainActor (ClashClientUI.ClashRootDestination?) -> AnyView
    private let moreAttentionAction: @MainActor (String) -> Void

    @State private var navigationState:
        ClashClientUI.AppleClientNavigationState
    @State private var configurationDestination:
        ClashMacSecondaryDestination = .configuration
    @State private var isPickingProfile = false
    @Binding private var navigationRequest:
        ClashMacSecondaryDestination?
    @Environment(\.locale) private var locale
    @StateObject private var cantoShortcuts = CantoShortcutStore()
    @State private var cantoModePicker = false
    @State private var cantoShortcutEditor = false
    @State private var cantoProfilePicker = false
    @State private var cantoSelectedGroup: ClashProxyGroupSnapshot?
    @State private var cantoSheet: CantoMacSheet?

    public init(
        snapshot: AppleClientSnapshot,
        selection: ClashMacDestination = .home,
        actions: AppleClientActions,
        navigationRequest:
            Binding<ClashMacSecondaryDestination?> = .constant(nil),
        secondaryContent: @escaping @MainActor (ClashMacSecondaryDestination) -> AnyView = {
            AnyView(ClashMacSecondaryUnavailableView(destination: $0))
        },
        detailOverlay: @escaping @MainActor (
            ClashClientUI.ClashRootDestination?
        ) -> AnyView = { _ in AnyView(EmptyView()) },
         
         
         
        moreAttentionAction: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.snapshot = snapshot
        self.actions = actions
        self.secondaryContent = secondaryContent
        self.detailOverlay = detailOverlay
        self.moreAttentionAction = moreAttentionAction
        _navigationRequest = navigationRequest
        _navigationState = State(
            initialValue: ClashClientUI.AppleClientNavigationState(
                selectedRoot: selection
            )
        )
    }

    public var body: some View {
         
         
         
        ClashClientUI.ClashRegularClientShell(
            navigationState: $navigationState,
            sidebarBehavior: .fixed,
            background: ClashMacPlatformPresentation.palette.canvas,
            sidebarBackground: ClashMacPlatformPresentation.palette.surface
        ) { destination in
            ClashSymbolImage(
                symbol: destination.symbol,
                resizesToFit: true
            )
        } rootContent: { destination in
            sharedProductPage(for: destination)
        } destinationContent: { destination in
            sharedDestinationContent(destination)
        } detailOverlay: { destination in
            detailOverlay(destination)
        }
        .frame(minWidth: 880, minHeight: 600)
         
         
         
        .background(ClashMacSidebarLock())
         
         
         
        .environment(
            \.clashFullWidthSegmentedPickerAdapter,
            ClashMacPlatformPresentation.fullWidthSegmentedPickerAdapter
        )
        .accessibilityIdentifier("clash.mac.root")
        .onAppear {
            ClashNavigationHooks.resignCurrentField =
                ClashMacPlatformPresentation.resignCurrentField
             
             
             
            ClashMacFrameCounter.install()
            consumeNavigationRequest()
        }
        .onChange(of: navigationRequest) { _ in
            consumeNavigationRequest()
        }
        .clashPageProbe("window-root")
    }

    @ViewBuilder
    private func sharedProductPage(
        for destination: ClashClientUI.ClashRootDestination
    ) -> some View {
        switch destination {
        case .home:
            cantoDashboard
        case .utilities:
            ClashClientUI.ClashUtilitiesView(
                snapshot: snapshot,
                destination: utilitiesDestinationBinding,
                presentationClass: .regularTouch,
                palette: productPalette,
                     
                 
                 
                 
                omitting: ClashUtilitiesCatalog.regularHubExcludes,
                icon: { symbol in
                    ClashSymbolImage(symbol: symbol)
                },
                destinationContent: { destination in
                    sharedDestinationContent(.utilities(destination))
                }
            )
        case .more:
            cantoMore
        case .profiles:
            cantoConfig
        case .proxies:
            cantoPolicy
        case .rules, .activity, .about:
            sharedDestinationContent(destination.productDestination)
        }
    }

    private var productPalette: ClashClientUI.ClashProductPalette {
        ClashMacPlatformPresentation.palette
    }

    // MARK: - Canto 四页（macOS 侧栏复用同一套 Canto 视图）

    private var cantoDashboard: some View {
        let home = snapshot.home
        let chip = ClashHomeProfileChipPresenter.presentation(
            selectedProfile: snapshot.selectedProfile,
            isSystemFallback: home.selectedProfileIsSystemFallback
        )
        let subtitle = ClashCopy.string(
            for: home.connection.subtitle,
            locale: locale
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let showsExtraAction: Bool = {
            switch home.connection.primaryAction {
            case .none, .disconnect:
                return false
            case .connect:
                return false
            case .cancel, .retry, .retryProxy, .openProfiles:
                return true
            }
        }()
        let unit = ClashThroughputUnit.stored(in: .standard)

        return CantoDashboardView(
            model: CantoDashboardModel(
                brandTitle: "CANTO",
                isConnected: home.connection.phase == .connected,
                connectionLabel: ClashCopy.string("Connection", locale: locale),
                modeTitle: modeTitle(home.routing.mode),
                connectionSubtitle: subtitle.isEmpty ? nil : subtitle,
                isConnectionToggleEnabled: !home.isProfileActionInFlight,
                connectionActionTitle: showsExtraAction
                    ? home.connection.primaryActionTitle.map {
                        ClashCopy.string($0, locale: locale)
                    }
                    : nil,
                connectionActionEnabled: home.connection.primaryActionEnabled,
                onConnectionAction: {
                    performCantoPrimaryAction(home.connection.primaryAction)
                },
                profileTitle: ClashCopy.string(for: chip.title, locale: locale),
                profileAccessory: chip.accessory == .add ? .add : .picker,
                onOpenProfiles: {
                    if chip.accessory == .add {
                        cantoSheet = .profiles
                    } else {
                        cantoProfilePicker = true
                    }
                },
                connectionNotice: home.connection.issue.map { issue in
                    CantoDashboardNotice(
                        message: ClashCopy.string(for: issue.text, locale: locale),
                        actionTitle: ClashCopy.string("View Details", locale: locale),
                        isDestructive: issue.kind.lineTapResetsVPNProfile,
                        action: {
                            Task { @MainActor in
                                try? await actions.perform(
                                    .home(.showConnectionIssue),
                                    allowedBy: snapshot
                                )
                            }
                        }
                    )
                },
                cantoBridge: nil,
                onOpenCanto: nil,
                uploadLabel: ClashCopy.string("Upload", locale: locale),
                uploadValue: ClashThroughputFormatter.rate(
                    home.traffic.uploadBytesPerSecond,
                    unit: unit
                ),
                uploadCaption: ClashThroughputFormatter.usage(
                    home.traffic.uploadTotalBytes
                ),
                downloadLabel: ClashCopy.string("Download", locale: locale),
                downloadValue: ClashThroughputFormatter.rate(
                    home.traffic.downloadBytesPerSecond,
                    unit: unit
                ),
                downloadCaption: ClashThroughputFormatter.usage(
                    home.traffic.downloadTotalBytes
                ),
                shortcutsTitle: ClashCopy.string("Shortcuts", locale: locale),
                shortcutsEditTitle: ClashCopy.string("Edit", locale: locale),
                shortcuts: cantoShortcuts.shortcuts,
                onToggleConnection: {
                    let intent: AppleClientConnectionIntent =
                        home.connection.phase == .connected ? .disconnect : .connect
                    Task { @MainActor in
                        try? await actions.perform(
                            .connection(intent),
                            allowedBy: snapshot
                        )
                    }
                },
                onSelectMode: { cantoModePicker = true },
                onEditShortcuts: { cantoShortcutEditor = true },
                onShortcut: openCantoShortcut
            )
        )
        .confirmationDialog(
            Text(verbatim: ClashCopy.string("Outbound Mode", locale: locale)),
            isPresented: $cantoModePicker,
            titleVisibility: .visible
        ) {
            ForEach(
                [AppleClientOutboundMode.rule, .global, .direct],
                id: \.rawValue
            ) { mode in
                Button {
                    Task { @MainActor in
                        try? await actions.perform(
                            .setOutboundMode(mode),
                            allowedBy: snapshot
                        )
                    }
                } label: {
                    Text(verbatim: modeTitle(mode))
                }
            }
            Button(role: .cancel) {} label: {
                Text(verbatim: ClashCopy.string("Cancel", locale: locale))
            }
        }
        .sheet(isPresented: $cantoProfilePicker) {
            ClashMacProfilePicker(
                profiles: snapshot.profiles.profiles,
                select: { id in
                    cantoProfilePicker = false
                    Task { @MainActor in
                        try? await actions.perform(
                            .selectProfile(id: id),
                            allowedBy: snapshot
                        )
                    }
                }
            )
            .padding()
            .frame(minWidth: 260)
        }
        .sheet(isPresented: $cantoShortcutEditor) {
            CantoShortcutEditorView(store: cantoShortcuts) {
                cantoShortcutEditor = false
            }
        }
        .sheet(item: $cantoSheet) { sheet in
            cantoSheetContent(sheet)
        }
    }

    private var cantoPolicy: some View {
        CantoPolicyView(
            title: "Policy",
            items: cantoPolicyItems,
            onSelect: { name in
                cantoSelectedGroup = snapshot.proxies.groups.first { $0.name == name }
            }
        )
        .sheet(item: $cantoSelectedGroup) { group in
            cantoPolicyPicker(group)
        }
    }

    private var cantoConfig: some View {
        CantoConfigView(
            model: CantoConfigModel(
                nodeCount: snapshot.home.proxyCount,
                ruleCount: snapshot.home.ruleCount,
                profileName: snapshot.selectedProfile?.label ?? "",
                profileCount: snapshot.profiles.profiles.count
            ),
            onSelect: handleCantoConfig
        )
        .sheet(item: $cantoSheet) { sheet in
            cantoSheetContent(sheet)
        }
    }

    private var cantoMore: some View {
        CantoMoreView(onSelect: handleCantoMore)
            .sheet(item: $cantoSheet) { sheet in
                cantoSheetContent(sheet)
            }
    }

    private var cantoPolicyItems: [CantoPolicyItem] {
        snapshot.proxies.groups.enumerated().map { index, group in
            let selection = group.runtimeSelection
                ?? group.configuredSelection
                ?? group.resolvedRuntimeRoute
                ?? ""
            let latency: String? = {
                guard let state = snapshot.proxies.latencyByName[selection],
                      case .measured(let milliseconds) = state else { return nil }
                return "\(milliseconds) ms"
            }()
            return CantoPolicyItem(
                id: group.name,
                title: group.name,
                subtitle: selection.isEmpty ? "DIRECT" : selection,
                systemImage: cantoPolicySymbol(for: group.type),
                tint: cantoPolicyTint(index),
                isSelected: group.configuredSelection != nil,
                latency: latency
            )
        }
    }

    private func cantoPolicySymbol(for type: String) -> String {
        switch type.lowercased() {
        case "select", "selector": "square.stack.3d.up.fill"
        case "url-test", "urltest": "bolt.horizontal.fill"
        case "fallback": "arrow.triangle.2.circlepath"
        case "load-balance", "loadbalance": "scale.3d"
        default: "square.stack.3d.up.fill"
        }
    }

    private func cantoPolicyTint(_ index: Int) -> Color {
        switch index % 4 {
        case 0: CantoTheme.Palette.accent
        case 1: CantoTheme.Palette.success
        case 2: CantoTheme.Palette.warning
        default: CantoTheme.Palette.secondaryInk
        }
    }

    private func cantoPolicyPicker(_ group: ClashProxyGroupSnapshot) -> some View {
        NavigationStack {
            List(group.members) { member in
                Button {
                    cantoSelectedGroup = nil
                    Task { @MainActor in
                        try? await actions.perform(
                            .proxies(.select(group: group.name, member: member.name)),
                            allowedBy: snapshot
                        )
                    }
                } label: {
                    HStack(spacing: CantoTheme.Spacing.row) {
                        Text(verbatim: member.name)
                            .font(CantoTheme.Typography.rowTitle)
                            .foregroundStyle(CantoTheme.Palette.ink)
                        Spacer(minLength: CantoTheme.Spacing.compact)
                        if group.runtimeSelection == member.name {
                            Image(systemName: "checkmark")
                                .foregroundStyle(CantoTheme.Palette.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .navigationTitle(Text(verbatim: group.name))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        cantoSelectedGroup = nil
                    } label: {
                        Text(verbatim: ClashCopy.string("Cancel", locale: locale))
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private func cantoSheetContent(_ sheet: CantoMacSheet) -> some View {
        NavigationStack {
            Group {
                switch sheet {
                case .profiles:
                    secondaryContent(.profiles)
                case .configuration:
                    secondaryContent(.configuration)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(role: .cancel) {
                        cantoSheet = nil
                    } label: {
                        Text(verbatim: ClashCopy.string("Cancel", locale: locale))
                    }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 560)
    }

    private func modeTitle(_ mode: AppleClientOutboundMode) -> String {
        ClashCopy.string(mode.rawValue.capitalized, locale: locale)
    }

    private func performCantoPrimaryAction(_ action: ClashHomePrimaryAction) {
        switch action {
        case .openProfiles:
            if snapshot.selectedProfile == nil
                || snapshot.home.selectedProfileIsSystemFallback {
                cantoSheet = .profiles
            } else {
                cantoProfilePicker = true
            }
        case .connect, .retry, .retryProxy:
            Task { @MainActor in
                try? await actions.perform(.connection(.connect), allowedBy: snapshot)
            }
        case .cancel, .disconnect:
            Task { @MainActor in
                try? await actions.perform(.connection(.disconnect), allowedBy: snapshot)
            }
        case .none:
            break
        }
    }

    private func openCantoShortcut(_ shortcut: CantoShortcut) {
        switch shortcut {
        case .nodes:
            navigationState.navigate(to: .proxies)
        case .requests:
            navigationState.navigate(to: .utilities(.requests))
        case .dnsRecords:
            navigationState.navigate(to: .dnsQuery)
        case .profiles, .modules, .scripts, .cantoAgent:
            cantoSheet = .profiles
        case .lanShare:
            navigationState.navigate(to: .utilities(.proxyShare))
        case .rules:
            navigationState.navigate(to: .rules)
        case .diagnostics:
            navigationState.navigate(to: .utilities(.diagnosticsInbox))
        }
    }

    private func handleCantoConfig(_ destination: CantoConfigDestination) {
        switch destination {
        case .nodes:
            navigationState.navigate(to: .proxies)
        case .rules:
            navigationState.navigate(to: .rules)
        case .modules, .rewrite, .scripts, .mitm, .files, .profiles, .appleTV:
            cantoSheet = .profiles
        case .dns, .advanced:
            configurationDestination = .configuration
            cantoSheet = .configuration
        case .externalController:
            navigationState.navigate(to: .more(.clientSettings))
        }
    }

    private func handleCantoMore(_ destination: CantoMoreDestination) {
        switch destination {
        case .vpn:
            navigationState.navigate(to: .more(.tunnel))
        case .onDemand:
            navigationState.navigate(to: .more(.onDemand))
        case .clientSettings, .externalController:
            navigationState.navigate(to: .more(.clientSettings))
        case .appearance:
            navigationState.navigate(to: .more(.appearance))
        case .storage:
            navigationState.navigate(to: .more(.storage))
        case .backup:
            cantoSheet = .profiles
        case .geo:
            navigationState.navigate(to: .more(.geoResources))
        case .networkQuality:
            navigationState.navigate(to: .utilities(.networkQuality))
        case .stun:
            navigationState.navigate(to: .utilities(.stun))
        case .dnsQuery:
            navigationState.navigate(to: .dnsQuery)
        case .lanShare:
            navigationState.navigate(to: .utilities(.proxyShare))
        case .runtime:
            navigationState.navigate(to: .utilities(.runtime))
        case .diagnostics:
            navigationState.navigate(to: .utilities(.diagnosticsInbox))
        case .logs:
            navigationState.navigate(to: .utilities(.logs))
        case .about:
            navigationState.navigate(to: .more(.about))
        }
    }

    private var navigationAwareActions: AppleClientActions {
        let components = actions.providedCapabilities.map { capability in
            AppleClientActions(capability: capability) { action in
                navigate(for: action)
                try await actions.perform(action, allowedBy: snapshot)
            }
        }
        return (try? AppleClientActions.composing(components))
            ?? .unavailable
    }

    private var utilitiesDestinationBinding:
        Binding<ClashUtilitiesDestination>
    {
        Binding(
            get: {
                guard navigationState.selectedRoot == .utilities,
                      case .utilities(let destination) =
                        navigationState.destination
                else {
                    return .root
                }
                return destination
            },
            set: { destination in
                openUtility(destination)
            }
        )
    }

    private var moreDestinationBinding:
        Binding<ClashMoreDestination>
    {
        Binding(
            get: {
                guard navigationState.selectedRoot == .more,
                      case .more(let destination) =
                        navigationState.destination
                else {
                    return .root
                }
                return destination
            },
            set: { destination in
                openMore(destination)
            }
        )
    }

    private func sharedDestinationContent(
        _ destination: ClashClientUI.AppleClientDestination
    ) -> AnyView {
        if destination == .configuration {
            return secondaryContent(configurationDestination)
        }
        if let macDestination = ClashMacSecondaryDestination(
            sharedDestination: destination
        ) {
            return secondaryContent(macDestination)
        } else {
            return AnyView(sharedProductPage(for: destination.root))
        }
    }

    private func consumeNavigationRequest() {
        guard let requested = navigationRequest else { return }
        if requested.isConfigurationDestination {
            configurationDestination = requested
        }
        navigationState.navigate(to: requested.sharedDestination)
        navigationRequest = nil
    }

    private func navigate(for action: AppleClientAction) {
        let destination: ClashClientUI.AppleClientDestination?
        switch action {
        case .home(let command):
            if let requested =
                ClashMacSecondaryDestination(homeCommand: command)
            {
                configurationDestination = requested
                destination = .configuration
            } else {
                switch command {
                case .openProfiles:
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                     
                    if chipIsTheAddDoor {
                        isPickingProfile = false
                         
                         
                         
                         
                         
                         
                        destination = .profiles
                    } else {
                        isPickingProfile = true
                        destination = nil
                    }
                case .openProxies:
                    destination = .proxies
                case .openRules:
                    destination = .rules
                case .performPrimaryAction, .showConnectionIssue,
                     .resetVPNProfile, .setCards, .setTrafficScope,
                     .refreshExternalIP, .refreshLANIP:
                    destination = nil
                case .openRuntimeConfiguration:
                    destination = nil
                }
            }
        case .rules(.openActiveRules):
            destination = .activeRules
        case .rules(.openProxiesGroup):
            destination = .proxies
        case .dns(.openDNSQuery):
            destination = .dnsQuery
        default:
            destination = nil
        }
        if let destination {
            navigationState.navigate(to: destination)
        }
    }

    private func openUtility(_ destination: ClashUtilityDestination) {
        if destination == .root {
            navigationState.selectRoot(.utilities)
            return
        }
        navigationState.navigate(to: .utilities(destination))
        Task { @MainActor in
            try? await actions.perform(
                .openUtility(destination),
                allowedBy: snapshot
            )
        }
    }

    private func openMore(_ destination: ClashMoreDestination) {
        if destination == .root {
            navigationState.selectRoot(.more)
            return
        }
        navigationState.navigate(to: .more(destination))
        Task { @MainActor in
            try? await actions.perform(
                .openMore(destination),
                allowedBy: snapshot
            )
        }
    }
}

private extension ClashMacSecondaryDestination {
    var isConfigurationDestination: Bool {
        switch self {
        case .runtimeConfiguration, .configuration:
            true
        case .profiles, .proxies, .rules, .activeRules, .dnsQuery,
             .utility, .more:
            false
        }
    }

    var sharedDestination: ClashClientUI.AppleClientDestination {
        switch self {
        case .profiles:
            .profiles
        case .proxies:
            .proxies
        case .rules:
            .rules
        case .activeRules:
            .activeRules
        case .dnsQuery:
            .dnsQuery
        case .runtimeConfiguration, .configuration:
            .configuration
        case .utility(let destination):
            .utilities(destination)
        case .more(let destination):
            .more(destination)
        }
    }

    init?(
        sharedDestination destination: ClashClientUI.AppleClientDestination
    ) {
        switch destination {
        case .profiles, .profileImport, .profileDetail, .modules:
            self = .profiles
        case .proxies:
            self = .proxies
        case .rules:
            self = .rules
        case .activeRules:
            self = .activeRules
        case .dnsQuery:
            self = .dnsQuery
        case .configuration:
            self = .configuration
        case .utilities(let destination) where destination != .root:
            self = .utility(destination)
        case .more(let destination) where destination != .root:
            self = .more(destination)
        case .home, .utilities, .more:
            return nil
        }
    }
}

extension ClashMacRootView {
}

extension ClashMacRootView {
     
     
     
     
     
     
     
     
     
     
     
    fileprivate var chipIsTheAddDoor: Bool {
        snapshot.home.selectedProfileIsSystemFallback
            || snapshot.profiles.profiles.isEmpty
    }

     
     
     
     
    fileprivate func profilePickerPresentation(
        for symbol: ClashSymbol
    ) -> Binding<Bool> {
        guard symbol == .chevronDown, !chipIsTheAddDoor else {
            return .constant(false)
        }
        return $isPickingProfile
    }
}
