#if os(iOS) || os(macOS)
import Foundation
import HakoAgentKit
import HakoClientUI
import Security

/// 注意：AnchorIdentityStoring 协议已并入 HakoClientUI 包的 AnchorBridge.swift
/// （与其它 Anchor 契约同模块，UI 可直接绑定；本文件只保留 Keychain 实现）。


/// 身份库错误
public enum AnchorIdentityStoreError: Error, Equatable, Sendable {
    case invalidAgentKeyLength(Int)
    case invalidAgentID(String)
    case invalidEndpoint
    case keychainWriteFailed(account: String, status: Int32)
}

/// Keychain 身份库（kSecClassGenericPassword，service = "org.example.hako.anchor"）。
///
/// 存储布局（account）：
///   - "device.x25519"  ：设备 X25519 静态私钥原文（32B）——跨重装保持同一设备身份
///   - "agent.static"   ：agent X25519 静态公钥原文（32B）
///   - "agent.endpoint" ：agent 直连 endpoint（utf8）
///   - "agent.id"       ：agent 16 字符 id（utf8）
///
/// 全部 kSecAttrAccessibleAfterFirstUnlock（与 CredentialVault 同档：后台唤醒也能读到）。
/// 并发：final + NSLock，@unchecked Sendable（同 AnchorIDs.ULIDMonotonic 的做法）。
public final class AnchorIdentityStore: AnchorIdentityStoring, @unchecked Sendable {
    public static let defaultService = "org.example.hako.anchor"

    private enum Account {
        static let deviceX25519 = "device.x25519"
        static let agentStatic = "agent.static"
        static let agentEndpoint = "agent.endpoint"
        static let agentID = "agent.id"
    }

    private let service: String
    private let lock = NSLock()

    private var cachedDeviceKey: DHKey?
    private var agentLoaded = false
    private var cachedAgentStatic: Data?
    private var cachedAgentEndpoint: String?
    private var cachedAgentID: String?

    public init(service: String = AnchorIdentityStore.defaultService) {
        self.service = service
    }

    // MARK: - 设备身份（读时生成）

    public var deviceStaticKey: DHKey? {
        lock.lock()
        defer { lock.unlock() }
        if let cachedDeviceKey { return cachedDeviceKey }
        // 已有 32B 私钥 → 直接用；否则首次生成并尽量落 Keychain。
        if let raw = read(Account.deviceX25519), raw.count == 32 {
            let key = DHKey.fromRawPrivate(raw)
            cachedDeviceKey = key
            return key
        }
        let fresh = DHKey.generate()
        // Keychain 写失败仍保留内存身份（本次会话可用；下次冷启动会重新生成——
        // 设备 id 必须稳定，故失败时不做任何其它副作用，留给上层日志观察）。
        write(fresh.priv.rawRepresentation, account: Account.deviceX25519)
        cachedDeviceKey = fresh
        return fresh
    }

    public var deviceId: String? {
        guard let key = deviceStaticKey else { return nil }
        return AnchorIDs.deviceIdFromPub(key.pub)
    }

    // MARK: - agent 配对信息

    public var agentStaticKey: Data? {
        lock.lock()
        defer { lock.unlock() }
        loadAgentLocked()
        return cachedAgentStatic
    }

    public var agentEndpoint: String? {
        lock.lock()
        defer { lock.unlock() }
        loadAgentLocked()
        return cachedAgentEndpoint
    }

    public var agentID: String? {
        lock.lock()
        defer { lock.unlock() }
        loadAgentLocked()
        return cachedAgentID
    }

    /// 配对成功后写入 agent 静态公钥 / endpoint / id（三项齐备才算配对完成）。
    public func savePairing(agentID: String, agentStaticKey: Data, agentEndpoint: String) throws {
        guard agentStaticKey.count == 32 else {
            throw AnchorIdentityStoreError.invalidAgentKeyLength(agentStaticKey.count)
        }
        guard AnchorIDs.isAgentId(agentID) else {
            throw AnchorIdentityStoreError.invalidAgentID(agentID)
        }
        guard !agentEndpoint.isEmpty, let endpointData = agentEndpoint.data(using: .utf8) else {
            throw AnchorIdentityStoreError.invalidEndpoint
        }
        guard let idData = agentID.data(using: .utf8) else {
            throw AnchorIdentityStoreError.invalidAgentID(agentID)
        }

        let staticStatus = write(agentStaticKey, account: Account.agentStatic)
        guard staticStatus == errSecSuccess else {
            throw AnchorIdentityStoreError.keychainWriteFailed(account: Account.agentStatic, status: staticStatus)
        }
        let endpointStatus = write(endpointData, account: Account.agentEndpoint)
        guard endpointStatus == errSecSuccess else {
            throw AnchorIdentityStoreError.keychainWriteFailed(account: Account.agentEndpoint, status: endpointStatus)
        }
        let idStatus = write(idData, account: Account.agentID)
        guard idStatus == errSecSuccess else {
            throw AnchorIdentityStoreError.keychainWriteFailed(account: Account.agentID, status: idStatus)
        }

        lock.lock()
        cachedAgentStatic = agentStaticKey
        cachedAgentEndpoint = agentEndpoint
        cachedAgentID = agentID
        agentLoaded = true
        lock.unlock()
    }

    public func forgetPairing() {
        lock.lock()
        defer { lock.unlock() }
        delete(Account.agentStatic)
        delete(Account.agentEndpoint)
        delete(Account.agentID)
        cachedAgentStatic = nil
        cachedAgentEndpoint = nil
        cachedAgentID = nil
        agentLoaded = true
    }

    // MARK: - 懒加载

    private func loadAgentLocked() {
        guard !agentLoaded else { return }
        agentLoaded = true
        let staticKey = read(Account.agentStatic)
        let endpoint = read(Account.agentEndpoint).flatMap { String(data: $0, encoding: .utf8) }
        let id = read(Account.agentID).flatMap { String(data: $0, encoding: .utf8) }
        if staticKey?.count == 32, let endpoint, !endpoint.isEmpty, let id, !id.isEmpty {
            cachedAgentStatic = staticKey
            cachedAgentEndpoint = endpoint
            cachedAgentID = id
            return
        }
        // 半残记录（例如保存中断）：整体清掉，避免 AC 用不完整身份启动。
        if staticKey != nil || endpoint != nil || id != nil {
            delete(Account.agentStatic)
            delete(Account.agentEndpoint)
            delete(Account.agentID)
        }
    }

    // MARK: - Keychain 原语（模式对齐 HakoClientKit.CredentialVault）

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func read(_ account: String) -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var output: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &output)
        guard status == errSecSuccess else { return nil }
        return output as? Data
    }

    @discardableResult
    private func write(_ data: Data, account: String) -> OSStatus {
        let query = baseQuery(account: account)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return status }
        guard status == errSecItemNotFound else { return status }
        var insertion = query
        for (key, value) in attributes { insertion[key] = value }
        status = SecItemAdd(insertion as CFDictionary, nil)
        if status == errSecDuplicateItem {
            status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        }
        return status
    }

    @discardableResult
    private func delete(_ account: String) -> OSStatus {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        return status == errSecItemNotFound ? errSecSuccess : status
    }
}
#endif
