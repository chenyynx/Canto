import Combine
import Foundation
import SwiftUI
import HakoAgentKit
import HakoClientUI

/// AnchorBridgeController — AnchorBridgeObservable 的默认实现：
/// 把 AC 连接器、配对服务、命令执行器、身份存储装配成 UI 可绑定的总门面。
///
/// 本文件是 P2 四条并行工作流的装配点（A 连接器 / B 配对 / C 执行器 / D UI）。
/// 组件均以协议依赖（AnchorBridge.swift），此处在 App 启动时组装。
@MainActor
public final class AnchorBridgeController: ObservableObject, AnchorBridgeObservable {
    @Published public private(set) var phase: AnchorSessionPhase = .idle
    @Published public private(set) var recentActivity: [AnchorActivityEntry] = []
    @Published public private(set) var pairingAgentID: String?

    private let connecting: AnchorConnecting
    private let pairing: AnchorPairingServiceProtocol
    private let identity: AnchorIdentityStoring
    private let commandHandler: AnchorCommandHandling?
    private let activityLog: AnchorActivityLogging

    public init(
        connecting: AnchorConnecting,
        pairing: AnchorPairingServiceProtocol,
        identity: AnchorIdentityStoring,
        commandHandler: AnchorCommandHandling?,
        activityLog: AnchorActivityLogging = AnchorActivityLog.shared
    ) {
        self.connecting = connecting
        self.pairing = pairing
        self.identity = identity
        self.commandHandler = commandHandler
        self.activityLog = activityLog
        connecting.onPhaseChange = { [weak self] newPhase in
            Task { @MainActor in
                self?.phase = newPhase
            }
        }
        refreshPairedState()
    }

    // MARK: - AnchorBridgeObservable

    public var isPaired: Bool {
        identity.agentEndpoint != nil && identity.deviceStaticKey != nil
    }

    public var agentID: String? {
        pairingAgentID ?? identity.agentID
    }

    public func startPairing(withURI uri: String) async {
        phase = .connecting
        do {
            let result = try await pairing.pair(withURI: uri)
            if result.accepted {
                refreshPairedState()
                connecting.start()
                activityLog.append(.init(
                    id: AnchorIDs.ulid(),
                    op: "pairing.completed",
                    at: Date(),
                    status: "applied"
                ))
            } else {
                phase = .failed(reason: "配对被拒绝")
            }
        } catch {
            phase = .failed(reason: String(describing: error))
        }
    }

    public func observeChanges(_ action: @escaping () -> Void) -> AnyCancellable {
        objectWillChange.sink { _ in action() }
    }

    public func forgetPairing() async {
        await identity.forgetPairing()
        connecting.stop()
        pairingAgentID = nil
        phase = .idle
        recentActivity.removeAll()
    }

    // MARK: - P3 配置一键撤销

    public var hasPendingConfigApply: Bool {
        AnchorConfigStore.defaultStore()?.loadPending() != nil
    }

    public func undoLastConfigApply() async throws {
        guard let store = AnchorConfigStore.defaultStore() else {
            throw AnchorConfigError.nothingToRollback
        }
        let manager = AnchorConfigManager(
            store: store,
            defaults: GlobalConfig.appGroupDefaults,
            liveness: { true })
        _ = try await manager.undoLast()
        recentActivity.insert(.init(
            id: AnchorIDs.ulid(), op: "config.rollback", at: Date(), status: "applied"), at: 0)
    }

    // MARK: - 私有

    private func refreshPairedState() {
        pairingAgentID = identity.agentID
        if isPaired {
            // App 启动即恢复会话（若 agent 在线）
            connecting.setCommandHandler(commandHandler)
            connecting.start()
        }
    }
}

/// 操作记录持久化（设置页 + 首页卡副行数据源）。
public protocol AnchorActivityLogging: Sendable {
    func append(_ entry: AnchorActivityEntry)
    func recent(limit: Int) -> [AnchorActivityEntry]
}

/// 内存版实现（P2 基础版；持久化升级在 P3 的操作记录任务里做）。
public final class AnchorActivityLog: AnchorActivityLogging, @unchecked Sendable {
    public static let shared = AnchorActivityLog()
    private let lock = NSLock()
    private var entries: [AnchorActivityEntry] = []
    private let capacity = 200

    public init() {}

    public func append(_ entry: AnchorActivityEntry) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
        if entries.count > capacity {
            entries.removeFirst(entries.count - capacity)
        }
    }

    public func recent(limit: Int) -> [AnchorActivityEntry] {
        lock.lock()
        defer { lock.unlock() }
        return Array(entries.suffix(limit).reversed())
    }
}

extension AnchorBridgeController {
    /// App 启动装配：真实依赖全部在此汇合（唯一组装点）。
    @MainActor
    static func assemble(vpn: VPNController, profiles: ProfilesViewModel) -> AnchorBridgeController {
        let identity = AnchorIdentityStore()
        let executor = AnchorAppCommandExecutor(
            vpn: AnchorVPNServiceAdapter(controller: vpn),
            profiles: AnchorProfileServiceAdapter(model: profiles)
        )
        let connector = AnchorConnector(identity: identity)
        connector.setCommandHandler(executor)
        let pairing = AnchorPairingService(identity: identity)
        let controller = AnchorBridgeController(
            connecting: connector,
            pairing: pairing,
            identity: identity,
            commandHandler: executor
        )
        // P4：APNs 静默推送唤醒 → 重连 daemon → hello 后自动补发队列命令
        AnchorPushService.shared.onWake = { [weak controller] in
            Task { @MainActor in
                controller?.wakeAndResync()
            }
        }
        return controller
    }

    /// P4 唤醒路径：APNs 静默推送把 App 拉起数十秒——立即补连（配对状态
    /// 且未连接时），连上后 hello 触发 daemon 补发队列命令；期间保持在
    /// 后台运行许可内完成，不做任何额外 UI。
    @MainActor
    public func wakeAndResync() {
        guard isPaired, phase != .connected else { return }
        refreshPairedState() // connecting.start() 幂等；在线则无操作
    }
}
