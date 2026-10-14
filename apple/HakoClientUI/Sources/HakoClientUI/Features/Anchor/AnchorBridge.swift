import Combine
import Foundation
import HakoAgentKit
import SwiftUI

/// AnchorBridge — P2 各组件的公共接口契约。
///
/// 四个并行工作流的交汇点：
///   A. AnchorConnector（AC 会话层）   —— 实现本文件协议
///   B. AnchorPairingService（配对）   —— 消费 AnchorConnector
///   C. AnchorAppCommandExecutor      —— 实现 AnchorCommandHandling
///   D. UI（Agent 卡 / 配对页）        —— 只依赖 AnchorBridgeObservable
///
/// 修改本文件需同步告知四条工作流。

// MARK: - 会话状态（UI 可观察）

public enum AnchorSessionPhase: Equatable, Sendable {
    case idle                 // 从未配对
    case connecting           // 正在握手/连接
    case connected            // Noise 完成 + hello 完成
    case suspended            // App 后台，会话挂起
    case failed(reason: String)
}

// MARK: - 命令处理（AC → 执行器）

/// app.* 命令执行器协议（由 C 实现；AC 收到 cmd 后调它）
public protocol AnchorCommandHandling: AnyObject, Sendable {
    /// 执行 app.* 命令，返回 data（成功）或抛 AnchorCommandError（→ rejected）
    func execute(op: String, args: [String: JSONValue]) async throws -> [String: JSONValue]
    /// 本连接器支持的 op 清单（hello.caps 用）
    var supportedOps: [String] { get }
}

public struct AnchorCommandError: Error, Sendable {
    public let code: String      // envelope err.code（SCOPE_DENIED / TUNNEL_DOWN / ...）
    public let message: String
    public let hint: String?
    public init(code: String, message: String, hint: String? = nil) {
        self.code = code; self.message = message; self.hint = hint
    }
}

// MARK: - AC 会话层协议（A 实现）

public protocol AnchorConnecting: AnyObject, Sendable {
    /// 当前状态（UI 绑定）
    var phase: AnchorSessionPhase { get }
    /// 状态变化回调（主线程投递）
    var onPhaseChange: (@Sendable (AnchorSessionPhase) -> Void)? { get set }
    /// 收到设备→agent 方向事件（保留字；P2 一般无）
    var onEvent: (@Sendable ([String: JSONValue]) -> Void)? { get set }

    /// 注入命令执行器（hello.caps 由它提供；cmd 分发给它）
    func setCommandHandler(_ handler: AnchorCommandHandling?)

    /// 发起会话（已配对设备；内部管理 Noise + WSS + 重连退避）
    func start()
    /// 挂起（App 进后台调用）
    func suspend()
    /// 恢复（App 回前台调用）
    func resume()
    /// 停止并清理
    func stop()
}

// MARK: - 配对服务协议（B 实现）

public struct AnchorPairingDescriptor: Equatable, Sendable {
    public var uri: String          // hako://pair?...
    public var agentID: String      // agent 16 字符 id
    public var endpoints: [String]
    public init(uri: String, agentID: String, endpoints: [String]) {
        self.uri = uri; self.agentID = agentID; self.endpoints = endpoints
    }
}

public protocol AnchorPairingServiceProtocol: AnyObject, Sendable {
    /// 粘贴口令路径：解析 URI → Noise 握手 → pair.req（含 secret）
    func pair(withURI uri: String) async throws -> PairingResult
    /// Bonjour 路径：发现同一局域网的 agent（SAS 确认码双端比对）
    func discoverAgents() -> AsyncStream<[AnchorBonjourAgent]>
    func pair(bonjour agent: AnchorBonjourAgent, sasConfirmed: () async -> Bool) async throws -> PairingResult
    /// 当前 agent 静态公钥指纹（配对前人眼比对用）
    var agentFingerprint: String { get }
}

public struct AnchorBonjourAgent: Equatable, Sendable, Identifiable {
    public var id: String           // agent id
    public var name: String
    public var endpoint: String
    public init(id: String, name: String, endpoint: String) {
        self.id = id; self.name = name; self.endpoint = endpoint
    }
}

public struct PairingResult: Equatable, Sendable {
    public var accepted: Bool
    public var controller: Bool     // 本 agent 是否成为主控
    public var scopes: String       // observe | operate | manage
    public var agentName: String?
    public init(accepted: Bool, controller: Bool, scopes: String, agentName: String? = nil) {
        self.accepted = accepted; self.controller = controller; self.scopes = scopes; self.agentName = agentName
    }
}

// MARK: - UI 可观察总门面（D 只看这个）

/// 主 App 持有的总门面：把连接器/配对/执行器粘起来，UI 绑定它。
@MainActor
public protocol AnchorBridgeObservable: ObservableObject {
    var phase: AnchorSessionPhase { get }
    var isPaired: Bool { get }
    var agentID: String? { get }
    /// 最近的操作记录（操作记录页数据源）
    var recentActivity: [AnchorActivityEntry] { get }
    /// P3：true = 有待确认的配置 apply（显示一键撤销按钮）
    var hasPendingConfigApply: Bool { get }
    /// P3：撤销最近一次未确认的配置 apply（回滚到改动前）
    func undoLastConfigApply() async throws
    func startPairing(withURI uri: String) async
    func forgetPairing() async
    /// 类型擦除后的变更通知：具体实现转发 objectWillChange。
    /// （`any AnchorBridgeObservable` 的 objectWillChange 是 `any Publisher`，
    ///  不能直接喂给 SwiftUI 的 onReceive，故显式桥接。）
    func observeChanges(_ action: @escaping () -> Void) -> AnyCancellable
}

public struct AnchorActivityEntry: Equatable, Identifiable, Sendable {
    public var id: String           // ULID
    public var op: String
    public var at: Date
    public var status: String       // applied | deferred | rejected
    public init(id: String, op: String, at: Date, status: String) {
        self.id = id; self.op = op; self.at = at; self.status = status
    }
}

/// AnchorIdentityStoring —— 配对身份的存取契约（配对服务 / AC 会话层 / UI 共用）。
///
/// 说明：AnchorBridge.swift（四工作流契约文件）当前并未声明本协议；
/// 若主会话把它并入 AnchorBridge.swift，请删除本文件中的同名定义（避免重复声明）。
public protocol AnchorIdentityStoring: AnyObject, Sendable {
    /// 本设备 X25519 静态私钥（首次访问自动生成并落 Keychain）
    var deviceStaticKey: DHKey? { get }
    /// 本设备 id（"dev_" + 16 字符 Crockford；由设备公钥派生）
    var deviceId: String? { get }

    /// 已配对 agent 的 X25519 静态公钥原文（32B）
    var agentStaticKey: Data? { get }
    /// 已配对 agent 的直连 endpoint（ws:// 或 wss://）
    var agentEndpoint: String? { get }
    /// 已配对 agent 的 16 字符 id
    var agentID: String? { get }

    /// 配对成功（pair.res = accepted）后落盘
    func savePairing(agentID: String, agentStaticKey: Data, agentEndpoint: String) throws
    /// 忘记配对：只清 agent 侧（设备私钥保留——它标识本设备）
    func forgetPairing()
}

// MARK: - 环境注入（首页挂载）

/// 首页经环境取 Anchor 桥；未装配时为 nil → 卡片整段隐藏。
private struct AnchorBridgeEnvironmentKey: EnvironmentKey {
    // 类型擦除的包装类，非 Sendable——环境默认值用 nonisolated(unsafe) 标注
    nonisolated(unsafe) static let defaultValue: AnchorBridgeProxy? = nil
}

/// 类型擦除的可观察包装：把 `any AnchorBridgeObservable` 变成 SwiftUI 能订阅的
/// 具体类型（@ObservedObject / @EnvironmentObject 都不支持 existential）。
public final class AnchorBridgeProxy: ObservableObject {
    public let bridge: any AnchorBridgeObservable
    private var cancellable: AnyCancellable?
    @MainActor
    public init(_ bridge: any AnchorBridgeObservable) {
        self.bridge = bridge
        cancellable = bridge.observeChanges { [weak self] in
            self?.objectWillChange.send()
        }
    }
}

extension EnvironmentValues {
    /// App 侧装配：`\.anchorBridge = controller`（未配对/未启用保持 nil）。
    public var anchorBridge: AnchorBridgeProxy? {
        get { self[AnchorBridgeEnvironmentKey.self] }
        set { self[AnchorBridgeEnvironmentKey.self] = newValue }
    }
}

extension View {
    /// 装配入口：`view.anchorBridge(AnchorBridgeProxy(controller))`
    /// 未装配（nil）时首页 Anchor 区块整段隐藏（feature-off 无痕）。
    public func anchorBridge(_ bridge: AnchorBridgeProxy?) -> some View {
        environment(\.anchorBridge, bridge)
    }
}
