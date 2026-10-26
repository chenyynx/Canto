import SwiftUI

/// 「更多」页的一级入口。
///
/// rawValue 会进入无障碍标识（`canto.more.<rawValue>`），改名会破坏自动化测试与宿主路由映射。
public enum CantoMoreDestination: String, CaseIterable, Identifiable, Sendable {
    case vpn
    case onDemand
    case clientSettings
    case externalController
    case appearance
    case storage
    case backup
    case geo
    case networkQuality
    case stun
    case dnsQuery
    case lanShare
    case runtime
    case diagnostics
    case logs
    case about

    public var id: String { rawValue }
}

/// 更多设置页：连接 / 外观与数据 / 工具 / 关于 四组入口。
///
/// 只负责布局与回调，不读取也不修改任何设置值；跳转由宿主在 `onSelect` 中处理，
/// 这样同一份视图可以直接放进 iPhone、iPad 与 macOS 的外壳。
public struct CantoMoreView: View {
    @Environment(\.locale) private var locale

    private let onSelect: (CantoMoreDestination) -> Void

    public init(onSelect: @escaping (CantoMoreDestination) -> Void) {
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // 标题与四个分组同处一个 LazyVStack：分组数量固定且很少，懒加载收益有限，
            // 但保留该容器，后续追加低频入口时无需再改结构。
            LazyVStack(alignment: .leading, spacing: 14) {
                title
                ForEach(Self.sections) { section in
                    sectionView(section)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, CantoTheme.Spacing.compact)
            .padding(.bottom, CantoTheme.Spacing.section)
        }
        .background(CantoTheme.Palette.canvas.ignoresSafeArea())
    }

    // MARK: - 标题

    private var title: some View {
        Text(clash: .copy("More"))
            .font(.largeTitle.weight(.black))
            .foregroundStyle(CantoTheme.Palette.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
            .accessibilityIdentifier("canto.more.title")
    }

    // MARK: - 分组

    private func sectionView(_ section: CantoMoreSection) -> some View {
        VStack(alignment: .leading, spacing: CantoTheme.Spacing.row) {
            // 「外观与数据」没有现成的整句键，用既有的「外观」「数据」两段拼出，
            // 三种语言都能直接得到本地化结果，不新造待翻译文案。
            CantoSectionHeader(
                title: section.titleKeys
                    .map { copy($0) }
                    .joined(separator: " · ")
            )
            CantoGroup {
                ForEach(section.destinations, id: \.self) { destination in
                    row(
                        destination,
                        showsDivider: destination != section.destinations.last
                    )
                }
            }
        }
    }

    private func row(
        _ destination: CantoMoreDestination,
        showsDivider: Bool
    ) -> some View {
        Button {
            onSelect(destination)
        } label: {
            CantoGroupRow(
                title: title(for: destination),
                subtitle: subtitle(for: destination),
                systemImage: destination.systemImage,
                iconTint: destination.iconTint,
                showsDivider: showsDivider
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("canto.more.\(destination.rawValue)")
    }

    // MARK: - 文案

    private func copy(_ key: String) -> String {
        ClashCopy.string(key, locale: locale)
    }

    private func title(for destination: CantoMoreDestination) -> String {
        // 品牌名不翻译：只把 “About” 交给本地化，中文得到「关于 Canto」、繁中「關於 Canto」。
        if destination == .about {
            return copy("About") + " Canto"
        }
        return copy(destination.titleKey)
    }

    private func subtitle(for destination: CantoMoreDestination) -> String? {
        guard let key = destination.subtitleKey else { return nil }
        return copy(key)
    }

    // MARK: - 分组数据

    private static let sections: [CantoMoreSection] = [
        CantoMoreSection(
            id: "connection",
            titleKeys: ["Connection"],
            destinations: [.vpn, .onDemand, .clientSettings, .externalController]
        ),
        CantoMoreSection(
            id: "appearanceData",
            titleKeys: ["Appearance", "Data"],
            destinations: [.appearance, .storage, .backup, .geo]
        ),
        CantoMoreSection(
            id: "tools",
            titleKeys: ["Tools"],
            destinations: [
                .networkQuality, .stun, .dnsQuery, .lanShare,
                .runtime, .diagnostics, .logs
            ]
        ),
        CantoMoreSection(
            id: "about",
            titleKeys: ["About"],
            destinations: [.about]
        ),
    ]
}

private struct CantoMoreSection: Identifiable {
    let id: String
    let titleKeys: [String]
    let destinations: [CantoMoreDestination]
}

private extension CantoMoreDestination {
    var titleKey: String {
        switch self {
        case .vpn: "VPN"
        case .onDemand: "On Demand"
        case .clientSettings: "Client Settings"
        case .externalController: "External Controller"
        case .appearance: "Appearance"
        case .storage: "Storage"
        case .backup: "Backup & Restore"
        case .geo: "Geo Resources"
        case .networkQuality: "Network Quality"
        case .stun: "STUN & NAT"
        case .dnsQuery: "DNS Query"
        case .lanShare: "LAN Share"
        // 沿用既有键，中文可直接得到「运行时诊断」，无需新增文案。
        case .runtime: "Runtime diagnostics"
        case .diagnostics: "Diagnostics Inbox"
        case .logs: "Logs"
        case .about: "About"
        }
    }

    // 副标题全部复用已存在的本地化键，避免在 UI 改造里新造待翻译文案。
    var subtitleKey: String? {
        switch self {
        case .vpn: "Tunnel & Routes"
        case .onDemand: "Automatic"
        case .clientSettings: "This Device"
        case .externalController: "Controller"
        case .appearance: "Theme"
        case .storage: "Data"
        case .backup: "iCloud Backup & Restore"
        case .geo: "Geo Data"
        case .networkQuality: "Latency"
        case .stun: "NAT type detection"
        case .dnsQuery: "Look up a name and clear the DNS cache"
        case .lanShare: "LAN HTTP and SOCKS proxy"
        case .runtime: "Runtime diagnostics"
        case .diagnostics: "Diagnostic Report"
        case .logs: "Core Log"
        case .about: "Version"
        }
    }

    // 只用 iOS 15 及更早版本就存在的 SF Symbol，避免低版本出现空图标。
    var systemImage: String {
        switch self {
        case .vpn: "lock.shield"
        case .onDemand: "clock.arrow.circlepath"
        case .clientSettings: "gearshape"
        case .externalController: "terminal"
        case .appearance: "paintbrush"
        case .storage: "internaldrive"
        case .backup: "arrow.triangle.2.circlepath"
        case .geo: "globe.asia.australia"
        case .networkQuality: "speedometer"
        case .stun: "network"
        case .dnsQuery: "magnifyingglass"
        case .lanShare: "antenna.radiowaves.left.and.right"
        case .runtime: "waveform.path.ecg"
        case .diagnostics: "tray.full"
        case .logs: "doc.plaintext"
        case .about: "info.circle"
        }
    }

    // 图标仅在既有 token 里选色，保持低饱和；图标井的 12% 底色由 CantoGroupRow 负责。
    var iconTint: Color {
        switch self {
        case .vpn, .clientSettings, .externalController, .appearance,
             .backup, .networkQuality, .dnsQuery:
            return CantoTheme.Palette.accent
        case .onDemand, .geo, .lanShare, .stun:
            return CantoTheme.Palette.success
        case .storage, .runtime, .diagnostics:
            return CantoTheme.Palette.warning
        case .logs, .about:
            return CantoTheme.Palette.secondaryInk
        }
    }
}
