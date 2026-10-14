import Combine
import Foundation
import SwiftUI

// Anchor 功能页共用展示层：不持有状态、不做网络、不实现任何协议。
//
// 依赖边界（重要）：
//   - 本目录的文件与 AnchorBridge.swift（AnchorSessionPhase / AnchorActivityEntry /
//     AnchorBridgeObservable / AnchorPairingServiceProtocol ...）必须编译在同一个模块里，
//     否则 AnchorBridge 的类型不可见。这些类型一律不加模块前缀引用。
//   - HakoClientUI 的类型一律显式前缀，原因是本目录可能被编译进 App 目标，
//     宿主另有同名类型（HakoTheme / HakoCardSurface / HakoIconWell / HakoEmptyState ...）。

// MARK: - 入口与展示模型

/// Anchor 卡可跳转的两个二级页。宿主可据此接管跳转（见 AnchorHomeCard.onOpen）。
public enum AnchorCardPage: Hashable, Sendable {
    case pairing
    case settings
}

/// 已配对 agent 的展示信息（首页卡 + 设置页共用）。
///
/// 数据来源由宿主汇总：AnchorBridgeObservable.agentID /
/// AnchorPairingServiceProtocol.agentFingerprint / AnchorIdentityStoring.agentEndpoint。
/// UI 不直接读身份库与配对服务内部状态。
public struct AnchorAgentProfile: Equatable, Sendable {
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

/// AnchorSessionPhase → 首页卡状态行/副行文案。
public enum AnchorPhaseCopy {
    /// 卡片大字状态行。
    public static func statusLine(_ phase: AnchorSessionPhase) -> String {
        switch phase {
        case .idle: return "未连接"
        case .connecting: return "连接中…"
        case .connected: return "已连接"
        case .suspended: return "已挂起"
        case .failed: return "连接失败"
        }
    }

    /// 卡片灰色副行；profile/activity 由宿主提供。
    public static func subtitleLine(
        _ phase: AnchorSessionPhase,
        profile: AnchorAgentProfile,
        activity: AnchorActivityEntry?,
        locale: Locale,
        now: Date = Date()
    ) -> String {
        switch phase {
        case .idle:
            return "节点、订阅、规则都由你的 Agent 管理维护"
        case .connecting:
            return "正在与 \(profile.shortName) 建立加密会话"
        case .connected, .suspended:
            var pieces = [profile.shortName]
            if let activity {
                pieces.append(
                    AnchorActivityPresentation.relativeTime(
                        activity.at,
                        now: now,
                        locale: locale
                    )
                )
                pieces.append(AnchorActivityPresentation.title(for: activity.op))
            } else {
                pieces.append("等待你的 Agent 指令")
            }
            return pieces.joined(separator: " · ")
        case .failed(let reason):
            return reason
        }
    }

    /// 是否需要把状态行画成强调色（已连接 = 强调色，失败 = 语义红）。
    public static func isAccented(_ phase: AnchorSessionPhase) -> Bool {
        if case .connected = phase { return true }
        return false
    }

    public static func isFailure(_ phase: AnchorSessionPhase) -> Bool {
        if case .failed = phase { return true }
        return false
    }
}

// MARK: - 操作记录文案

/// AnchorActivityEntry 的展示映射：op → 中文标题，status → 徽标。
public enum AnchorActivityPresentation {
    /// 已知 op 的中文标题；未知 op 原样显示（便于排查）。
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

    /// status：applied | deferred | rejected
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
/// 结构对齐 HakoProductRootPage（该类型是包内 internal，无法跨模块复用）。
struct AnchorPageScaffold<Content: View>: View {
    let palette: HakoClientUI.HakoProductPalette
    let accessibilityIdentifier: String
    private let content: Content

    @Environment(\.hakoDetailCanvas) private var detailCanvas

    init(
        palette: HakoClientUI.HakoProductPalette,
        accessibilityIdentifier: String,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.accessibilityIdentifier = accessibilityIdentifier
        self.content = content()
    }

    var body: some View {
        Group {
            if HakoClientUI.HakoPlatformLayout.pageUsesSystemSettingsIdiom,
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
                        spacing: HakoClientUI.HakoTheme.Spacing.section
                    ) {
                        content
                    }
                    .padding(.horizontal, HakoClientUI.HakoTheme.Layout.cardHorizontalInset)
                    .padding(.vertical, HakoClientUI.HakoTheme.Spacing.section)
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

/// 标准符号渲染：本目录只用内置 SF Symbol（不含 hako.* 自定义符号），
/// 故直接取 rawValue；宿主侧的候选回退与光学缩放不参与。
struct AnchorSymbolImage: View {
    let symbol: HakoSymbol

    var body: some View {
        Image(systemName: symbol.rawValue)
            .accessibilityHidden(true)
    }
}

/// 只读「标题 + 值」行（设置页的 id / 指纹 / 端点）。
/// 与 HakoProductDestinationRow 同构：正文标题 + 等宽值 + 可选中文本。
struct AnchorValueRow: View {
    let title: String
    let value: String
    let symbol: HakoSymbol
    var monospaced = true
    var selectable = true

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: HakoClientUI.HakoTheme.Spacing.row) {
            Label {
                Text(HakoCopy.key(title))
                    .foregroundStyle(.primary)
            } icon: {
                AnchorSymbolImage(symbol: symbol)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: HakoClientUI.HakoTheme.Spacing.row)
            Text(value)
                .font(monospaced ? .system(.subheadline, design: .monospaced) : .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
                .fixedSize(horizontal: false, vertical: true)
                .modifier(AnchorSelectableText(enabled: selectable))
        }
        .font(.subheadline)
        .frame(
            maxWidth: .infinity,
            minHeight: HakoClientUI.HakoTheme.Control.pointerRowTarget,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }
}

/// iOS 15 起支持 textSelection；tvOS 不提供，故按平台短路。
private struct AnchorSelectableText: ViewModifier {
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
/// ⚠️ 必须在 #if DEBUG 之外——AnchorHomeCard 的默认参数引用它。
public extension HakoClientUI.HakoProductPalette {
    static var anchorPreview: Self {
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
final class AnchorPreviewBridge: AnchorBridgeObservable {
    @Published private(set) var phase: AnchorSessionPhase
    @Published private(set) var isPaired: Bool
    @Published private(set) var agentID: String?
    @Published private(set) var recentActivity: [AnchorActivityEntry]

    init(
        phase: AnchorSessionPhase = .idle,
        isPaired: Bool = false,
        agentID: String? = nil,
        recentActivity: [AnchorActivityEntry] = []
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
final class AnchorPreviewPairingService: AnchorPairingServiceProtocol, AnchorSASCodeProviding,
    @unchecked Sendable {
    let agentFingerprint = "J5H2QT9M4N7Q2W8Z"
    let sasCode: String? = "418 296"

    private let agents: [AnchorBonjourAgent]

    init(
        agents: [AnchorBonjourAgent] = [
            AnchorBonjourAgent(
                id: "4N7Q2W8Z0R5TVK9Y",
                name: "Mac Studio",
                endpoint: "wss://192.168.1.20:8787/anchor"
            ),
            AnchorBonjourAgent(
                id: "9Y8W7V6T5R4Q3P2N",
                name: "Arch 工作站",
                endpoint: "wss://192.168.1.31:8787/anchor"
            ),
        ]
    ) {
        self.agents = agents
    }

    func discoverAgents() -> AsyncStream<[AnchorBonjourAgent]> {
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
        bonjour agent: AnchorBonjourAgent,
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
func anchorPreviewActivity(_ items: [(String, TimeInterval, String)]) -> [AnchorActivityEntry] {
    items.enumerated().map { index, item in
        AnchorActivityEntry(
            id: "01J8Z6Q2W8Z0R5TVK9Y\(index)",
            op: item.0,
            at: Date().addingTimeInterval(item.1),
            status: item.2
        )
    }
}

/// 预览用示例 profile。
let anchorPreviewProfile = AnchorAgentProfile(
    agentID: "4N7Q2W8Z0R5TVK9Y",
    agentName: "Mac Studio",
    fingerprint: "J5H2QT9M4N7Q2W8Z",
    endpoint: "wss://192.168.1.20:8787/anchor"
)

#endif
