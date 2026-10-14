import Foundation

// P3: agent-side configuration management with safe apply/confirm/rollback.
//
// Overlay strategy: agent patches land in the same OverrideSpec store the app
// itself uses for runtime overrides (GlobalConfig, app group defaults key
// "config.runtime.flclash.v1"). No core changes; activation pipeline applies
// the overlay exactly as user-made overrides are applied.
//
// Safety model:
//  - patch/apply are two steps: `app.config.patch` stages a patch (returns a
//    preview + new rev, does NOT persist), `app.config.apply` persists it,
//    reloads, and starts a confirm window.
//  - If the agent does not confirm within `confirm_within_s` (default 60s),
//    or the bridge loses connectivity while unconfirmed, the previous
//    confirmed snapshot is restored automatically (anti-lockout).
//  - The agent endpoint direct rule is always forced to the top of the rules
//    list in every applied patch; patches cannot remove or deprioritize it.

struct AnchorConfigSnapshot: Codable, Equatable {
    var rev: Int
    var patchJSON: String
    var savedAt: Date

    /// 手写编解码（自定义 computed `data` 会遮蔽 Codable 合成成员）。
    enum CodingKeys: String, CodingKey { case rev, patchJSON, savedAt }

    var data: Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try? encoder.encode(self)
    }

    static func decode(_ data: Data) -> AnchorConfigSnapshot? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(AnchorConfigSnapshot.self, from: data)
    }
}

enum AnchorConfigError: Error, LocalizedError {
    case staleRev(expected: Int, got: Int)
    case invalidPatch(String)
    case applyInFlight
    case nothingToConfirm
    case nothingToRollback
    case endpointRuleMissing

    var errorDescription: String? {
        switch self {
        case .staleRev(let expected, let got):
            return "rev 冲突：当前 \(expected)，请求基于 \(got)。请先 app.config.get 再重试"
        case .invalidPatch(let why): return "patch 无效：\(why)"
        case .applyInFlight: return "已有一次 apply 在确认窗口内，先 confirm 或等回滚"
        case .nothingToConfirm: return "没有待确认的 apply"
        case .nothingToRollback: return "没有可回滚的历史"
        case .endpointRuleMissing: return "patch 试图移除 agent 直连规则，已拒绝（防自锁）"
        }
    }
}

/// Persists confirm-window state across relaunches (unconfirmed apply must
/// roll back even if the app is killed mid-window).
struct AnchorPendingApply: Codable, Equatable {
    // 全部存储属性 Codable 可合成；此前不合成是因 AnchorConfigSnapshot 未 Codable
    var rev: Int
    var previous: AnchorConfigSnapshot
    var appliedAt: Date
    var confirmWithinS: Int
}

protocol AnchorConfigStoring {
    func loadSnapshot() -> AnchorConfigSnapshot?
    func saveSnapshot(_ snapshot: AnchorConfigSnapshot)
    func loadPending() -> AnchorPendingApply?
    func savePending(_ pending: AnchorPendingApply?)
    func appendActivity(_ entry: AnchorConfigActivity)
    func loadActivity() -> [AnchorConfigActivity]
}

struct AnchorConfigActivity: Codable, Equatable {
    var id: String
    var at: Date
    var op: String
    var rev: Int?
    var detail: String
    var undone: Bool
}

/// Store rooted in the Anchor app-group directory. File-backed so it survives
/// relaunch and is readable by both App and Extension sides.
struct AnchorConfigStore: AnchorConfigStoring {
    let root: URL
    private let queue = DispatchQueue(label: "anchor.config.store")

    static func defaultStore() -> AnchorConfigStore? {
        guard let root = HakoAppIdentifiers.appGroupContainer?.appendingPathComponent("anchor/config", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return AnchorConfigStore(root: root)
    }

    private var snapshotURL: URL { root.appendingPathComponent("snapshot.json") }
    private var pendingURL: URL { root.appendingPathComponent("pending.json") }
    private var activityURL: URL { root.appendingPathComponent("activity.json") }

    func loadSnapshot() -> AnchorConfigSnapshot? {
        guard let data = try? Data(contentsOf: snapshotURL) else { return nil }
        return AnchorConfigSnapshot.decode(data)
    }

    func saveSnapshot(_ snapshot: AnchorConfigSnapshot) {
        if let data = snapshot.data {
            try? data.write(to: snapshotURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: snapshotURL.path)
        }
    }

    func loadPending() -> AnchorPendingApply? {
        guard let data = try? Data(contentsOf: pendingURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(AnchorPendingApply.self, from: data)
    }

    func savePending(_ pending: AnchorPendingApply?) {
        guard let pending else {
            try? FileManager.default.removeItem(at: pendingURL)
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(pending) {
            try? data.write(to: pendingURL, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: pendingURL.path)
        }
    }

    func appendActivity(_ entry: AnchorConfigActivity) {
        queue.sync {
            var entries = loadActivity()
            entries.insert(entry, at: 0)
            if entries.count > 100 { entries = Array(entries.prefix(100)) }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .secondsSince1970
            encoder.outputFormatting = [.sortedKeys]
            if let data = try? encoder.encode(entries) {
                try? data.write(to: activityURL, options: .atomic)
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: activityURL.path)
            }
        }
    }

    func loadActivity() -> [AnchorConfigActivity] {
        guard let data = try? Data(contentsOf: activityURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return (try? decoder.decode([AnchorConfigActivity].self, from: data)) ?? []
    }
}

/// Core P3 logic. Pure state transitions + persistence; connectivity checks
/// are injected via `liveness` so this file stays unit-testable.
final class AnchorConfigManager {
    static let endpointRuleKey = "anchor.agent.direct"
    /// The immutable top rule: agent endpoint must always go direct, or the
    /// agent locks itself (and the user) out.
    static let agentDirectRule = "IP-CIDR,0.0.0.0/0,DIRECT,no-resolve"

    private let store: AnchorConfigStoring
    private let defaults: UserDefaults
    private let configKey: String
    /// Returns true when the tunnel/core is healthy enough to keep a new
    /// config alive (bridge still reachable counts as healthy).
    private let liveness: () async -> Bool

    private var confirmTask: Task<Void, Never>?

    init(
        store: AnchorConfigStoring,
        defaults: UserDefaults,
        configKey: String = "config.runtime.flclash.v1",
        liveness: @escaping () async -> Bool = { true }
    ) {
        self.store = store
        self.defaults = defaults
        self.configKey = configKey
        self.liveness = liveness
        // Crash recovery: an unconfirmed apply from a previous run rolls back.
        recoverPendingOnLaunch()
    }

    deinit { confirmTask?.cancel() }

    // MARK: - Reading

    func currentSnapshot() -> AnchorConfigSnapshot {
        store.loadSnapshot() ?? AnchorConfigSnapshot(rev: 0, patchJSON: currentPatchJSON(), savedAt: Date())
    }

    func currentPatchJSON() -> String {
        guard let data = defaults.data(forKey: configKey),
              let record = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let patch = record["patchJSON"] as? String else { return "" }
        return patch
    }

    // MARK: - patch (stage, no persistence)

    /// Validates and stages a patch against `base_rev`. Returns the merged
    /// preview JSON (agent rules pinned on top) without touching storage.
    func stage(baseRev: Int, patch: [String: Any]) throws -> (rev: Int, mergedJSON: String) {
        guard !(store.loadPending() != nil) else { throw AnchorConfigError.applyInFlight }
        let current = currentSnapshot()
        guard baseRev == current.rev else { throw AnchorConfigError.staleRev(expected: current.rev, got: baseRev) }

        // Validate patch shape: must be a JSON object; rules must not drop the
        // agent direct rule when present.
        if let rules = patch["rules"] as? [String] {
            guard rules.contains(where: { $0.contains(Self.endpointRuleKey) }) else {
                throw AnchorConfigError.endpointRuleMissing
            }
        }

        let merged = try Self.merge(base: currentPatchJSON(), patch: patch)
        return (rev: current.rev + 1, mergedJSON: merged)
    }

    // MARK: - apply (persist + confirm window)

    /// Persists the merged patch, triggers reload via the supplied hook, and
    /// starts the confirm countdown. Automatic rollback on timeout or lost
    /// liveness.
    func apply(
        rev: Int,
        mergedJSON: String,
        confirmWithinS: Int = 60,
        reload: @escaping () async -> Void
    ) async throws -> AnchorConfigSnapshot {
        guard store.loadPending() == nil else { throw AnchorConfigError.applyInFlight }
        let previous = currentSnapshot()
        guard rev == previous.rev + 1 else { throw AnchorConfigError.staleRev(expected: previous.rev + 1, got: rev) }

        let next = AnchorConfigSnapshot(rev: rev, patchJSON: mergedJSON, savedAt: Date())
        writePatch(mergedJSON)
        store.saveSnapshot(next)
        let pending = AnchorPendingApply(rev: rev, previous: previous, appliedAt: Date(), confirmWithinS: confirmWithinS)
        store.savePending(pending)
        store.appendActivity(AnchorConfigActivity(
            id: UUID().uuidString, at: Date(), op: "apply", rev: rev,
            detail: "applied rev \(rev) (\(mergedJSON.utf8.count) bytes), confirm within \(confirmWithinS)s", undone: false
        ))

        await reload()
        startConfirmWindow(pending: pending, reload: reload)
        return next
    }

    // MARK: - confirm / rollback

    func confirm(rev: Int, reload: @escaping () async -> Void) async throws {
        guard let pending = store.loadPending() else { throw AnchorConfigError.nothingToConfirm }
        guard pending.rev == rev else { throw AnchorConfigError.staleRev(expected: pending.rev, got: rev) }
        confirmTask?.cancel()
        store.savePending(nil)
        store.appendActivity(AnchorConfigActivity(
            id: UUID().uuidString, at: Date(), op: "confirm", rev: rev, detail: "rev \(rev) confirmed", undone: false
        ))
        _ = reload // no-op; config already live
    }

    func rollback(rev: Int? = nil, reload: @escaping () async -> Void) async throws -> AnchorConfigSnapshot {
        let target: AnchorConfigSnapshot
        if let pending = store.loadPending(), rev == nil || rev == pending.rev {
            target = pending.previous
        } else if let snap = store.loadSnapshot(), rev == nil || snap.rev > (rev ?? 0) {
            // Manual rollback to last confirmed state.
            target = snap
        } else {
            throw AnchorConfigError.nothingToRollback
        }
        confirmTask?.cancel()
        writePatch(target.patchJSON)
        let restored = AnchorConfigSnapshot(rev: target.rev, patchJSON: target.patchJSON, savedAt: Date())
        store.saveSnapshot(restored)
        store.savePending(nil)
        store.appendActivity(AnchorConfigActivity(
            id: UUID().uuidString, at: Date(), op: "rollback", rev: target.rev,
            detail: "rolled back to rev \(target.rev)", undone: false
        ))
        await reload()
        return restored
    }

    // MARK: - undo (one-tap, UI side)

    /// Undoes the most recent unconfirmed apply. Confirmed applies are part
    /// of the confirmed history and are reverted by an explicit
    /// app.config.rollback from the agent instead.
    func undoLast() async throws -> AnchorConfigSnapshot {
        guard let pending = store.loadPending() else {
            throw AnchorConfigError.nothingToRollback
        }
        return try await rollback(rev: pending.rev, reload: {})
    }

    // MARK: - pending recovery

    /// Called at launch and after reconnect: anything unconfirmed past its
    /// window rolls back immediately.
    func recoverPendingOnLaunch() {
        guard let pending = store.loadPending() else { return }
        let deadline = pending.appliedAt.addingTimeInterval(TimeInterval(pending.confirmWithinS))
        if Date() >= deadline {
            Task { try? await rollback(rev: pending.rev, reload: {}) }
        } else {
            startConfirmWindow(pending: pending, reload: {})
        }
    }

    /// Bridge-side hook: call when connectivity drops while unconfirmed.
    func handleConnectivityLost() {
        guard store.loadPending() != nil else { return }
        Task { try? await rollback(rev: nil, reload: {}) }
    }

    // MARK: - internals

    private func startConfirmWindow(pending: AnchorPendingApply, reload: @escaping () async -> Void) {
        confirmTask?.cancel()
        confirmTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(pending.confirmWithinS) * 1_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard let still = self.store.loadPending(), still.rev == pending.rev else { return }
            let healthy = await self.liveness()
            if !healthy {
                try? await self.rollback(rev: pending.rev, reload: reload)
            } else {
                // Healthy but never confirmed: still roll back (agent must
                // explicitly confirm; silence = not trusted).
                try? await self.rollback(rev: pending.rev, reload: reload)
            }
        }
    }

    private func writePatch(_ json: String) {
        let record: [String: Any] = ["patchJSON": json]
        if let data = try? JSONSerialization.data(withJSONObject: record) {
            defaults.set(data, forKey: configKey)
        }
    }

    /// JSON-object merge: patch keys overwrite base keys; rules arrays get the
    /// agent direct rule pinned at index 0.
    static func merge(base: String, patch: [String: Any]) throws -> String {
        var merged: [String: Any] = [:]
        if !base.isEmpty,
           let parsed = try? JSONSerialization.jsonObject(with: Data(base.utf8)) as? [String: Any] {
            merged = parsed
        }
        for (k, v) in patch {
            if k == "rules", let incoming = v as? [String] {
                var rules = incoming.filter { !$0.contains(endpointRuleKey) }
                rules.insert(agentDirectRule, at: 0)
                merged[k] = rules
            } else {
                merged[k] = v
            }
        }
        if merged["rules"] != nil {
            var rules = merged["rules"] as? [String] ?? []
            rules.removeAll { $0.contains(endpointRuleKey) }
            rules.insert(agentDirectRule, at: 0)
            merged["rules"] = rules
        }
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }
}

extension AnchorConfigActivity {
    mutating func markUndone() { undone = true }
}
