// HakoAgentKit — Anchor 控制面协议的 Swift 实现（纯逻辑）。
// 与 agent 端（TS）共享测试向量互验；任何协议变更必须同步两侧。

/// 协议常量（与 TS 侧 src/protocol/noise.ts 一致）
public enum AnchorProtocol {
    public static let protocolName = "Noise_XX_25519_AESGCM_SHA256"
    public static let dhLen = 32
    public static let maxFrame = 65535
    /// 传输帧明文上限（扣 16B GCM tag）
    public static let maxPlaintext = maxFrame - 16
}
