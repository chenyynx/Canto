#if os(iOS) || os(macOS)
import Foundation
import CryptoKit
import HakoAgentKit
#if os(iOS)
import UIKit
#endif
import ClashClientUI
#if canImport(UIKit)
import UIKit
#endif

/// AnchorPairingService — 配对流程主体（粘贴口令 / Bonjour 两路）。
///
/// 流程（方案 v4 §配对）：
///   1. PairingURI.parse → k（agent 公钥）/ s（口令）/ endpoints
///   2. Noise_XX 发起方握手（设备持有 agent 静态公钥）
///   3. msg3 载荷 = pair.req（QR 路径带 secret；Bonjour 路径无 secret）
///   4. 收 pair.res → accepted 时写入身份库 → 日常会话由 AnchorConnector 接管
///
/// SAS 确认码（Bonjour 路径）：SHA256(agentPub || devPub) hex 前 12 位 mod 1e6。
/// **该算式须与 anchor TS 侧一致**（daemon.ts #onPairReq 同式）。
final class AnchorPairingService: AnchorPairingServiceProtocol, @unchecked Sendable {
    private let identity: AnchorIdentityStore
    private let bonjour = AnchorBonjourDiscovery()
    private let lock = NSLock()

    init(identity: AnchorIdentityStore) {
        self.identity = identity
    }

    // MARK: - 粘贴口令路径

    func pair(withURI uri: String) async throws -> PairingResult {
        let parsed = try PairingURI.parse(uri)
        guard let agentPub = Data(base64urlEncoded: parsed.k), agentPub.count == 32 else {
            throw AnchorPairingFlowError.invalidAgentKey
        }
        guard let endpoint = parsed.endpoints.first else {
            throw AnchorPairingFlowError.noEndpoint
        }
        return try await runPairing(
            endpoint: endpoint,
            agentPub: agentPub,
            includeSecret: parsed.secret,
            sasCode: nil
        )
    }

    // MARK: - Bonjour 路径

    func discoverAgents() -> AsyncStream<[AnchorBonjourAgent]> {
        bonjour.makeStream()
    }

    func pair(bonjour agent: AnchorBonjourAgent, sasConfirmed: @Sendable () async -> Bool) async throws -> PairingResult {
        // Bonjour 路径（trust-on-first-use）：
        //   1) 先连 endpoint 完成 msg1/msg2 —— 从 readMsg2 得到 agent 公钥
        //   2) 用公钥算 SAS 交 UI 人眼比对
        //   3) 用户确认后发 pair.req（无 secret，带 sas）
        guard let devKey = identity.deviceStaticKey else {
            throw AnchorPairingFlowError.missingDeviceKey
        }
        guard let url = URL(string: agent.endpoint) else {
            throw AnchorPairingFlowError.invalidEndpoint
        }
        let noise = NoiseXX(initiator: true, staticKey: devKey)
        let session = URLSession(configuration: .default)
        defer { session.invalidateAndCancel() }
        let ws = session.webSocketTask(with: url)
        ws.resume()
        try await ws.send(.data(try noise.writeMsg1()))
        let agentPub = try noise.readMsg2(try await receiveBinary(ws)).rs
        ws.cancel(with: .goingAway, reason: nil)

        let sas = Self.sasCode(agentPub: agentPub, devPub: devKey.pub)
        guard await sasConfirmed() else {
            throw AnchorPairingFlowError.userCancelled
        }
        return try await runPairing(
            endpoint: agent.endpoint,
            agentPub: agentPub,
            includeSecret: nil,
            sasCode: sas
        )
    }

    var agentFingerprint: String {
        guard let pub = identity.agentStaticKey else { return "-" }
        return Self.fingerprint(pub)
    }

    // MARK: - 握手与 pair.req/res

    private func runPairing(endpoint: String, agentPub: Data,
                            includeSecret: String?, sasCode: String?) async throws -> PairingResult {
        guard let devKey = identity.deviceStaticKey else {
            throw AnchorPairingFlowError.missingDeviceKey
        }
        guard let url = URL(string: endpoint) else {
            throw AnchorPairingFlowError.invalidEndpoint
        }

        let noise = NoiseXX(initiator: true, staticKey: devKey, remoteStatic: agentPub)
        let session = URLSession(configuration: .default)
        defer { session.invalidateAndCancel() }
        let ws = session.webSocketTask(with: url)
        ws.resume()

        // -> msg1
        let m1 = try noise.writeMsg1()
        try await ws.send(.data(m1))
        // <- msg2
        let m2 = try await receiveBinary(ws)
        _ = try noise.readMsg2(m2)
        // -> msg3（载荷 = pair.req）
        let deviceName = Self.localDeviceName()
        var device: [String: JSONValue] = [
            "id": .string(AnchorIDs.deviceIdFromPub(devKey.pub)),
            "name": .string(deviceName),
            "os": .string(Self.osName()),
        ]
        var req: [String: JSONValue] = [
            "t": .string("pair.req"),
            "device": .object(device),
            "roles": .array([.string("app")]),
            "caps": .object(["app": .array([])]),
        ]
        if let secret = includeSecret {
            req["secret"] = .string(secret)
        }
        if let sas = sasCode {
            req["sas"] = .string(sas)
        }
        _ = device
        let m3 = try noise.writeMsg3(payload: try JSONEncoder().encode(req))
        try await ws.send(.data(m3))

        // <- 传输帧 = pair.res
        let frame = try await receiveBinary(ws)
        let resJSON = try noise.recv(frame)
        let res = try JSONDecoder().decode([String: JSONValue].self, from: resJSON)

        let status = res["status"]?.stringValue ?? ""
        guard status == "accepted" else {
            return PairingResult(
                accepted: false,
                controller: false,
                scopes: res["scopes"]?.stringValue ?? "operate",
                agentName: res["device_alias"]?.stringValue
            )
        }

        let agentID = (res["agent"]?.objectValue?["id"]?.stringValue)
            ?? AnchorIDs.agentIdFromPub(agentPub)
        try identity.savePairing(
            agentID: agentID,
            agentStaticKey: agentPub,
            agentEndpoint: endpoint
        )
        return PairingResult(
            accepted: true,
            controller: res["controller"]?.boolValue ?? false,
            scopes: res["scopes"]?.stringValue ?? "manage",
            agentName: res["device_alias"]?.stringValue
        )
    }

    // MARK: - 工具

    private func receiveBinary(_ ws: URLSessionWebSocketTask) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            ws.receive { result in
                switch result {
                case .success(let msg):
                    guard case .data(let data) = msg else {
                        cont.resume(throwing: AnchorPairingFlowError.notBinaryFrame)
                        return
                    }
                    cont.resume(returning: data)
                case .failure(let error):
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// SAS 码：SHA256(agentPub || devPub) hex 前 12 位 mod 1e6（与 TS daemon 同式）
    static func sasCode(agentPub: Data, devPub: Data) -> String {
        var data = agentPub
        data.append(devPub)
        let digest = CryptoSHA256(data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        let value = UInt64(hex.prefix(12), radix: 16) ?? 0
        return String(value % 1_000_000).padding(toLength: 6, withPad: "0", startingAt: 0)
    }

    static func fingerprint(_ pub: Data) -> String {
        let digest = CryptoSHA256(pub)
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    private static func localDeviceName() -> String {
        #if canImport(UIKit)
        UIDevice.current.name
        #elseif os(macOS)
        Host.current().localizedName ?? "Mac"
        #else
        "Clash Device"
        #endif
    }

    private static func osName() -> String {
        #if os(iOS)
        "iOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #elseif os(macOS)
        "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        #else
        ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
}

public enum AnchorPairingFlowError: Error, Equatable {
    case invalidAgentKey
    case noEndpoint
    case missingDeviceKey
    case invalidEndpoint
    case notBinaryFrame
    case userCancelled
    case rejected(String)
}

// MARK: - 小工具

private func CryptoSHA256(_ data: Data) -> Data {
    // iOS/macOS 原生 CryptoKit（与 HakoAgentKit 内 swift-crypto 的 SHA256 同算法）
    Data(SHA256.hash(data: data))
}

extension String {
    func base64urlDecoded() -> Data? {
        var s = self
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s.append("=") }
        return Data(base64Encoded: s)
    }
}

#endif

extension Data {
    /// base64url（RFC 4648 §5，无填充）解码；口令 URI 的 k/s 用它。
    init?(base64urlEncoded: String) {
        var s = base64urlEncoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        self.init(base64Encoded: s)
    }
}
