import Combine
import Foundation
import SwiftUI

// Canto 功能页共用展示层：不持有状态、不做网络、不实现任何协议。
//
// 依赖边界（重要）：
//   - 本目录的文件与 CantoBridge.swift（CantoSessionPhase / CantoActivityEntry /
//     CantoBridgeObservable / CantoPairingServiceProtocol ...）必须编译在同一个模块里，
//     否则 CantoBridge 的类型不可见。这些类型一律不加模块前缀引用。
//   - ClashClientUI 的类型一律显式前缀，原因是本目录可能被编译进 App 目标，
//     宿主另有同名类型（ClashTheme / ClashCardSurface / ClashIconWell / ClashEmptyState ...）。

// MARK: - 入口与展示模型

/// Canto 卡可跳转的两个二级页。宿主可据此接管跳转（见 CantoHomeCard.onOpen）。
public enum CantoCardPage: Hashable, Sendable {
    case pairing
    case settings
}

/// 已配对 agent 的展示信息（首页卡 + 设置页共用）。
///
/// 数据来源由宿主汇总：CantoBridgeObservable.agentID /
/// CantoPairingServiceProtocol.agentFingerprint / CantoIdentityStoring.agentEndpoint。
/// UI 不直接读身份库与配对服务内部状态。
public struct CantoAgentProfile: Equatable, Sendable {
    public var agentID: String?
    public var agentName: String?
    public var fingerprint: String?
    public var endpoint: String?

    public init(
        agentID: String? = nil,
        agentName: String? = nil,
        fingerprint: String? = nil,
        endpoint: String? = nil
    ) {
        self.agentID = agentID
        self.agentName = agentName
        self.fingerprint = fingerprint
        self.endpoint = endpoint
    }

    /// 空档位统一占位，避免各页各写一份。
    public static let placeholder = "—"

    /// 卡片副行的称呼：优先 agent 名，其次 id 尾 4 位，最后兜底「Agent」。
    public var shortName: String {
        if let agentName, !agentName.isEmpty { return agentName }
        if let agentID, !agentID.isEmpty { return "Agent " + String(agentID.suffix(4)) }
        return "Agent"
    }

    /// 本地化后的称呼；「Agent」是产品名词，三种语言保持原样。
    public func shortName(locale: Locale) -> String {
        if let agentName, !agentName.isEmpty { return agentName }
        if let agentID, !agentID.isEmpty {
            return ClashCopy.format(
                "Agent %@",
                locale: locale,
                String(agentID.suffix(4))
            )
        }
        return ClashCopy.string("Agent", locale: locale)
    }

    public var displayID: String { value(agentID) }
    public var displayName: String { value(agentName) }
    public var displayFingerprint: String { value(fingerprint) }
    public var displayEndpoint: String { value(endpoint) }

    /// 指纹尾 4 位（Bonjour 设备行 / SAS 确认的人眼比对片段）。
    public var fingerprintTail: String {
        guard let fingerprint, !fingerprint.isEmpty else { return Self.placeholder }
        return String(fingerprint.suffix(4))
    }

    private func value(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return Self.placeholder }
        return raw
    }
}

// MARK: - 会话阶段文案

/// CantoSessionPhase → 首页卡状态行/副行文案。
public enum CantoPhaseCopy {
    /// 状态行本地化键：复用 App 既有词条，仅 Suspended 为本功能新增。
    static func statusKey(_ phase: CantoSessionPhase) -> String {
        switch phase {
        case .idle: return "Not Connected"
        case .connecting: return "Connecting…"
        case .connected: return "Connected"
        case .suspended: return "Suspended"
        case .failed: return "Connection failed"
        }
    }

    /// 卡片大字状态行（未本地化的中文源串，保留给既有调用方）。
    public static func statusLine(_ phase: CantoSessionPhase) -> String {
        switch phase {
        case .idle: return "未连接"
        case .connecting: return "连接中…"
        case .connected: return "已连接"
        case .suspended: return "已挂起"
        case .failed: return "连接失败"
        }
    }

    /// 本地化后的状态行：首页卡与设置页共用。
    public static func statusLine(_ phase: CantoSessionPhase, locale: Locale) -> String {
        ClashCopy.string(statusKey(phase), locale: locale)
    }

    /// 卡片灰色副行；profile/activity 由宿主提供。
    public static func subtitleLine(
        _ phase: CantoSessionPhase,
        profile: CantoAgentProfile,
        activity: CantoActivityEntry?,
        locale: Locale,
        now: Date = Date()
    ) -> String {
        switch phase {
        case .idle:
            return ClashCopy.string(
                "节点、订阅、规则都由你的 Agent 管理维护",
                locale: locale
            )
        case .connecting:
            return ClashCopy.format(
                "正在与 %@ 建立加密会话",
                locale: locale,
                profile.shortName(locale: locale)
            )
        case .connected, .suspended:
            var pieces = [profile.shortName(locale: locale)]
            if let activity {
                pieces.append(
                    CantoActivityPresentation.relativeTime(
                        activity.at,
                        now: now,
                        locale: locale
                    )
                )
                pieces.append(
                    CantoActivityPresentation.title(for: activity.op, locale: locale)
                )
            } else {
                pieces.append(
                    ClashCopy.string("等待你的 Agent 指令", locale: locale)
                )
            }
            return pieces.joined(separator: " · ")
        case .failed(let reason):
            return reason
        }
    }

    /// 是否需要把状态行画成强调色（已连接 = 强调色，失败 = 语义红）。
    public static func isAccented(_ phase: CantoSessionPhase) -> Bool {
        if case .connected = phase { return true }
        return false
    }

    public static func isFailure(_ phase: CantoSessionPhase) -> Bool {
        if case .failed = phase { return true }
        return false
    }
}

// MARK: - 操作记录文案

/// CantoActivityEntry 的展示映射：op → 标题，status → 徽标。
public enum CantoActivityPresentation {
    /// 已知 op 的本地化键；Close Connection / DNS Query 复用 App 既有词条。
    static func titleKey(for op: String) -> String? {
        switch op {
        case "core.state.get", "app.state.get":
            return "Read Status"
        case "core.proxy.list", "app.proxy.list":
            return "Read Proxies"
        case "core.proxy.select", "app.proxy.select", "app.node.select":
            return "Switch Proxy"
        case "core.proxy.delay", "app.proxy.delay", "app.node.test":
            return "Test Proxy Latency"
        case "core.mode.set", "app.mode.set":
            return "Switch Outbound Mode"
        case "core.conn.list", "app.conn.list":
            return "Read Connections"
        case "core.conn.close", "app.conn.close":
            return "Close Connection"
        case "core.rules.list", "app.rules.list":
            return "Read Rules"
        case "core.rules.set", "app.rules.set":
            return "Modify Rules"
        case "core.provider.update", "app.subscription.update":
            return "Update Subscription"
        case "core.dns.query", "app.dns.query":
            return "DNS Query"
        case "core.probe", "app.probe":
            return "Connectivity Probe"
        case "core.log.tail", "app.log.tail":
            return "Read Logs"
        case "core.config.reload", "app.profile.reload":
            return "Reload Configuration"
        case "pairing.completed":
            return "Pairing Complete"
        case "pairing.failed":
            return "Pairing Failed"
        default:
            return nil
        }
    }

    /// 已知 op 的中文标题（未本地化源串，保留给既有调用方）；未知 op 原样显示。
    public static func title(for op: String) -> String {
        switch op {
        case "core.state.get", "app.state.get":
            return "读取状态"
        case "core.proxy.list", "app.proxy.list":
            return "读取节点"
        case "core.proxy.select", "app.proxy.select", "app.node.select":
            return "切换节点"
        case "core.proxy.delay", "app.proxy.delay", "app.node.test":
            return "节点测速"
        case "core.mode.set", "app.mode.set":
            return "切换出站模式"
        case "core.conn.list", "app.conn.list":
            return "读取连接"
        case "core.conn.close", "app.conn.close":
            return "关闭连接"
        case "core.rules.list", "app.rules.list":
            return "读取规则"
        case "core.rules.set", "app.rules.set":
            return "修改规则"
        case "core.provider.update", "app.subscription.update":
            return "更新订阅"
        case "core.dns.query", "app.dns.query":
            return "DNS 查询"
        case "core.probe", "app.probe":
            return "连通性探测"
        case "core.log.tail", "app.log.tail":
            return "读取日志"
        case "core.config.reload", "app.profile.reload":
            return "重载配置"
        case "pairing.completed":
            return "完成配对"
        case "pairing.failed":
            return "配对失败"
        default:
            return op
        }
    }

    /// 本地化后的 op 标题；未知 op 原样显示（便于排查）。
    public static func title(for op: String, locale: Locale) -> String {
        guard let key = titleKey(for: op) else { return op }
        return ClashCopy.string(key, locale: locale)
    }

    /// status：applied | deferred | rejected 的本地化键；未知 status 原样显示。
    static func statusKey(_ status: String) -> String? {
        switch status {
        case "applied": return "Applied"
        case "deferred": return "Deferred"
        case "rejected": return "Rejected"
        default: return nil
        }
    }

    /// status：applied | deferred | rejected（未本地化中文源串，保留给既有调用方）
    public static func statusLine(_ status: String) -> String {
        switch status {
        case "applied": return "已执行"
        case "deferred": return "已延后"
        case "rejected": return "已拒绝"
        default: return status
        }
    }

    /// 状态徽标色：语义色（成功/等待/失败），不跟 accent。
    public static func statusTint(_ status: String) -> Color {
        switch status {
        case "applied": return .green
        case "deferred": return .orange
        case "rejected": return .red
        default: return .secondary
        }
    }

    /// 「3 分钟前」——跟随系统语言与用户区域设置。
    public static func relativeTime(
        _ date: Date,
        now: Date = Date(),
        locale: Locale
    ) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = locale
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

// MARK: - 二级页骨架

/// 二级页统一骨架：iOS 触摸壳 = ScrollView + 卡片；macOS = 系统设置惯用 Form。
/// 结构对齐 ClashProductRootPage（该类型是包内 internal，无法跨模块复用）。
struct CantoPageScaffold<Content: View>: View {
    let palette: ClashClientUI.ClashProductPalette
    let accessibilityIdentifier: String
    private let content: Content

    @Environment(\.clashDetailCanvas) private var detailCanvas

    init(
        palette: ClashClientUI.ClashProductPalette,
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        Group {
            if ClashClientUI.ClashPlatformLayout.pageUsesSystemSettingsIdiom,
               #available(iOS 16.0, macOS 13.0, tvOS 16.0, *) {
                Form {
                    content
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
            } else {
                ScrollView {
                    VStack(
                        alignment: .leading,
                        spacing: ClashClientUI.ClashTheme.Spacing.section
                    ) {
                        content
                    }
                    .padding(.horizontal, ClashClientUI.ClashTheme.Layout.cardHorizontalInset)
                    .padding(.vertical, ClashClientUI.ClashTheme.Spacing.section)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .background(canvas.ignoresSafeArea())
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    /// 常规壳（iPad 侧栏 / macOS）自己画画布，本页只补底色。
    private var canvas: Color {
        detailCanvas ?? palette.canvas
    }
}

// MARK: - 符号与只读值行

/// 标准符号渲染：本目录只用内置 SF Symbol（不含 clash.* 自定义符号），
/// 故直接取 rawValue；宿主侧的候选回退与光学缩放不参与。
struct CantoSymbolImage: View {
    let symbol: ClashSymbol

    var body: some View {
        Image(systemName: symbol.rawValue)
            .accessibilityHidden(true)
    }
}

/// 只读「标题 + 值」行（设置页的 id / 指纹 / 端点）。
/// 与 ClashProductDestinationRow 同构：正文标题 + 等宽值 + 可选中文本。
struct CantoValueRow: View {
    let title: String
    let value: String
    let symbol: ClashSymbol
    var monospaced = true
    var selectable = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ClashClientUI.ClashTheme.Spacing.row) {
            Label {
                Text(ClashCopy.key(title))
                    .foregroundStyle(.primary)
            } icon: {
                CantoSymbolImage(symbol: symbol)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: ClashClientUI.ClashTheme.Spacing.row)
            Text(value)
                .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(CantoSelectableText(enabled: selectable))
        }
        .font(.subheadline)
        .frame(
            maxWidth: .infinity,
            minHeight: ClashClientUI.ClashTheme.Control.pointerRowTarget,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }
}

/// iOS 15 起支持 textSelection；tvOS 不提供，故按平台短路。
private struct CantoSelectableText: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
#if os(tvOS)
        content
#else
        if enabled {
            content.textSelection(.enabled)
        } else {
            content
        }
#endif
    }
}

// MARK: - 默认调色板（Release 构建同样可用）

/// 预览/默认调色板：全部取系统语义色，深浅色自适应。
/// ⚠️ 必须在 #if DEBUG 之外——CantoHomeCard 的默认参数引用它。
public extension ClashClientUI.ClashProductPalette {
    static var cantoPreview: Self {
#if os(macOS)
        Self(
            canvas: Color(nsColor: .windowBackgroundColor),
            surface: Color(nsColor: .controlBackgroundColor),
            raisedFill: Color(nsColor: .unemphasizedSelectedContentBackgroundColor),
            separator: Color(nsColor: .separatorColor)
        )
#elseif os(tvOS)
        Self(
            canvas: Color(uiColor: .black),
            surface: Color(uiColor: .darkGray),
            raisedFill: Color(uiColor: .darkGray),
            separator: Color(uiColor: .separator)
        )
#else
        Self(
            canvas: Color(uiColor: .systemGroupedBackground),
            surface: Color(uiColor: .secondarySystemGroupedBackground),
            raisedFill: Color(uiColor: .tertiarySystemFill),
            separator: Color(uiColor: .separator)
        )
#endif
    }
}

#if DEBUG


/// 预览用总门面 mock：不联网、不落盘。
@MainActor
final class CantoPreviewBridge: CantoBridgeObservable {
    @Published private(set) var phase: CantoSessionPhase
    @Published private(set) var isPaired: Bool
    @Published private(set) var agentID: String?
    @Published private(set) var recentActivity: [CantoActivityEntry]

    init(
        phase: CantoSessionPhase = .idle,
        isPaired: Bool = false,
        agentID: String? = nil,
        recentActivity: [CantoActivityEntry] = []
    ) {
        self.phase = phase
        self.isPaired = isPaired
        self.agentID = agentID
        self.recentActivity = recentActivity
    }

    func startPairing(withURI uri: String) async {
        phase = .connecting
        try? await Task.sleep(nanoseconds: 400_000_000)
        isPaired = true
        agentID = "4N7Q2W8Z0R5TVK9Y"
        phase = .connected
    }

    func forgetPairing() async {
        isPaired = false
        agentID = nil
        phase = .idle
    }

    // MARK: P3 桩（预览不需要真实回滚能力）
    var hasPendingConfigApply: Bool { false }
    func undoLastConfigApply() async throws {}

    /// 类型擦除的变更通知：预览里直接转发 objectWillChange。
    func observeChanges(_ action: @escaping () -> Void) -> AnyCancellable {
        objectWillChange.sink { _ in action() }
    }
}

/// 预览用配对服务 mock（同时演示 SAS 确认码来源）。
final class CantoPreviewPairingService: CantoPairingServiceProtocol, CantoSASCodeProviding,
    @unchecked Sendable {
    let agentFingerprint = "J5H2QT9M4N7Q2W8Z"
    let sasCode: String? = "418 296"

    private let agents: [CantoBonjourAgent]

    init(
        agents: [CantoBonjourAgent] = [
            CantoBonjourAgent(
                id: "4N7Q2W8Z0R5TVK9Y",
                name: "Mac Studio",
                endpoint: "wss://192.168.1.20:8787/canto"
            ),
            CantoBonjourAgent(
                id: "9Y8W7V6T5R4Q3P2N",
                name: "Arch 工作站",
                endpoint: "wss://192.168.1.31:8787/canto"
            ),
        ]
    ) {
        self.agents = agents
    }

    func discoverAgents() -> AsyncStream<[CantoBonjourAgent]> {
        let snapshot = agents
        return AsyncStream { continuation in
            continuation.yield(snapshot)
            continuation.finish()
        }
    }

    func pair(withURI uri: String) async throws -> PairingResult {
        PairingResult(
            accepted: true,
            controller: false,
            scopes: "observe|operate",
            agentName: "Mac Studio"
        )
    }

    func pair(
        bonjour agent: CantoBonjourAgent,
        sasConfirmed: @Sendable () async -> Bool
    ) async throws -> PairingResult {
        let confirmed = await sasConfirmed()
        return PairingResult(
            accepted: confirmed,
            controller: false,
            scopes: "observe|operate",
            agentName: agent.name
        )
    }
}

/// 预览用活动记录。
func cantoPreviewActivity(_ items: [(String, TimeInterval, String)]) -> [CantoActivityEntry] {
    items.enumerated().map { index, item in
        CantoActivityEntry(
            id: "01J8Z6Q2W8Z0R5TVK9Y\(index)",
            op: item.0,
            at: Date().addingTimeInterval(item.1),
            status: item.2
        )
    }
}

/// 预览用示例 profile。
let cantoPreviewProfile = CantoAgentProfile(
    agentID: "4N7Q2W8Z0R5TVK9Y",
    agentName: "Mac Studio",
    fingerprint: "J5H2QT9M4N7Q2W8Z",
    endpoint: "wss://192.168.1.20:8787/canto"
)

#endif
