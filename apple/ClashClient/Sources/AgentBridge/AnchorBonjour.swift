#if os(iOS) || os(macOS)
import Foundation
import HakoAgentKit
import ClashClientUI
import Network

/// Bonjour/mDNS 发现（Network.framework，iOS 15 / macOS 13 可用面）。
///
/// 契约（与 agent 端 TS 侧对齐——TS 的 Bonjour 广告尚在 P2，落实现时按此为准）：
///   - 服务类型：`_anchor._tcp`（Info.plist 需在 NSBonjourServices 中登记，否则 browse 直接失败）
///   - TXT 键：`id`（16 字符 agent id，= agentIdFromPub(X25519 静态公钥)，同 daemon.ts 的 pair.res.agent.id）
///             `name`（展示名）
///   - TXT 键 `ep`（可选）：完整直连 URL，如 `ws://192.168.1.20:8787/pair`。
///     缺省时本机对 Bonjour SRV 做一次探测（NWConnection → 取解析后的 host:port），
///     组装 `ws://host:port/pair`；探测失败/超时的条目 endpoint 留空，待下次浏览更新重试。
///   - 配对连接使用 `/pair` 路径（daemon 对 /pair 与 /ws 都收 pair.req，但路径分开更清晰）
public final class AnchorBonjourDiscovery: @unchecked Sendable {
    public static let serviceType = "_anchor._tcp"
    public static let pairingPath = "/pair"

    private let queue = DispatchQueue(label: "org.example.hako.anchor.bonjour")
    private let lock = NSLock()

    private var browser: NWBrowser?
    private var continuation: AsyncStream<[AnchorBonjourAgent]>.Continuation?
    private var base: [String: AnchorBonjourAgent] = [:]   // service 名 → TXT 解析出的记录
    private var resolved: [String: String] = [:]           // service 名 → 探测解析出的 endpoint
    private var probes: [String: BonjourProbe] = [:]

    public init() {}

    deinit {
        stop()
    }

    /// 开始浏览；产出的每一帧是"当前全量快照"。
    /// 消费者结束（取消迭代）→ onTermination → 自动 stop()。
    public func makeStream() -> AsyncStream<[AnchorBonjourAgent]> {
        AsyncStream<[AnchorBonjourAgent]> { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
            startBrowser()
        }
    }

    /// 停止浏览并结束流（幂等）。
    public func stop() {
        lock.lock()
        let browser = self.browser
        self.browser = nil
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        browser?.cancel()
        continuation?.finish()
    }

    // MARK: - 浏览器

    private func startBrowser() {
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil),
            using: .tcp
        )
        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                self?.stop()
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.update(results: results)
        }
        lock.lock()
        let active = self.continuation != nil
        if active { self.browser = browser }
        lock.unlock()
        if active {
            browser.start(queue: queue)
        } else {
            browser.cancel()
        }
    }

    private func update(results: Set<NWBrowser.Result>) {
        var next: [String: AnchorBonjourAgent] = [:]
        var toProbe: [(service: String, endpoint: NWEndpoint)] = []
        for result in results {
            guard case let .bonjour(txtRecord) = result.metadata else { continue }
            let service = Self.serviceName(of: result.endpoint)
            let id = txtRecord["id"] ?? service
            let name = txtRecord["name"] ?? service
            let advertised = txtRecord["ep"] ?? txtRecord["endpoint"] ?? ""
            next[service] = AnchorBonjourAgent(id: id, name: name, endpoint: advertised)
            if advertised.isEmpty {
                toProbe.append((service, result.endpoint))
            }
        }

        lock.lock()
        base = next
        let agents = publishLocked()
        let continuation = self.continuation
        lock.unlock()
        continuation?.yield(agents)

        for entry in toProbe {
            startProbe(service: entry.service, endpoint: entry.endpoint)
        }
    }

    private func publishLocked() -> [AnchorBonjourAgent] {
        let records: [AnchorBonjourAgent] = base.map { entry in
            let (service, baseRecord) = entry
            var record = baseRecord
            if record.endpoint.isEmpty, let endpoint = resolved[service] {
                record.endpoint = endpoint
            }
            return record
        }
        return records.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    // MARK: - Bonjour SRV 解析（TXT 未带 ep 时的兜底）

    /// 对已发现服务做一次 TCP 探测，取 NWPath 解析出的 host:port。
    private func startProbe(service: String, endpoint: NWEndpoint) {
        lock.lock()
        let already = resolved[service] != nil || probes[service] != nil
        lock.unlock()
        guard !already else { return }

        let probe = BonjourProbe(queue: queue) { [weak self] url in
            self?.finishProbe(service: service, endpoint: url)
        }
        lock.lock()
        if resolved[service] == nil, probes[service] == nil {
            probes[service] = probe
        } else {
            return lock.unlock()
        }
        lock.unlock()
        probe.start(endpoint: endpoint)
    }

    private func finishProbe(service: String, endpoint: String?) {
        lock.lock()
        probes.removeValue(forKey: service)
        if let endpoint, !endpoint.isEmpty {
            resolved[service] = endpoint
        }
        let agents = publishLocked()
        let continuation = self.continuation
        lock.unlock()
        if let endpoint, !endpoint.isEmpty {
            continuation?.yield(agents)
        }
        // 失败不打搅：留待下一次浏览更新再探测
    }

    // MARK: - 小工具

    private static func serviceName(of endpoint: NWEndpoint) -> String {
        if case let .service(name, _, _, _) = endpoint { return name }
        return String(describing: endpoint)
    }

    fileprivate static func hostText(_ host: NWEndpoint.Host) -> String {
        switch host {
        case let .name(name, _):
            return name
        case let .ipv4(address):
            return "\(address)"
        case let .ipv6(address):
            return "\(address)"
        }
    }

    /// IPv6 字面量需方括号；链路本地地址的 zone（%en0）在 URL 里要转义成 %25。
    fileprivate static func websocketURL(host: String, port: UInt16) -> String? {
        guard !host.isEmpty else { return nil }
        let encodedHost: String
        if host.contains(":") {
            encodedHost = "[" + host.replacingOccurrences(of: "%", with: "%25") + "]"
        } else {
            encodedHost = host
        }
        return "ws://\(encodedHost):\(port)\(pairingPath)"
    }
}

/// 单次 Bonjour SRV 解析探测：NWConnection 连到服务 endpoint，ready 后读解析出的 host:port。
/// 生命周期由 AnchorBonjourDiscovery.probes 字典持有；finish 后被移除并可释放（handler 只持弱引用，不成环）。
private final class BonjourProbe: @unchecked Sendable {
    private let lock = NSLock()
    private let queue: DispatchQueue
    private let completion: @Sendable (String?) -> Void
    private var finished = false
    private var connection: NWConnection?

    init(queue: DispatchQueue, completion: @escaping @Sendable (String?) -> Void) {
        self.queue = queue
        self.completion = completion
    }

    func start(endpoint: NWEndpoint) {
        let connection = NWConnection(to: endpoint, using: .tcp)
        self.connection = connection
        connection.stateUpdateHandler = { [weak self, weak connection] state in
            switch state {
            case .ready:
                var url: String?
                if let remote = connection?.currentPath?.remoteEndpoint,
                   case let .hostPort(host, port) = remote {
                    url = AnchorBonjourDiscovery.websocketURL(
                        host: AnchorBonjourDiscovery.hostText(host),
                        port: port.rawValue
                    )
                }
                self?.finish(url)
            case .failed, .cancelled:
                self?.finish(nil)
            default:
                break
            }
        }
        connection.start(queue: queue)
        queue.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.finish(nil)
        }
    }

    private func finish(_ url: String?) {
        lock.lock()
        let shouldFire = !finished
        finished = true
        let connection = self.connection
        self.connection = nil
        lock.unlock()
        guard shouldFire else { return }
        connection?.cancel()
        completion(url)
    }
}
#endif
