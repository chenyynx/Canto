#if os(iOS) || os(macOS)
import Foundation
import Hako
import HakoAgentKit

/// AnchorAgentControlService — Anchor 协议的 EC（Extension 连接器）胶水层。
///
/// 职责（方案 v4 §10.1 / P1）：
///   - 接收 Anchor 信封（cmd, ch=ext），把 `core.*` 命令映射到内核绑定/HakoClashAPI
///   - 复用 `ExtensionProvider.handleMessage` 的现有 cmd 面（不重写任何内核逻辑）
///   - 产出 res 信封（applied / rejected + err.code/hint）
///
/// 内核零改动：全部经现有 Go 绑定全局函数与 provider 消息通道。
/// 行数预算：≤200 行。
final class AnchorAgentControlService {
    private unowned let provider: ExtensionProvider
    private let queue = DispatchQueue(label: "org.example.hako.anchor.ec")
    private var deduper = Deduper()
    private var seq = SeqAllocator()

    /// core.* 命令 → EC 执行器。声明式：加命令 = 加一个 case。
    init(provider: ExtensionProvider) {
        self.provider = provider
    }

    // MARK: - 入口：信封 → res 信封

    /// Mailbox v2 入口：body 是一条已通过 HMAC 校验的 Envelope JSON。
    func handle(rawJSON: Data) async -> Envelope? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: rawJSON) else {
            return nil
        }
        return await handle(envelope: envelope)
    }

    /// 处理一条已解密、已解码的信封（由 AgentBridge 的会话层调用）。
    /// 返回要回发的 res 信封（调用方负责加密回传）。
    func handle(envelope: Envelope) async -> Envelope? {
        guard envelope.t == "cmd", envelope.ch == "ext", let op = envelope.op else {
            return Self.res(for: envelope, ok: false, status: "rejected", err: .init(
                code: "INVALID_ARGUMENT", message: "EC 只接受 ch=ext 的 cmd"))
        }
        // 幂等：同 id/idem 的重放直接忽略（按协议，接收方去重表 256 条/10 分钟）
        let idem = envelope.idem ?? envelope.id
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let duplicate = queue.sync { !deduper.checkAndInsert(envelope.id, now: nowMs, idem: idem) }
        if duplicate {
            return nil // 重放静默丢弃（原 res 已回过）
        }

        let args = envelope.args ?? [:]
        do {
            let data = try await dispatch(op: op, args: args)
            return Self.res(for: envelope, ok: true, status: "applied", data: data)
        } catch let e as CoreError {
            return Self.res(for: envelope, ok: false, status: "rejected", err: e.errorBody)
        } catch {
            return Self.res(for: envelope, ok: false, status: "rejected", err: .init(
                code: "CORE_ERROR", message: String(describing: error).prefix(200).description))
        }
    }

    // MARK: - core.* 分发（13 条，逐条映射现有能力）

    private func dispatch(op: String, args: [String: JSONValue]) async throws -> [String: JSONValue] {
        switch op {
        case "core.state.get":
            return .json(await providerMessageAsync(["cmd": "status"]))
        case "core.proxy.list":
            return .json(await providerMessageAsync(["cmd": "proxies"]))
        case "core.proxy.select":
            guard let group = args["group"]?.stringValue, let name = args["node"]?.stringValue ?? args["proxy"]?.stringValue else {
                throw CoreError(.INVALID_ARGUMENT, "missing group/node", hint: "先 core.proxy.list 拿组名与节点名")
            }
            return .json(Self.providerMessage(["cmd": "select", "group": group, "name": name]))
        case "core.proxy.delay":
            guard let targets = args["targets"], case .array(let list) = targets, let first = list.first?.stringValue else {
                throw CoreError(.INVALID_ARGUMENT, "missing targets[1+]", hint: "targets: [\"节点名\"]")
            }
            let url = args["url"]?.stringValue ?? ""
            let delay = goBind { HakoURLTest(first, url) }
            return ["delays": .object([first: .int(Int64(delay))])]
        case "core.mode.set":
            guard let mode = args["mode"]?.stringValue else {
                throw CoreError(.INVALID_ARGUMENT, "missing mode")
            }
            return .json(Self.providerMessage(["cmd": "setMode", "mode": mode]))
        case "core.conn.list":
            return .json(await providerMessageAsync(["cmd": "connections"]))
        case "core.conn.close":
            guard let id = args["id"]?.stringValue else { throw CoreError(.INVALID_ARGUMENT, "missing id") }
            if args["all"]?.boolValue == true {
                goBindVoid(HakoCloseAllConnections)
                return ["closed": .bool(true)]
            }
            let closed = goBind { HakoCloseConnection(id) }
            return ["closed": .bool(closed)]
        case "core.rules.list":
            return .json(await providerMessageAsync(["cmd": "ruleProviders"]))
        case "core.provider.update":
            // provider 拉取是 App 侧 client 能力；EC 内走 reload 兜底
            return .json(await providerMessageAsync(["cmd": "reload"]))
        case "core.dns.query":
            guard let name = args["name"]?.stringValue else { throw CoreError(.INVALID_ARGUMENT, "missing name") }
            let type = args["type"]?.stringValue ?? "A"
            return .json(goBind { HakoDNSQueryJSON(name, type) })
        case "core.probe":
            return ["version": .string(goBind { HakoVersion() }),
                    "status": .string(await providerMessageAsync(["cmd": "status"]))]
        case "core.log.tail":
            return .json(await providerMessageAsync(["cmd": "logs"]))
        case "core.config.reload":
            return .json(await providerMessageAsync(["cmd": "reload"]))
        default:
            throw CoreError(.UNSUPPORTED, "EC 不支持 \(op)", hint: "core.* 清单见 ops.schema.json")
        }
    }

    // MARK: - 复用通道

    private func providerMessageAsync(_ req: [String: Any]) async -> String {
        let (reply, after) = await provider.handleMessage(Data_tryJSON(req))
        after?()
        return String(decoding: reply, as: UTF8.self)
    }

    // MARK: - res 构造

    private static func res(for cmd: Envelope, ok: Bool, status: String,
                            data: [String: JSONValue]? = nil,
                            err: Envelope.ErrorBody? = nil) -> Envelope {
        var r = Envelope(t: "res", id: AnchorIDs.ulid())
        r.ref = cmd.id
        r.ch = cmd.ch
        r.ok = ok
        r.status = status
        r.data = data
        r.err = err
        return r
    }
}

/// 内核层错误 → 协议错误码
struct CoreError: Error {
    let errorBody: Envelope.ErrorBody
    init(_ code: String, _ message: String, hint: String? = nil, retryable: Bool = false) {
        errorBody = .init(code: code, message: message, retryable: retryable, hint: hint)
    }
}

// MARK: - 小工具

/// Go 绑定是同步阻塞调用（内部连本机 socket）；主线程时丢后台执行防卡顿。
private func goBind<T>(_ body: @escaping () -> T) -> T {
    #if canImport(Darwin)
    if Thread.isMainThread {
        return DispatchQueue.global().sync(execute: body)
    }
    #endif
    return body()
}

private func goBindVoid(_ body: @escaping () -> Void) {
    _ = goBind { body(); return true }
}

extension [String: JSONValue] {
    /// 把 JSON 字符串包成 .object 单字段（EC 返回内核原始 JSON 时用）
    static func json(_ raw: String) -> [String: JSONValue] {
        ["raw": .string(raw)]
    }
}

private func Data_tryJSON(_ obj: [String: Any]) -> Data {
    (try? JSONSerialization.data(withJSONObject: obj)) ?? Data("{}".utf8)
}
#endif
