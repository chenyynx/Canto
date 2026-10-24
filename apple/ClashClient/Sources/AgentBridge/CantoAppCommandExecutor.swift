#if os(iOS) || os(macOS)
import Foundation
import CantoAgentKit
import ClashClientKit
import ClashClientUI

//  CantoAppCommandExecutor —— Canto 协议 P2 · app.* 命令执行器（工作流 C）
//
//  职责：把 agent 下发的 app.* 命令映射到 Clash 客户端已有的 App 能力。
//  原则：只复用、不重写——每条 op 都落到现有 ViewModel/控制器的既有入口，
//        本文件不含任何新的订阅下载、配置生成或 VPN 协议逻辑。
//
//  依赖注入：执行器只依赖下面三个 @MainActor 依赖接口，真实 App 对象经同文件的
//  Adapter 在装配处传入（例如 AppShellView 里 `CantoVPNServiceAdapter(controller: vpn)`）。
//  执行器自身不访问任何单例，也不访问 static shared。
//
//  ⚠️ 装配前提：ClashiOS target 已声明 `- package: CantoAgentKit`；
//     ClashmacOS target 目前未声明该依赖（见 project.yml 的 dependencies），
//     在 macOS 侧编译 AgentBridge 前需补齐。
//
//  行数预算：≤ 560 行

// MARK: - 依赖接口（由主会话在 App 装配时注入）

/// VPN 开关能力。真实实现见文件末尾 `CantoVPNServiceAdapter`（包 `VPNController`）。
@MainActor
protocol CantoVPNServicing: AnyObject, Sendable {
    /// 当前隧道快照（`VPNController.status` / 系统授权状态 / 最近错误）
    var state: CantoVPNState { get }
    /// 请求启动隧道；返回 false 表示启动请求未发出（失败或需要用户确认系统弹窗）
    func requestStart() async -> Bool
    /// 请求停止隧道（等待停止请求送达系统；含关掉 on-demand，避免立刻被拉起）
    func requestStop() async
}

/// 订阅（profile）管理能力。真实实现见文件末尾 `CantoProfileServiceAdapter`（包 `ProfilesViewModel`）。
@MainActor
protocol CantoProfileServicing: AnyObject, Sendable {
    /// 当前激活的订阅 id（`ProfilesViewModel.activeProfileID`）
    func activeProfileID() async -> String?
    /// 全部订阅摘要（顺序与订阅中心一致）
    func listProfiles() async -> [CantoProfileSummary]
    /// 新建订阅：`ProfilesViewModel.installSubscription` 同路径，等待新订阅落库
    func addSubscription(url: String, name: String?, autoUpdateHours: Int?,
                         waitUpTo seconds: TimeInterval) async throws -> CantoProfileAddReceipt
    /// 切换订阅：`ProfilesViewModel.selectAndWait`（stage→reload 单事务，等完成）
    func selectProfile(id: String, force: Bool) async throws -> CantoProfileSelectReceipt
    /// 刷新订阅：id 为空 = 全部（`syncAll`），否则单个（`sync`）
    func refreshProfiles(id: String?, waitUpTo seconds: TimeInterval) async throws -> CantoRefreshReceipt
    /// 删除订阅：`ProfilesViewModel.delete`（含删除前的策略校验）
    func removeProfile(id: String) async throws -> CantoProfileSummary
}

/// 只读内核状态（可选注入）。真实实现见 `CantoCoreStatusAdapter`（包 `ClashCommandClient`）。
@MainActor
protocol CantoCoreStatusProviding: AnyObject, Sendable {
    func coreState() async -> CantoCoreState
}

// MARK: - 值类型（执行器 ↔ 适配器之间的 Sendable 快照；均为 App 现有类型的投影）

/// VPN 开关快照。`status` 原样取 `VPNController.status`。
struct CantoVPNState: Sendable, Equatable {
    var on: Bool                    // connected | connecting | reasserting
    var status: String              // connected / connecting / disconnecting / disconnected / not installed / invalid / idle / unknown
    var authorization: String?      // required / waiting / not_completed（null = 无需用户操作）
    var transitioning: Bool         // connecting | disconnecting | reasserting
    var lastError: String

    static let unknown = CantoVPNState(on: false, status: "unknown", authorization: nil,
                                       transitioning: false, lastError: "")
}

/// 订阅用量（订阅中心等价信息）。`expire` 原样是 unix 秒。
struct CantoSubscriptionUsage: Sendable, Equatable {
    var uploadBytes: Int64
    var downloadBytes: Int64
    var totalBytes: Int64
    var expireAt: Date?
}

/// 单个订阅摘要（app.profile.list / app.state.get 的元素）。
struct CantoProfileSummary: Sendable, Equatable {
    var id: String
    var name: String                // profile.label（内置兜底为 "Direct"）
    var kind: String                // url | file | clipboard
    var builtIn: Bool               // 内置 Direct 兜底配置（不可删除）
    var active: Bool
    var autoUpdate: Bool
    var updateIntervalHours: Int
    var updatedAt: Date?            // 配置库记录优先，退回 profile.lastUpdatedAt
    var nodeCount: Int?             // 配方 → 各订阅源 nodeCount 之和（与订阅中心同一口径）
    var usage: CantoSubscriptionUsage?
}

/// app.profile.add 回执。
struct CantoProfileAddReceipt: Sendable, Equatable {
    var id: String
    var name: String
    var created: Bool               // 新建
    var existing: Bool              // 命中已有同 URL 订阅（未新建，仅触发同步）
    var pending: Bool               // 已入队但超时未落库（AC 可映射 deferred）
    var metadataApplied: Bool?      // 是否成功应用 name / auto_update_hours
    var note: String?
}

/// app.profile.select 回执。
struct CantoProfileSelectReceipt: Sendable, Equatable {
    var id: String
    var name: String
    var appliedToTunnel: Bool?      // ProfilesViewModel.activationAppliesToTunnel
}

/// app.profile.update 回执。
struct CantoRefreshReceipt: Sendable, Equatable {
    var scope: String               // id | all
    var id: String?
    var started: Bool               // 刷新请求已交给 App 侧任务
    var settled: Bool               // 观测到 App 侧刷新队列回到空闲
    var waitedMs: Int
    var note: String?
}

/// 内核只读状态（app.state.get 的 core 段；仅注入 core 依赖时出现）。
struct CantoCoreState: Sendable, Equatable {
    var connected: Bool
    var tunnelUp: Bool
    var mode: String
    var coreVersion: String
    var memoryBytes: Int64
    var uploadTotalBytes: Int64
    var downloadTotalBytes: Int64
}

// MARK: - 执行器

/// app.* 命令执行器。`execute` 是 nonisolated async，所有 App 能力都在 @MainActor 上 await 调用。
final class CantoAppCommandExecutor: CantoCommandHandling {

    private let vpn: any CantoVPNServicing
    private let profiles: any CantoProfileServicing
    private let core: (any CantoCoreStatusProviding)?
    /// P3: config manager built lazily (needs app-group storage); `store` is
    /// kept for configGet's pending preview.
    private var manager: CantoConfigManager?
    var store: CantoConfigStore? { CantoConfigStore.defaultStore() }

    init(vpn: any CantoVPNServicing,
         profiles: any CantoProfileServicing,
         core: (any CantoCoreStatusProviding)? = nil) {
        self.vpn = vpn
        self.profiles = profiles
        self.core = core
    }

    // MARK: 能力清单（hello.caps.app）

    private static let opList: [String] = [
        "app.state.get",
        "app.vpn.start",
        "app.vpn.stop",
        "app.profile.list",
        "app.profile.add",
        "app.profile.select",
        "app.config.get",
        "app.config.patch",
        "app.config.apply",
        "app.config.confirm",
        "app.config.rollback",
        "app.profile.update",
        "app.profile.remove",
        "app.config.apply",
    ]

    var supportedOps: [String] { Self.opList }

    // MARK: 分发

    func execute(op: String, args: [String: JSONValue]) async throws -> [String: JSONValue] {
        switch op {
        case "app.state.get":      return try await stateGet(args)
        case "app.vpn.start":      return try await vpnStart(args)
        case "app.vpn.stop":       return try await vpnStop(args)
        case "app.profile.list":   return try await profileList(args)
        case "app.profile.add":    return try await profileAdd(args)
        case "app.profile.select": return try await profileSelect(args)
        // 测试向量里该 op 名为 app.profile.refresh，P2 清单里为 app.profile.update：
        // 两者同一条路径，refresh 作为未广告的别名接受。
        case "app.profile.update", "app.profile.refresh":
            return try await profileUpdate(args)
        case "app.profile.remove": return try await profileRemove(args)
        case "app.config.apply":
            return try await configApply(args)
        case "app.config.get":      return try await configGet(args)
        case "app.config.patch":    return try await configPatch(args)
        case "app.config.confirm":  return try await configConfirm(args)
        case "app.config.rollback": return try await configRollback(args)
        default:
            throw CantoCommandError(
                code: "UNSUPPORTED",
                message: "未知 app.* 命令：\(op)",
                hint: "支持的 op 见 hello.caps.app（\(Self.opList.count) 条）")
        }
    }

    // MARK: - app.state.get
    //
    // data 结构（字段名 snake_case）：
    // {
    //   "vpn": { "on": Bool, "state": String, "authorization": String|null,
    //            "transitioning": Bool, "last_error": String },
    //   "profile": { 同 app.profile.list 元素 } | null,      // 当前激活订阅
    //   "profile_count": Int,                                 // 本机订阅总数（含内置兜底）
    //   "app": { "version": String, "build": String, "locale": String },
    //   "core": { ... } | 缺席,                               // 仅注入 core 依赖时
    //   "at": "ISO8601"                                       // 快照时间（UTC）
    // }

    private func stateGet(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        let vpnState = await vpn.state
        let summaries = await profiles.listProfiles()
        let activeID = await profiles.activeProfileID()

        var data: [String: JSONValue] = [
            "vpn": Self.jsonVPN(vpnState),
            "profile": summaries.first { $0.id == activeID }.map { Self.jsonProfile($0) } ?? JSONValue.null,
            "profile_count": .int(Int64(summaries.count)),
            "app": Self.appFacts(),
            "at": .string(Self.iso(Date()) ?? ""),
        ]
        if let core {
            data["core"] = Self.jsonCore(await core.coreState())
        }
        // P4：on-demand（系统级兜底）状态——上游 OnDemandSettings 是唯一事实源，
        // Canto 只读暴露，不新增/不覆写规则。
        let onDemand = OnDemandSettings.configuration()
        data["on_demand"] = .object([
            "enabled": .bool(onDemand.enabled),
            "rule_count": .int(Int64(onDemand.rules.count)),
            "note": .string("由 App 内「按需连接」设置管理；agent 可通过本字段判断系统级兜底是否开启"),
        ])
        return data
    }

    // MARK: - app.vpn.start

    private func vpnStart(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        let timeout = timeout(args, fallback: 20, maximum: 60)
        var state = await vpn.state

        // 目标态幂等：已经开着（或正在连接）就直接回报，不再重复请求。
        if state.on {
            return ["vpn": Self.jsonVPN(state), "settled": .bool(true),
                    "already_on": .bool(true), "waited_ms": .int(0)]
        }

        let began = Date()
        let requested = await vpn.requestStart()
        if !requested {
            state = await vpn.state
            if state.authorization != nil {
                throw Self.needUserAction(hint: "请让用户在 App 里完成系统 VPN 授权弹窗（设置 → VPN）后重试 app.vpn.start")
            }
            let message = state.lastError.isEmpty ? "VPN 启动请求被系统拒绝（status=\(state.status)）" : state.lastError
            throw CantoCommandError(
                code: "CORE_ERROR", message: message,
                hint: "隧道未启动；让用户打开 App 查看连接失败详情，或稍后重试 app.vpn.start")
        }

        let settled = try await waitForConnected(timeout: timeout)
        state = await vpn.state
        let waited = Int(Date().timeIntervalSince(began) * 1000)

        // 启动请求已发出但用户还没确认系统弹窗 → 明确要求用户动作。
        if !state.on, let authorization = state.authorization {
            throw Self.needUserAction(
                hint: "当前系统授权状态 authorization=\(authorization)；用户确认后重试 app.vpn.start")
        }

        var data: [String: JSONValue] = [
            "vpn": Self.jsonVPN(state),
            "settled": .bool(settled),
            "already_on": .bool(false),
            "waited_ms": .int(Int64(waited)),
        ]
        if !settled {
            // 隧道仍在 connecting/reasserting：不谎报 applied，让 AC 自行映射 deferred。
            data["note"] = .string("启动请求已发出，但 \(Int(timeout)) 秒内未观测到 connected（当前 status=\(state.status)）；建议 AC 映射 deferred，之后用 app.state.get 复核")
        }
        return data
    }

    // MARK: - app.vpn.stop

    private func vpnStop(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        let timeout = timeout(args, fallback: 10, maximum: 60)
        var state = await vpn.state

        if !state.on {
            return ["vpn": Self.jsonVPN(state), "settled": .bool(true),
                    "already_off": .bool(true), "waited_ms": .int(0)]
        }

        let began = Date()
        await vpn.requestStop()
        let settled = try await waitForStopped(timeout: timeout)
        state = await vpn.state
        let waited = Int(Date().timeIntervalSince(began) * 1000)

        var data: [String: JSONValue] = [
            "vpn": Self.jsonVPN(state),
            "settled": .bool(settled),
            "already_off": .bool(false),
            "waited_ms": .int(Int64(waited)),
        ]
        if !settled {
            data["note"] = .string("停止请求已发出，但 \(Int(timeout)) 秒内未观测到断开（当前 status=\(state.status)）；建议 AC 映射 deferred")
        }
        return data
    }

    /// 轮询等待隧道进入 connected（隧道连接由系统/扩展异步完成，`VPNController.start` 返回即“请求已发出”）。
    private func waitForConnected(timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let state = await vpn.state
            if state.status == "connected" { return true }
            if !state.on, state.authorization != nil { return false }   // 权限没确认，不会自己好
            if ["disconnected", "not installed", "invalid"].contains(state.status) { return false }
            if Date() >= deadline { return false }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    /// 轮询等待隧道离开“开着”的状态。
    private func waitForStopped(timeout: TimeInterval) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let state = await vpn.state
            if !state.on { return true }
            if Date() >= deadline { return false }
            try await Task.sleep(nanoseconds: 250_000_000)
        }
    }

    // MARK: - app.profile.list
    //
    // args：limit（Int，默认 100，上限 500）、include_builtin（Bool，默认 true）
    // data：{ "profiles": [元素], "count": Int, "total": Int, "active_id": String|null, "truncated": Bool }
    // 元素：
    // {
    //   "id": String, "name": String,            // 订阅名（label）
    //   "kind": "url"|"file"|"clipboard",        // 来源类型
    //   "built_in": Bool,                        // 内置 Direct 兜底（不可删除）
    //   "active": Bool,                          // 是否是当前激活订阅
    //   "auto_update": Bool, "update_interval_hours": Int,
    //   "updated_at": ISO8601|null,              // 配置库记录优先，退回 profile.lastUpdatedAt
    //   "node_count": Int|null,                  // 配方 → 订阅源 nodeCount 之和
    //   "usage": { "upload_bytes": Int, "download_bytes": Int,
    //              "total_bytes": Int, "expire_at": ISO8601|null } | 缺席
    // }

    private func profileList(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        let includeBuiltIn = args["include_builtin"]?.boolValue ?? true
        let limit = min(max(intArg(args, "limit") ?? 100, 1), 500)
        let all = await profiles.listProfiles()
        let visible = includeBuiltIn ? all : all.filter { !$0.builtIn }
        let page = Array(visible.prefix(limit))
        let activeID = await profiles.activeProfileID()
        return [
            "profiles": .array(page.map { Self.jsonProfile($0) }),
            "count": .int(Int64(page.count)),
            "total": .int(Int64(visible.count)),
            "active_id": activeID.map { JSONValue.string($0) } ?? JSONValue.null,
            "truncated": .bool(page.count < visible.count),
        ]
    }

    // MARK: - app.profile.add
    //
    // args：url（必填）、name（可选）、auto_update_hours（可选，≥1）、timeout_s（可选）
    // data：{ "id": String, "name": String, "created": Bool, "existing": Bool,
    //        "pending": Bool, "metadata_applied": Bool?, "note": String? }

    private func profileAdd(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        let url = try requiredString(args, "url")
        let name = stringArg(args, "name")
        let hours = intArg(args, "auto_update_hours")
        if let hours, hours < 1 {
            throw CantoCommandError(
                code: "INVALID_ARGUMENT",
                message: "auto_update_hours 必须是 ≥ 1 的整数（收到 \(hours)）",
                hint: "省略该参数表示不改变默认自动更新间隔")
        }
        let receipt = try await profiles.addSubscription(
            url: url, name: name, autoUpdateHours: hours,
            waitUpTo: timeout(args, fallback: 25, maximum: 120))

        var data: [String: JSONValue] = [
            "id": .string(receipt.id),
            "name": .string(receipt.name),
            "created": .bool(receipt.created),
            "existing": .bool(receipt.existing),
            "pending": .bool(receipt.pending),
        ]
        if let applied = receipt.metadataApplied { data["metadata_applied"] = .bool(applied) }
        if let note = receipt.note { data["note"] = .string(note) }
        return data
    }

    // MARK: - app.profile.select
    //
    // args：id（必填）、force（可选，默认 false）
    // data：{ "id": String, "name": String, "active": true, "applied_to_tunnel": Bool|null }
    // applied_to_tunnel=false 表示配置已切换但隧道没吃上新配置（隧道没开时属正常）。

    private func profileSelect(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        let id = try requiredString(args, "id")
        let force = args["force"]?.boolValue ?? false
        let receipt = try await profiles.selectProfile(id: id, force: force)
        return [
            "id": .string(receipt.id),
            "name": .string(receipt.name),
            "active": .bool(true),
            "applied_to_tunnel": receipt.appliedToTunnel.map { JSONValue.bool($0) } ?? JSONValue.null,
        ]
    }

    // MARK: - app.profile.update
    //
    // args：id（可选；缺省 = 全部）、timeout_s（可选，默认 25，上限 120）
    // data：{ "scope": "id"|"all", "id": String?, "started": Bool, "settled": Bool,
    //        "waited_ms": Int, "note": String? }
    // 说明：刷新由 App 内部任务执行（订阅下载/解析），`started` 表示请求已交给 App；
    //       `settled` 只代表 App 侧刷新队列（busyProfileID / isSyncingAll）回到空闲——
    //       可再用 app.profile.list 的 updated_at 复核。AC 可据此映射 applied / deferred。

    private func profileUpdate(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        let id = stringArg(args, "id")
        let receipt = try await profiles.refreshProfiles(
            id: id, waitUpTo: timeout(args, fallback: 25, maximum: 120))
        var data: [String: JSONValue] = [
            "scope": .string(receipt.scope),
            "started": .bool(receipt.started),
            "settled": .bool(receipt.settled),
            "waited_ms": .int(Int64(receipt.waitedMs)),
        ]
        if let id = receipt.id { data["id"] = .string(id) }
        if let note = receipt.note { data["note"] = .string(note) }
        return data
    }

    // MARK: - app.profile.remove
    //
    // args：id（必填）
    // data：{ "id": String, "name": String, "removed": true }
    // 注意：删除当前激活的订阅时，App 会先自动切到内置兜底配置（既有 delete 行为）。

    private func profileRemove(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        let id = try requiredString(args, "id")
        let removed = try await profiles.removeProfile(id: id)
        return [
            "id": .string(removed.id),
            "name": .string(removed.name),
            "removed": .bool(true),
        ]
    }

    // MARK: - 参数取值（JSONValue → Swift；类型不符一律按“缺参数”处理）

    private func stringArg(_ args: [String: JSONValue], _ key: String) -> String? {
        guard let raw = args[key]?.stringValue else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func requiredString(_ args: [String: JSONValue], _ key: String) throws -> String {
        guard let value = stringArg(args, key) else {
            throw CantoCommandError(
                code: "INVALID_ARGUMENT", message: "缺少必填参数 \(key)",
                hint: "\(key) 为字符串；先按该 op 的参数约定补全后重试")
        }
        return value
    }

    private func number(_ args: [String: JSONValue], _ key: String) -> Double? {
        guard let value = args[key] else { return nil }
        switch value {
        case .int(let raw): return Double(raw)
        case .double(let raw): return raw
        default: return nil
        }
    }

    private func intArg(_ args: [String: JSONValue], _ key: String) -> Int? {
        number(args, key).map { Int($0) }
    }

    private func timeout(_ args: [String: JSONValue], fallback: TimeInterval, maximum: TimeInterval) -> TimeInterval {
        guard let value = number(args, "timeout_s"), value >= 0 else { return fallback }
        return min(value, maximum)
    }

    // MARK: - 错误构造

    /// `NEED_USER_ACTION`。envelope 的 err 支持 `action`（向量 res_need_user_action 要求
    /// action=vpn_permission），但 `CantoBridge.CantoCommandError` 目前只有 code/message/hint，
    /// 因此把 action 编进 hint 前缀「action=<x>｜」，由 AC 侧解析后填入 `res.err.action`。
    static func needUserAction(hint: String) -> CantoCommandError {
        CantoCommandError(
            code: "NEED_USER_ACTION",
            message: "需要用户在 App 上完成系统 VPN 授权确认",
            hint: "action=vpn_permission｜\(hint)")
    }

    // MARK: - 出参编码（统一在这里做 snake_case 映射）

    private static func iso(_ date: Date?) -> String? {
        guard let date else { return nil }
        return ISO8601DateFormatter().string(from: date)
    }

    private static func appFacts() -> JSONValue {
        let info = Bundle.main.infoDictionary
        let rawBuild = info?["CFBundleVersion"]
        return .object([
            "version": .string(info?["CFBundleShortVersionString"] as? String ?? "unknown"),
            "build": .string((rawBuild as? String) ?? (rawBuild as? NSNumber)?.stringValue ?? "unknown"),
            "locale": .string(Locale.current.identifier),
        ])
    }

    private static func jsonVPN(_ state: CantoVPNState) -> JSONValue {
        .object([
            "on": .bool(state.on),
            "state": .string(state.status),
            "authorization": state.authorization.map { JSONValue.string($0) } ?? JSONValue.null,
            "transitioning": .bool(state.transitioning),
            "last_error": .string(state.lastError),
        ])
    }

    private static func jsonProfile(_ summary: CantoProfileSummary) -> JSONValue {
        var fields: [String: JSONValue] = [
            "id": .string(summary.id),
            "name": .string(summary.name),
            "kind": .string(summary.kind),
            "built_in": .bool(summary.builtIn),
            "active": .bool(summary.active),
            "auto_update": .bool(summary.autoUpdate),
            "update_interval_hours": .int(Int64(summary.updateIntervalHours)),
            "updated_at": summary.updatedAt.flatMap { iso($0) }.map { JSONValue.string($0) } ?? JSONValue.null,
            "node_count": summary.nodeCount.map { JSONValue.int(Int64($0)) } ?? JSONValue.null,
        ]
        if let usage = summary.usage {
            fields["usage"] = .object([
                "upload_bytes": .int(usage.uploadBytes),
                "download_bytes": .int(usage.downloadBytes),
                "total_bytes": .int(usage.totalBytes),
                "expire_at": usage.expireAt.flatMap { iso($0) }.map { JSONValue.string($0) } ?? JSONValue.null,
            ])
        }
        return .object(fields)
    }

    private static func jsonCore(_ state: CantoCoreState) -> JSONValue {
        .object([
            "connected": .bool(state.connected),
            "tunnel_up": .bool(state.tunnelUp),
            "mode": .string(state.mode),
            "core_version": .string(state.coreVersion),
            "memory_bytes": .int(state.memoryBytes),
            "upload_total_bytes": .int(state.uploadTotalBytes),
            "download_total_bytes": .int(state.downloadTotalBytes),
        ])
    }

    // MARK: - app.config.*（P3：配置覆写 + 确认/回滚）

    /// Config manager built lazily: app-group file store + liveness = tunnel
    /// up. Reload is a no-op here — the overlay lands in the same store the
    /// activation pipeline reads, so it takes effect on next profile
    /// activation (documented; core untouched).
    private func configManager() throws -> CantoConfigManager {
        if let manager { return manager }
        guard let store = CantoConfigStore.defaultStore() else {
            throw CantoCommandError(
                code: "STORE_UNAVAILABLE",
                message: "app group 配置存储不可用",
                hint: "检查 App Group entitlements")
        }
        let built = CantoConfigManager(store: store, defaults: GlobalConfig.appGroupDefaults, liveness: { [weak self] in
            guard let self else { return false }
            let state = await self.vpn.state
            return state.on
        })
        manager = built
        return built
    }

    private func configGet(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        let manager = try configManager()
        let snap = manager.currentSnapshot()
        var data: [String: JSONValue] = [
            "rev": .int(Int64(snap.rev)),
            "patch": Self.jsonFromString(snap.patchJSON),
            "saved_at": .string(Self.iso8601(snap.savedAt)),
        ]
        if let pending = store?.loadPending() {
            data["pending"] = .object([
                "rev": .int(Int64(pending.rev)),
                "applied_at": .string(Self.iso8601(pending.appliedAt)),
                "confirm_within_s": .int(Int64(pending.confirmWithinS)),
            ])
        }
        return ["ok": .bool(true), "data": .object(data)]
    }

    private func configPatch(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        guard case .int(let baseRev)? = args["base_rev"],
              case .object(let patchObj)? = args["patch"] else {
            throw CantoCommandError(
                code: "BAD_ARGS",
                message: "app.config.patch 需要 base_rev(int) + patch(object)",
                hint: "先 app.config.get 拿当前 rev 与 patch")
        }
        let manager = try configManager()
        let staged = try manager.stage(baseRev: Int(baseRev), patch: Self.plainObject(.object(patchObj)))
        return ["ok": .bool(true), "data": .object([
            "rev": .int(Int64(staged.rev)),
            "merged": Self.jsonFromString(staged.mergedJSON),
        ])]
    }

    private func configApply(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        guard case .int(let baseRev)? = args["base_rev"],
              case .object(let patchObj)? = args["patch"] else {
            throw CantoCommandError(
                code: "BAD_ARGS",
                message: "app.config.apply 需要 base_rev(int) + patch(object)",
                hint: "标准流程：app.config.patch 预览 → app.config.apply 落地 → confirm_within_s 内 app.config.confirm")
        }
        let confirmWithinS: Int
        if case .int(let s)? = args["confirm_within_s"], s >= 10, s <= 600 { confirmWithinS = Int(s) }
        else { confirmWithinS = 60 }
        let manager = try configManager()
        let staged = try manager.stage(baseRev: Int(baseRev), patch: Self.plainObject(.object(patchObj)))
        let snap = try await manager.apply(rev: staged.rev, mergedJSON: staged.mergedJSON, confirmWithinS: confirmWithinS, reload: {})
        return ["ok": .bool(true), "data": .object([
            "rev": .int(Int64(snap.rev)),
            "status": .string("applied_pending_confirm"),
            "confirm_within_s": .int(Int64(confirmWithinS)),
            "note": .string("confirm_within_s 秒内请 app.config.confirm(rev)；超时或连接断开将自动回滚"),
        ])]
    }

    private func configConfirm(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        guard case .int(let rev)? = args["rev"] else {
            throw CantoCommandError(code: "BAD_ARGS", message: "app.config.confirm 需要 rev(int)", hint: "apply 返回的 rev")
        }
        let manager = try configManager()
        try await manager.confirm(rev: Int(rev), reload: {})
        return ["ok": .bool(true), "data": .object(["rev": .int(rev), "status": .string("confirmed")])]
    }

    private func configRollback(_ args: [String: JSONValue]) async throws -> [String: JSONValue] {
        let rev: Int? = { if case .int(let r)? = args["rev"] { return Int(r) }; return nil }()
        let manager = try configManager()
        let snap = try await manager.rollback(rev: rev, reload: {})
        return ["ok": .bool(true), "data": .object([
            "rev": .int(Int64(snap.rev)), "status": .string("rolled_back"),
        ])]
    }

    // MARK: JSONValue helpers

    private static func iso8601(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    /// JSONValue object → [String: Any] for the config manager.
    private static func plainObject(_ value: JSONValue) -> [String: Any] {
        guard case .object(let obj) = value else { return [:] }
        return obj.mapValues { plainAny($0) }
    }

    private static func plainObject(_ obj: [String: JSONValue]) -> [String: Any] {
        obj.mapValues { plainAny($0) }
    }

    private static func plainAny(_ value: JSONValue) -> Any {
        switch value {
        case .null: return NSNull()
        case .bool(let b): return b
        case .int(let i): return i
        case .double(let d): return d
        case .string(let s): return s
        case .array(let arr): return arr.map(plainAny)
        case .object(let obj): return obj.mapValues(plainAny)
        }
    }

    /// Patch JSON string → JSONValue (parsed, so agents get real JSON back).
    private static func jsonFromString(_ json: String) -> JSONValue {
        guard !json.isEmpty,
              let obj = try? JSONSerialization.jsonObject(with: Data(json.utf8)) else { return .object([:]) }
        return jsonValue(obj)
    }

    private static func jsonValue(_ any: Any) -> JSONValue {
        switch any {
        case is NSNull: return .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return .bool(n.boolValue) }
            let isIntegral = n.doubleValue == floor(n.doubleValue) && abs(n.doubleValue) < 1e15
            return isIntegral ? .int(n.int64Value) : .double(n.doubleValue)
        case let s as String: return .string(s)
        case let arr as [Any]: return .array(arr.map(jsonValue))
        case let obj as [String: Any]: return .object(obj.mapValues(jsonValue))
        default: return .null
        }
    }
}

// MARK: - 真实能力适配器（把接口接到 App 现有对象；接口之外的逻辑一律不新增）

/// `CantoVPNServicing` → 既有 `VPNController`（App 里已 @StateObject 持有的那一个）。
///
/// iOS 与 macOS 的系统 VPN 控制器签名不同（iOS：`start(origin:)` / `stop(site:origin:)`；
/// macOS：`start()` / `stop()`），差异只在这里用 #if 收口，执行器看不到。
@MainActor
final class CantoVPNServiceAdapter: CantoVPNServicing {

    private let controller: VPNController

    init(controller: VPNController) { self.controller = controller }

    var state: CantoVPNState {
        let status = controller.status
        return CantoVPNState(
            on: Self.liveStatuses.contains(status),
            status: status,
            authorization: Self.authorizationWord(controller.systemVPNAuthorization),
            transitioning: Self.transitioningStatuses.contains(status),
            lastError: controller.lastError)
    }

    func requestStart() async -> Bool {
        #if os(iOS)
        // .programmatic：程序触发，跳过手势去抖窗口（TunnelRequestCoalescer.Origin）
        return await controller.start(origin: .programmatic)
        #else
        return await controller.start()
        #endif
    }

    func requestStop() async {
        #if os(iOS)
        // .userButton 语义 = 明确的外部停止请求：顺带关掉 on-demand，避免隧道被立刻拉起
        await controller.stop(site: .userButton, origin: .programmatic)
        #else
        await controller.stop()
        #endif
    }

    /// 与 `VPNController` 内部 `["connected","connecting","reasserting"].contains(status)` 同一口径
    private static let liveStatuses: Set<String> = ["connected", "connecting", "reasserting"]
    private static let transitioningStatuses: Set<String> = ["connecting", "disconnecting", "reasserting"]

    private static func authorizationWord(_ authorization: ClashVPNAuthorizationState?) -> String? {
        switch authorization {
        case .some(.required): return "required"
        case .some(.waiting): return "waiting"
        case .some(.notCompleted): return "not_completed"
        case .none: return nil
        }
    }
}

/// `CantoProfileServicing` → 既有 `ProfilesViewModel`（订阅中心同一个实例，状态天然一致）。
///
/// 所有写操作都走订阅页的同一条路径：`installSubscription` / `selectAndWait` /
/// `sync` / `syncAll` / `delete` / `updateMetadata`，本适配器只做参数校验、结果读取与等待。
@MainActor
final class CantoProfileServiceAdapter: CantoProfileServicing {

    private let model: ProfilesViewModel

    init(model: ProfilesViewModel) { self.model = model }

    // MARK: 读

    func activeProfileID() async -> String? {
        ensureLoaded()
        return model.activeProfileID
    }

    func listProfiles() async -> [CantoProfileSummary] {
        ensureLoaded()
        let library = self.library()
        let activeID = model.activeProfileID
        return model.profiles.map { Self.summary(of: $0, library: library, activeID: activeID) }
    }

    // MARK: 写

    func addSubscription(url: String, name: String?, autoUpdateHours: Int?,
                         waitUpTo seconds: TimeInterval) async throws -> CantoProfileAddReceipt {
        ensureLoaded()

        // 与 installSubscription 相同的去重语义：URL 完全一致时只触发同步，不新建。
        if let existing = model.profiles.first(where: { profile in
            if case let .url(stored) = profile.source { return stored == url }
            return false
        }) {
            model.installSubscription(url)
            return CantoProfileAddReceipt(
                id: existing.id, name: existing.label,
                created: false, existing: true, pending: false, metadataApplied: nil,
                note: "同 URL 订阅已存在（id=\(existing.id)），已按订阅中心的方式触发同步")
        }

        // URL 形状校验与 Profile.RemoteSource 同一判定：http(s) + 主机名。
        guard Self.isUsableSubscriptionURL(url) else {
            throw CantoCommandError(
                code: "INVALID_ARGUMENT", message: "订阅 URL 不可用：\(url)",
                hint: "需要 http(s):// 且带主机名的订阅地址（与订阅中心同一校验）")
        }

        let knownIDs = Set(model.profiles.map(\.id))
        let failureBefore = model.lastFailure
        model.installSubscription(url)          // ← 订阅页同入口：入队序列化 → quickCreate(.link)
        let deadline = Date().addingTimeInterval(seconds)
        var created: Profile?
        while Date() < deadline {
            created = model.profiles.first { !knownIDs.contains($0.id) }
            if created != nil { break }
            if let failure = model.lastFailure, failure != failureBefore { break }
            try await Task.sleep(nanoseconds: 250_000_000)
        }

        guard let created else {
            if let failure = model.lastFailure, failure != failureBefore {
                throw CantoCommandError(
                    code: "CORE_ERROR",
                    message: failure.errorDescription ?? failure.message,
                    hint: "订阅下载/解析失败：确认 URL 可达且内容是合法 Clash 订阅，然后重试 app.profile.add")
            }
            let progress = model.statusMessage.resolved(locale: .current)
            return CantoProfileAddReceipt(
                id: "", name: name ?? "",
                created: false, existing: false, pending: true, metadataApplied: nil,
                note: progress.isEmpty
                    ? "导入仍在 App 侧进行（\(Int(seconds))s 内未落库），建议 AC 映射 deferred，之后用 app.profile.list 复核"
                    : "导入仍在进行：\(progress)；建议 AC 映射 deferred")
        }

        // name / auto_update_hours 走订阅页的同一保存入口（updateMetadata）。
        var metadataApplied: Bool?
        var note: String?
        if name != nil || autoUpdateHours != nil {
            let target = model.profiles.first { $0.id == created.id } ?? created
            let storedURL: String? = {
                if case let .url(value) = target.source { return value }
                return nil
            }()
            do {
                try model.updateMetadata(
                    target,
                    label: name ?? target.label,
                    subscriptionURL: storedURL,
                    autoUpdate: autoUpdateHours.map { _ in true } ?? target.autoUpdate,
                    updateIntervalHours: max(autoUpdateHours ?? target.updateIntervalHours, 1))
                metadataApplied = true
            } catch {
                metadataApplied = false
                note = "订阅已创建，但名称/自动更新设置未生效：\(error.localizedDescription)"
            }
        }

        let latest = model.profiles.first { $0.id == created.id } ?? created
        return CantoProfileAddReceipt(
            id: latest.id, name: latest.label,
            created: true, existing: false, pending: false,
            metadataApplied: metadataApplied, note: note)
    }

    func selectProfile(id: String, force: Bool) async throws -> CantoProfileSelectReceipt {
        ensureLoaded()
        guard let profile = model.profiles.first(where: { $0.id == id }) else {
            throw CantoCommandError(
                code: "NOT_FOUND", message: "找不到 id=\(id) 的订阅",
                hint: "先调用 app.profile.list 拿最新 id（订阅可能已被删除）")
        }
        if model.isActivationInFlight || model.busyProfileID != nil {
            throw CantoCommandError(
                code: "CONFLICT_BUSY",
                message: "另一个订阅操作正在进行（busy=\(model.busyProfileID ?? "activation")）",
                hint: "等当前切换/同步结束后重试 app.profile.select；可用 app.state.get 观察状态")
        }
        // ← 订阅页同路径：startActivation(stage→reload 单事务) + waitForPendingActivation
        let ok = await model.selectAndWait(profile, force: force)
        guard ok else {
            let reason = model.lastFailure?.errorDescription ?? model.statusMessage.resolved(locale: .current)
            throw CantoCommandError(
                code: "CORE_ERROR",
                message: reason.isEmpty ? "订阅切换失败（id=\(id)）" : reason,
                hint: "在 App 订阅页查看失败详情，修复后可重试 app.profile.select")
        }
        let settled = model.profiles.first { $0.id == id }
        return CantoProfileSelectReceipt(
            id: id, name: settled?.label ?? profile.label,
            appliedToTunnel: model.activationAppliesToTunnel)
    }

    func refreshProfiles(id: String?, waitUpTo seconds: TimeInterval) async throws -> CantoRefreshReceipt {
        ensureLoaded()
        let began = Date()

        guard let id else {
            let wasSyncing = model.isSyncingAll
            model.syncAll()                                 // ← 订阅页“全部更新”同入口
            let started = model.isSyncingAll
            let settled = started ? await waitForQuiescence(seconds: seconds) : true
            let note: String
            if started {
                note = "批量刷新由 App 侧任务执行（每个订阅有独立超时上限）；settled=true 表示已观测到刷新队列空闲，可用 app.profile.list 的 updated_at 复核"
            } else if wasSyncing {
                note = "已有批量刷新在进行，本次未重复启动"
            } else {
                note = "没有可刷新的订阅（或全部无需联网刷新）"
            }
            return CantoRefreshReceipt(scope: "all", id: nil, started: started, settled: settled,
                                        waitedMs: Self.milliseconds(since: began), note: note)
        }

        guard let profile = model.profiles.first(where: { $0.id == id }) else {
            throw CantoCommandError(
                code: "NOT_FOUND", message: "找不到 id=\(id) 的订阅",
                hint: "先调用 app.profile.list 拿最新 id（订阅可能已被删除）")
        }
        if let busy = model.busyProfileID, busy != profile.id {
            throw CantoCommandError(
                code: "CONFLICT_BUSY", message: "另一个订阅正在更新（busy=\(busy)）",
                hint: "等它结束后重试 app.profile.update，或先用 app.state.get 看状态")
        }

        let library = self.library()
        let hasRecipe = library.map { snapshot in
            snapshot.recipes.contains { $0.id == profile.id }
        } ?? false
        let isURLSource: Bool = {
            if case .url = profile.source { return true }
            return false
        }()
        let isActive = profile.id == model.activeProfileID

        model.sync(profile)                                 // ← 订阅行“同步”同入口
        // sync() 的三条分支：配置库配方 / 当前激活订阅 → 同步置忙；legacy URL → 内部任务不置忙。
        let started = hasRecipe || isActive || isURLSource
        let settled = started ? await waitForQuiescence(seconds: seconds) : true
        let note: String
        if !started {
            note = "该订阅没有可联网刷新的来源（本地导入的配置）"
        } else if hasRecipe || isActive {
            note = "刷新由 App 侧任务执行；settled=true 表示已观测到刷新队列空闲，可用 app.profile.list 的 updated_at 复核"
        } else {
            note = "刷新已交给 App 侧任务（legacy URL 分支不置 busyProfileID，settled 仅表示当前无其它队列占用）；请用 app.profile.list 的 updated_at 复核"
        }
        return CantoRefreshReceipt(scope: "id", id: profile.id, started: started, settled: settled,
                                    waitedMs: Self.milliseconds(since: began), note: note)
    }

    func removeProfile(id: String) async throws -> CantoProfileSummary {
        ensureLoaded()
        let library = self.library()
        let activeID = model.activeProfileID
        guard let profile = model.profiles.first(where: { $0.id == id }) else {
            throw CantoCommandError(
                code: "NOT_FOUND", message: "找不到 id=\(id) 的订阅",
                hint: "先调用 app.profile.list 拿最新 id")
        }
        // 与订阅页删除前的同一条策略判定（内置兜底 / 活动订阅需要先切走）。
        guard ProfileCenterPolicy.canDelete(profileID: profile.id, activeProfileID: activeID,
                                            profiles: model.profiles) else {
            let reason = profile.id == LocalDefaultProfileProvisioner.profileID
                ? "内置兜底配置不可删除"
                : "当前正在使用的订阅不能直接删除"
            throw CantoCommandError(
                code: "CONFLICT_BUSY", message: reason,
                hint: "先 app.profile.select 切到其它订阅再删；内置 Direct 配置永远保留")
        }
        if let busy = model.busyProfileID {
            throw CantoCommandError(
                code: "CONFLICT_BUSY", message: "订阅正在更新/切换中（busy=\(busy)）",
                hint: "稍后重试 app.profile.remove")
        }

        let summary = Self.summary(of: profile, library: library, activeID: activeID)
        await model.delete(profile)                         // ← 订阅页删除同入口
        guard !model.profiles.contains(where: { $0.id == id }) else {
            let reason = model.planErrors.first ?? model.statusMessage.resolved(locale: .current)
            throw CantoCommandError(
                code: "CONFLICT_BUSY",
                message: reason.isEmpty ? "订阅删除未完成（App 侧拒绝了该操作）" : reason,
                hint: "在 App 订阅页查看提示；正在使用的订阅需要先切换到其它订阅")
        }
        return summary
    }

    // MARK: 内部小工具（全部沿用 App 既有读取口径）

    /// 首次访问时从磁盘装载订阅列表——与订阅页 onAppear 调用的同一个 `load()`。
    private func ensureLoaded() {
        if model.profiles.isEmpty { model.load() }
    }

    private func library() -> ConfigurationLibrarySnapshot? {
        guard let store = model.configurationLibraryStore else { return nil }
        return try? store.snapshot()
    }

    /// 观测 App 侧刷新队列回到空闲（同步/激活都跑在 MainActor 上，轮询不会读到半状态）。
    private func waitForQuiescence(seconds: TimeInterval) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if Self.isQuiescent(model) { return true }
            do { try await Task.sleep(nanoseconds: 250_000_000) } catch { return Self.isQuiescent(model) }
        }
        return Self.isQuiescent(model)
    }

    private static func isQuiescent(_ model: ProfilesViewModel) -> Bool {
        model.busyProfileID == nil && !model.isSyncingAll && !model.isActivationInFlight
    }

    private static func milliseconds(since date: Date) -> Int {
        max(0, Int(Date().timeIntervalSince(date) * 1000))
    }

    private static func summary(of profile: Profile,
                                library: ConfigurationLibrarySnapshot?,
                                activeID: String?) -> CantoProfileSummary {
        // 与订阅中心同一份事实来源：库记录（ProfileCenterView.libraryFacts）+ profile 自身。
        let facts = library.flatMap { ProfileCenterView.libraryFacts(for: profile, in: $0) }
        let subscription: CantoSubscriptionUsage? =
            facts?.usage.map { Self.usage($0) } ?? profile.subscriptionInfo.map { Self.usage($0) }
        return CantoProfileSummary(
            id: profile.id,
            name: profile.label,
            kind: Self.kind(of: profile.source),
            builtIn: profile.id == LocalDefaultProfileProvisioner.profileID,
            active: profile.id == activeID,
            autoUpdate: profile.autoUpdate,
            updateIntervalHours: profile.updateIntervalHours,
            updatedAt: facts?.lastUpdatedAt ?? profile.lastUpdatedAt,
            nodeCount: library.flatMap { Self.nodeCount(of: profile.id, in: $0) },
            usage: subscription)
    }

    private static func kind(of source: Profile.Source) -> String {
        switch source {
        case .url: return "url"
        case .file: return "file"
        case .clipboard: return "clipboard"
        }
    }

    /// 与 ProfileRowPresentation.note 同一口径：配方 → 各订阅源 nodeCount 之和。
    private static func nodeCount(of profileID: String, in library: ConfigurationLibrarySnapshot) -> Int? {
        guard let recipe = library.recipes.first(where: { $0.id == profileID }) else { return nil }
        return recipe.sources.reduce(0) { total, pin in
            total + (library.sources.first { $0.id == pin.id }?.nodeCount ?? 0)
        }
    }

    private static func usage(_ value: ConfigurationSubscriptionUsage) -> CantoSubscriptionUsage {
        CantoSubscriptionUsage(
            uploadBytes: value.upload, downloadBytes: value.download, totalBytes: value.total,
            expireAt: value.expire > 0 ? Date(timeIntervalSince1970: TimeInterval(value.expire)) : nil)
    }

    private static func usage(_ info: SubscriptionInfo) -> CantoSubscriptionUsage {
        CantoSubscriptionUsage(
            uploadBytes: info.upload, downloadBytes: info.download, totalBytes: info.total,
            expireAt: info.expire > 0 ? Date(timeIntervalSince1970: TimeInterval(info.expire)) : nil)
    }

    /// 与 `Profile.RemoteSource` 相同的可用性判定（http/https + 非空主机）。
    private static func isUsableSubscriptionURL(_ raw: String) -> Bool {
        guard let components = URLComponents(string: raw),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false else { return false }
        return true
    }
}

/// `CantoCoreStatusProviding` → 既有 `ClashCommandClient`（只读 published 快照，不触发任何请求）。
@MainActor
final class CantoCoreStatusAdapter: CantoCoreStatusProviding {

    private let client: ClashCommandClient

    init(client: ClashCommandClient) { self.client = client }

    func coreState() async -> CantoCoreState {
        CantoCoreState(
            connected: client.isConnected,
            tunnelUp: client.tunnelIsUp,
            mode: client.mode,
            coreVersion: client.peerCoreVersion,
            memoryBytes: client.memoryBytes,
            uploadTotalBytes: client.traffic.uploadTotal,
            downloadTotalBytes: client.traffic.downloadTotal)
    }
}
#endif
