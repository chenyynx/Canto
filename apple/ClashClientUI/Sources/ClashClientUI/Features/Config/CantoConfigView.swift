import SwiftUI

/// 配置页的顶层入口。
public enum CantoConfigDestination: String, CaseIterable, Identifiable, Sendable {
    case nodes
    case rules
    case modules
    case rewrite
    case scripts
    case mitm
    case dns
    case files
    case profiles
    case advanced
    case appleTV
    case externalController

    public var id: String { rawValue }
}

/// 配置页的展示数据。
///
/// 只放各入口需要显示的数量与当前配置名；视图不推断业务状态，
/// 具体页面与数据仍由宿主通过 `onSelect` 接线。
public struct CantoConfigModel {
    public var nodeCount: Int?
    public var ruleCount: Int?
    public var moduleCount: Int?
    public var rewriteCount: Int?
    public var scriptCount: Int?
    public var mitmCount: Int?
    public var profileName: String
    public var profileCount: Int?

    public init(
        nodeCount: Int? = nil,
        ruleCount: Int? = nil,
        moduleCount: Int? = nil,
        rewriteCount: Int? = nil,
        scriptCount: Int? = nil,
        mitmCount: Int? = nil,
        profileName: String = "",
        profileCount: Int? = nil
    ) {
        self.nodeCount = nodeCount
        self.ruleCount = ruleCount
        self.moduleCount = moduleCount
        self.rewriteCount = rewriteCount
        self.scriptCount = scriptCount
        self.mitmCount = mitmCount
        self.profileName = profileName
        self.profileCount = profileCount
    }
}

/// Loon 式配置长列表：分节标题加白色分组行，整页纵向滚动。
///
/// 只负责布局、文案与无障碍；选中哪一行以 `CantoConfigDestination`
/// 回调宿主，视图本身不持有导航状态。
public struct CantoConfigView: View {
    private let model: CantoConfigModel
    private let onSelect: (CantoConfigDestination) -> Void
    @Environment(\.locale) private var locale

    public init(
        model: CantoConfigModel,
        onSelect: @escaping (CantoConfigDestination) -> Void
    ) {
        self.model = model
        self.onSelect = onSelect
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(alignment: .leading, spacing: 14) {
                header
                nodesSection
                rulesSection
                modulesSection
                rewriteSection
                scriptsSection
                mitmSection
                dnsSection
                filesSection
                otherSection
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .background(CantoTheme.Palette.canvas.ignoresSafeArea())
    }

    // MARK: - 顶部

    private var header: some View {
        HStack(alignment: .center, spacing: CantoTheme.Spacing.compact) {
            Text(clash: .copy("Config"))
                .font(.largeTitle.weight(.black))
                .foregroundStyle(CantoTheme.Palette.ink)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: CantoTheme.Spacing.compact)

            // 给定 API 只有行选中回调，没有“更多”动作：保留概念图里的圆形
            // 外观，但不做成可点但无响应的假按钮。
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(CantoTheme.Palette.ink)
                .frame(width: 44, height: 44)
                .background(Circle().fill(CantoTheme.Palette.card))
                .accessibilityHidden(true)
        }
    }

    // MARK: - 分节

    private var nodesSection: some View {
        section("Nodes") {
            row(
                .nodes,
                "All Nodes",
                subtitle: counted("%@ nodes", model.nodeCount),
                systemImage: "server.rack",
                tint: CantoTheme.Palette.accent,
                showsDivider: true
            )
            row(
                .nodes,
                "Filter Nodes",
                subtitle: copy("Filter by region, protocol, or latency"),
                systemImage: "line.3.horizontal.decrease.circle",
                tint: CantoTheme.Palette.accent,
                showsDivider: true
            )
            row(
                .nodes,
                "Proxy Chain",
                subtitle: copy("Chain proxies in order"),
                systemImage: "link",
                tint: CantoTheme.Palette.accent,
                showsDivider: false
            )
        }
    }

    private var rulesSection: some View {
        section("Rules") {
            row(
                .rules,
                "Rules",
                subtitle: counted("%@ rules", model.ruleCount),
                systemImage: "list.bullet.rectangle",
                tint: CantoTheme.Palette.accent,
                showsDivider: false
            )
        }
    }

    private var modulesSection: some View {
        section("Modules") {
            row(
                .modules,
                "Modules",
                subtitle: counted("%@ modules", model.moduleCount),
                systemImage: "shippingbox",
                tint: CantoTheme.Palette.accent,
                showsDivider: false
            )
        }
    }

    private var rewriteSection: some View {
        section("Rewrite") {
            row(
                .rewrite,
                "Rewrite",
                subtitle: "\(counted("%@ rewrites", model.rewriteCount)) · \(copy("From modules and profiles"))",
                systemImage: "arrow.triangle.2.circlepath",
                tint: CantoTheme.Palette.warning,
                showsDivider: false
            )
        }
    }

    private var scriptsSection: some View {
        section("Scripts") {
            row(
                .scripts,
                "Scripts",
                subtitle: "\(counted("%@ scripts", model.scriptCount)) · \(copy("From modules and profiles"))",
                systemImage: "curlybraces",
                tint: CantoTheme.Palette.warning,
                showsDivider: false
            )
        }
    }

    private var mitmSection: some View {
        section("MitM") {
            row(
                .mitm,
                "Decrypted Domains",
                subtitle: counted("%@ domains", model.mitmCount),
                systemImage: "lock.open",
                tint: CantoTheme.Palette.success,
                showsDivider: true
            )
            row(
                .mitm,
                "MitM Configuration",
                subtitle: copy("Certificates and hostnames"),
                systemImage: "checkmark.shield",
                tint: CantoTheme.Palette.success,
                showsDivider: false
            )
        }
    }

    private var dnsSection: some View {
        section("DNS") {
            row(
                .dns,
                "DNS Servers",
                subtitle: copy("Resolvers and policies"),
                systemImage: "network",
                tint: CantoTheme.Palette.accent,
                showsDivider: true
            )
            row(
                .dns,
                "Domain, IP & Stack Mapping",
                subtitle: copy("Local mappings and IP stack"),
                systemImage: "arrow.left.arrow.right",
                tint: CantoTheme.Palette.accent,
                showsDivider: false
            )
        }
    }

    private var filesSection: some View {
        section("Files") {
            row(
                .files,
                "Quick Edit",
                subtitle: copy("Edit the active profile"),
                systemImage: "square.and.pencil",
                tint: CantoTheme.Palette.warning,
                showsDivider: true
            )
            row(
                .profiles,
                "All Profiles",
                subtitle: profilesSubtitle,
                systemImage: "doc.on.doc",
                tint: CantoTheme.Palette.accent,
                showsDivider: true
            )
            row(
                .files,
                "Sample Templates",
                subtitle: copy("Start from an example configuration"),
                systemImage: "doc.text",
                tint: CantoTheme.Palette.secondaryInk,
                showsDivider: true
            )
            row(
                .files,
                "External Resources",
                subtitle: copy("Icons, rule sets, and scripts"),
                systemImage: "link",
                tint: CantoTheme.Palette.secondaryInk,
                showsDivider: false
            )
        }
    }

    private var otherSection: some View {
        section("Other") {
            row(
                .advanced,
                "Advanced Config",
                subtitle: copy("Overrides, certificates, and runtime"),
                systemImage: "slider.horizontal.3",
                tint: CantoTheme.Palette.warning,
                showsDivider: true
            )
            row(
                .appleTV,
                "Apple TV",
                subtitle: copy("Pair and manage Apple TV"),
                systemImage: "appletv",
                tint: CantoTheme.Palette.accent,
                showsDivider: true
            )
            row(
                .externalController,
                "External Controller",
                subtitle: copy("Web dashboard and API"),
                systemImage: "antenna.radiowaves.left.and.right",
                tint: CantoTheme.Palette.secondaryInk,
                showsDivider: false
            )
        }
    }

    // MARK: - 构建块

    private func section<Rows: View>(
        _ titleKey: String,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: CantoTheme.Spacing.row) {
            Text(clash: .copy(titleKey))
                .font(.title2.bold())
                .foregroundStyle(CantoTheme.Palette.ink)
                .accessibilityAddTraits(.isHeader)

            CantoGroup {
                rows()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func row(
        _ destination: CantoConfigDestination,
        _ titleKey: String,
        subtitle: String? = nil,
        systemImage: String,
        tint: Color,
        showsDivider: Bool = true
    ) -> some View {
        Button {
            onSelect(destination)
        } label: {
            CantoGroupRow(
                title: ClashCopy.string(titleKey, locale: locale),
                subtitle: subtitle,
                systemImage: systemImage,
                iconTint: tint,
                showsDivider: showsDivider
            )
            // 行背景由 CantoGroup 提供，透明区域默认不参与命中；
            // 显式矩形让整行都能点。
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var profilesSubtitle: String? {
        let count = counted("%@ profiles", model.profileCount)
        if model.profileName.isEmpty { return count }
        guard let count else { return model.profileName }
        return "\(count) · \(model.profileName)"
    }

    private func copy(_ key: String) -> String {
        ClashCopy.string(key, locale: locale)
    }

    private func counted(_ format: String, _ count: Int?) -> String? {
        guard let count else { return nil }
        return ClashCopy.format(
            format,
            locale: locale,
            ClashCopy.count(count, locale: locale)
        )
    }
}
