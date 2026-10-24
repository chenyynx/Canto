import Foundation

// AnchorMailboxService — App ↔ EC command transport over the Anchor file domain.
//
// Hard isolation (2026-09-09 rule): this does NOT touch the widget mailbox
// files (`widgets/request.json` etc.) or its Darwin notifications. Anchor
// traffic lives entirely in `anchor/mailbox/`:
//   - app2ec.json   App (or connector, on behalf of agent) → EC commands
//   - ec2app.json   EC replies / events → App
// Every file contains one tagged record (AnchorMailboxCodec). 0600 perms.
// Delivery is poll-based (EC polls every 0.5 s while running; Darwin notify
// would wake the tunnel process needlessly when idle).

#if os(iOS) || os(macOS)
import Clash

final class AnchorMailboxService {
    static let directory = "anchor/mailbox"
    static let app2ecFile = "anchor/mailbox/app2ec.json"
    static let ec2appFile = "anchor/mailbox/ec2app.json"
    static let pollInterval: TimeInterval = 0.5

    private let root: URL
    private let defaults: UserDefaults
    private let queue = DispatchQueue(label: "org.example.hako.anchor.mailbox")
    private var verifier: AnchorMailboxVerifier?
    private var poller: DispatchSourceTimer?
    private weak var control: AnchorAgentControlService?

    /// EC side: poll app2ec.json, execute via AnchorAgentControlService,
    /// write reply to ec2app.json.
    init(root: URL, defaults: UserDefaults, control: AnchorAgentControlService) {
        self.root = root
        self.defaults = defaults
        self.control = control
    }

    func start() {
        queue.async {
            let key = AnchorMailboxKey.loadOrCreate(defaults: self.defaults)
            self.verifier = AnchorMailboxVerifier(key: key)
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now() + Self.pollInterval, repeating: Self.pollInterval)
            timer.setEventHandler { [weak self] in self?.pollOnce() }
            timer.resume()
            self.poller = timer
        }
    }

    func stop() {
        queue.async {
            self.poller?.cancel()
            self.poller = nil
        }
    }

    private func pollOnce() {
        let url = root.appendingPathComponent(Self.app2ecFile)
        guard let wire = try? Data(contentsOf: url) else { return }
        try? FileManager.default.removeItem(at: url) // consume before executing
        guard var verifier else { return }
        guard let message = try? AnchorMailboxCodec.open(wire, key: AnchorMailboxKey.loadOrCreate(defaults: defaults), expect: "app2ec", verifier: &verifier) else {
            ClashLogStore.shared.append("anchor mailbox: rejected unauthenticated message", stream: .app, level: .warning)
            return
        }
        Task { [weak self] in
            guard let self, let control = self.control else { return }
            // Body = one Anchor envelope (cmd, ch=ext) → res envelope JSON.
            let replyEnvelope = await control.handle(rawJSON: message.body)
            guard let replyEnvelope, let replyData = try? JSONEncoder().encode(replyEnvelope) else { return }
            let reply = AnchorMailboxMessage(direction: "ec2app", body: replyData)
            var outVerifier = AnchorMailboxVerifier(key: AnchorMailboxKey.loadOrCreate(defaults: self.defaults))
            if let sealed = try? AnchorMailboxCodec.seal(reply, key: AnchorMailboxKey.loadOrCreate(defaults: self.defaults)) {
                self.write(sealed, to: Self.ec2appFile)
                _ = outVerifier
            }
        }
    }

    private func write(_ data: Data, to relative: String) {
        let url = root.appendingPathComponent(relative)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    // MARK: - App side (send + read replies)

    func send(fromApp body: Data) throws {
        let key = AnchorMailboxKey.loadOrCreate(defaults: defaults)
        let message = AnchorMailboxMessage(direction: "app2ec", body: body)
        let sealed = try AnchorMailboxCodec.seal(message, key: key)
        let url = root.appendingPathComponent(Self.app2ecFile)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try sealed.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func takeReply(defaultsKey key: Data) -> Data? {
        let url = root.appendingPathComponent(Self.ec2appFile)
        guard let wire = try? Data(contentsOf: url) else { return nil }
        try? FileManager.default.removeItem(at: url)
        var verifier = AnchorMailboxVerifier(key: key)
        guard let message = try? AnchorMailboxCodec.open(wire, key: key, expect: "ec2app", verifier: &verifier) else {
            return nil
        }
        return message.body
    }
}
#endif
