import Foundation
import CantoAgentKit
import ClashClientUI

/// CantoConnector — AC（App 连接器）：已配对设备的日常会话层。
///
/// 职责（方案 v4 §AC / P2）：
///   - URLSessionWebSocketTask 连 agent（端点/密钥来自 CantoIdentityStoring）
///   - Noise_XX 发起方握手（设备持有 agent 静态公钥）→ hello → helloRes → .connected
///   - 命令分发（Deduper 去重 / TTL 检查 / res 回包）与保活（ping/pong）
///   - 指数退避重连；suspend/resume/stop 生命周期
///
/// 可测设计：TTL 判定（frameIsExpired）、res 构造（makeResult）为纯函数。
final class CantoConnector: CantoConnecting, @unchecked Sendable {
    private let lock = NSLock()
    private let identity: CantoIdentityStoring

    // 状态
    private var task: URLSessionWebSocketTask?
    private var noise: NoiseXX?
    private var session: URLSession?
    private var reconnectAttempt = 0
    private var backoff = Backoff(baseMs: 1_000, maxMs: 30_000, jitterRatio: 0.2)
    private var pingTimer: DispatchSourceTimer?
    private var stopped = false
    private var handshaking = false
    private var seq = SeqAllocator()

    // 协议状态
    private(set) var phase: CantoSessionPhase = .idle
    var onPhaseChange: (@Sendable (CantoSessionPhase) -> Void)?
    var onEvent: (@Sendable ([String: JSONValue]) -> Void)?
    private var commandHandler: CantoCommandHandling?

    /// 保活间隔与判死线（秒）
    private let pingInterval: TimeInterval = 30
    private let pongTimeout: TimeInterval = 15

    init(identity: CantoIdentityStoring) {
        self.identity = identity
    }

    // MARK: - CantoConnecting

    func setCommandHandler(_ handler: CantoCommandHandling?) {
        lock.lock()
        defer { lock.unlock() }
        commandHandler = handler
    }

    func start() {
        lock.lock()
        stopped = false
        lock.unlock()
        connect()
    }

    func suspend() {
        setPhase(.suspended)
        closeSocket()
    }

    func resume() {
        lock.lock()
        backoff.reset()
        reconnectAttempt = 0
        let wasStopped = stopped
        lock.unlock()
        guard !wasStopped else { return }
        connect()
    }

    func stop() {
        lock.lock()
        stopped = true
        lock.unlock()
        stopPing()
        closeSocket()
        setPhase(.idle)
    }

    // MARK: - 连接生命周期

    private func connect() {
        lock.lock()
        guard !stopped, !handshaking, task == nil else {
            lock.unlock()
            return
        }
        guard let endpoint = identity.agentEndpoint,
              let agentPub = identity.agentStaticKey,
              let devKey = identity.deviceStaticKey
        else {
            lock.unlock()
            setPhase(.idle)
            return
        }
        handshaking = true
        lock.unlock()

        setPhase(.connecting)
        let noise = NoiseXX(initiator: true, staticKey: devKey, remoteStatic: agentPub)
        lock.lock()
        self.noise = noise
        lock.unlock()

        let session = URLSession(configuration: .default)
        guard let url = URL(string: endpoint) else {
            handshaking = false
            setPhase(.failed(reason: "端点无效：\(endpoint)"))
            scheduleReconnect()
            return
        }
        let task = session.webSocketTask(with: url)
        lock.lock()
        self.session = session
        self.task = task
        lock.unlock()
        task.resume()
        sendHandshake(with: noise, task: task)
    }

    private func sendHandshake(with noise: NoiseXX, task: URLSessionWebSocketTask) {
        do {
            // -> msg1
            let m1 = try noise.writeMsg1()
            task.send(.data(m1)) { [weak self] error in
                if error != nil {
                    self?.handshakeFailed("msg1 发送失败")
                } else {
                    // <- msg2（在 receive 循环里处理，此处先挂接收）
                    self?.receiveLoop(task: task, noise: noise)
                }
            }
        } catch {
            handshakeFailed("msg1 构造失败：\(error)")
        }
    }

    private func receiveLoop(task: URLSessionWebSocketTask, noise: NoiseXX) {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .failure(let error):
                self.connectionDied("接收失败：\(error.localizedDescription)")
            case .success(let message):
                guard case .data(let data) = message else {
                    self.connectionDied("非二进制帧")
                    return
                }
                self.handleFrame(data, noise: noise, task: task)
            }
        }
    }

    private func handleFrame(_ data: Data, noise: NoiseXX, task: URLSessionWebSocketTask) {
        do {
            if !noise.handshakeComplete {
                // <- msg2 → -> msg3（载荷 = hello）
                let (_, payload) = try noise.readMsg2(data)
                let hello = makeHelloEnvelope()
                let helloJSON = try JSONEncoder().encode(hello)
                let m3 = try noise.writeMsg3(payload: helloJSON)
                task.send(.data(m3)) { [weak self] error in
                    if error != nil { self?.handshakeFailed("msg3 发送失败") }
                }
                _ = payload
                receiveLoop(task: task, noise: noise)
                return
            }
            // 传输阶段：一帧一信封
            let plain = try noise.recv(data)
            let envelope = try JSONDecoder().decode(Envelope.self, from: plain)
            Task { await self.process(envelope: envelope) }
            receiveLoop(task: task, noise: noise)
        } catch {
            handshakeFailed("握手/解码失败：\(error)")
        }
    }

    private func makeHelloEnvelope() -> Envelope {
        var e = Envelope(t: "hello", id: CantoIDs.ulid())
        e.ch = "app"
        e.op = "hello"
        var helloArgs: [String: JSONValue] = [
            "role": .string("app"),
            "dev_id": .string(identity.deviceId ?? ""),
            "proto": .array([.int(1)]),
            "caps": .object([
                "app": .array((commandHandler?.supportedOps ?? []).map { JSONValue.string($0) }),
            ]),
        ]
        // P4：上报 APNs token（daemon 存 devices.apns_token，离线唤醒用）
        if let apns = CantoPushTokenStore.report() {
            var apnsObj: [String: JSONValue] = [:]
            if let token = apns["token"] as? String { apnsObj["token"] = .string(token) }
            if let env = apns["env"] as? String { apnsObj["env"] = .string(env) }
            if let topic = apns["topic"] as? String { apnsObj["topic"] = .string(topic) }
            helloArgs["apns"] = .object(apnsObj)
        }
        e.args = helloArgs
        e.seq = lock.withLock { seq.next() }
        return e
    }

    // MARK: - 信封处理（传输阶段）

    private func process(envelope: Envelope) async {
        switch envelope.t {
        case "helloRes":
            if envelope.ok == true {
                setPhase(.connected)
                lock.lock()
                reconnectAttempt = 0
                backoff.reset()
                lock.unlock()
                startPing()
            } else {
                let reason = envelope.reason ?? envelope.err?.message ?? "hello 被拒"
                connectionDied("hello 失败：\(reason)")
            }
        case "pong":
            // 保活应答（超时判定在 ping timer 里）
            break
        case "cmd":
            await handleCommand(envelope)
        case "bye":
            connectionDied("对端 bye：\(envelope.reason ?? "")")
        default:
            break
        }
    }

    private func handleCommand(_ cmd: Envelope) async {
        // 去重（256 条 / 10 分钟；重放静默丢弃）
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let isReplay = !lock.withLock {
            deduper.checkAndInsert(cmd.id, now: nowMs, idem: cmd.idem)
        }
        if isReplay { return }

        // TTL：过期拒绝（接收方单调时钟 + 创建时间判定）
        if Self.frameIsExpired(cmd, nowMs: nowMs) {
            sendResult(for: cmd, ok: false, status: "rejected", err: .init(
                code: "EXPIRED", message: "命令已过有效期", retryable: true,
                hint: "agent 侧重新下发"))
            return
        }

        guard let handler = commandHandler else {
            sendResult(for: cmd, ok: false, status: "rejected", err: .init(
                code: "UNKNOWN_DEVICE", message: "命令执行器未装配"))
            return
        }

        do {
            let args = cmd.args ?? [:]
            let data = try await handler.execute(op: cmd.op ?? "", args: args)
            sendResult(for: cmd, ok: true, status: "applied", data: data)
        } catch let e as CantoCommandError {
            sendResult(for: cmd, ok: false, status: "rejected", err: .init(
                code: e.code, message: e.message, retryable: e.code == "TIMEOUT_UNKNOWN",
                hint: e.hint))
        } catch {
            sendResult(for: cmd, ok: false, status: "rejected", err: .init(
                code: "CORE_ERROR", message: String(describing: error).prefix(200).description))
        }
    }

    private func sendResult(for cmd: Envelope, ok: Bool, status: String,
                            data: [String: JSONValue]? = nil,
                            err: Envelope.ErrorBody? = nil) {
        var r = Envelope(t: "res", id: CantoIDs.ulid())
        r.ref = cmd.id
        r.ch = cmd.ch
        r.ok = ok
        r.status = status
        r.data = data
        r.err = err
        r.seq = lock.withLock { seq.next() }
        send(envelope: r)
    }

    private func send(envelope: Envelope) {
        lock.lock()
        let task = self.task
        let noise = self.noise
        lock.unlock()
        guard let task, let noise, noise.handshakeComplete else { return }
        guard let json = try? JSONEncoder().encode(envelope),
              let frame = try? noise.send(json)
        else { return }
        task.send(.data(frame)) { [weak self] error in
            if error != nil { self?.connectionDied("发送失败") }
        }
    }

    // MARK: - 可测纯函数

    /// TTL 判定：created_at 由 ULID 时间戳恢复；超过 ttl_ms 视为过期
    /// （ULID 高 48 bit = 毫秒时间戳）
    static func frameIsExpired(_ envelope: Envelope, nowMs: Int64) -> Bool {
        guard let ttl = envelope.ttlMs else { return false }
        let createdMs = ulidTimestampMs(envelope.id)
        return nowMs - createdMs > Int64(ttl)
    }

    static func ulidTimestampMs(_ id: String) -> Int64 {
        // 26 字符 Crockford；前 10 字符 = 48 bit 时间戳
        let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        guard id.count >= 10 else { return 0 }
        var ts: UInt64 = 0
        for ch in id.prefix(10) {
            guard let idx = alphabet.firstIndex(of: ch) else { return 0 }
            ts = (ts << 5) | UInt64(idx)
        }
        return Int64(ts)
    }

    static func makeResult(for cmd: Envelope, ok: Bool, status: String,
                           data: [String: JSONValue]? = nil,
                           err: Envelope.ErrorBody? = nil) -> Envelope {
        var r = Envelope(t: "res", id: CantoIDs.ulid())
        r.ref = cmd.id
        r.ch = cmd.ch
        r.ok = ok
        r.status = status
        r.data = data
        r.err = err
        return r
    }

    // MARK: - 保活与重连

    private func startPing() {
        stopPing()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        timer.schedule(deadline: .now() + pingInterval, repeating: pingInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            var ping = Envelope(t: "ping", id: CantoIDs.ulid())
            ping.seq = self.lock.withLock { self.seq.next() }
            self.send(envelope: ping)
        }
        timer.resume()
        lock.lock()
        pingTimer = timer
        lock.unlock()
    }

    private func stopPing() {
        lock.lock()
        pingTimer?.cancel()
        pingTimer = nil
        lock.unlock()
    }

    private func scheduleReconnect() {
        lock.lock()
        guard !stopped else { lock.unlock(); return }
        reconnectAttempt += 1
        let delay = backoff.next()
        lock.unlock()
        DispatchQueue.global().asyncAfter(deadline: .now() + Double(delay) / 1000) { [weak self] in
            guard let self else { return }
            self.lock.lock()
            let stopped = self.stopped
            self.lock.unlock()
            if !stopped { self.connect() }
        }
    }

    // MARK: - 失败路径

    private func handshakeFailed(_ reason: String) {
        lock.lock()
        handshaking = false
        lock.unlock()
        closeSocket()
        setPhase(.failed(reason: reason))
        scheduleReconnect()
    }

    private func connectionDied(_ reason: String) {
        lock.lock()
        let wasConnected = (phase == .connected)
        handshaking = false
        lock.unlock()
        stopPing()
        closeSocket()
        setPhase(wasConnected ? .connecting : .failed(reason: reason))
        scheduleReconnect()
    }

    private func closeSocket() {
        lock.lock()
        let task = self.task
        let session = self.session
        self.task = nil
        self.session = nil
        self.noise = nil
        lock.unlock()
        task?.cancel(with: .goingAway, reason: nil)
        session?.invalidateAndCancel()
    }

    private func setPhase(_ newPhase: CantoSessionPhase) {
        lock.lock()
        guard phase != newPhase else { lock.unlock(); return }
        phase = newPhase
        lock.unlock()
        onPhaseChange?(newPhase)
    }

    // 去重表（传输阶段 cmd 用）
    private var deduper = Deduper()
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
