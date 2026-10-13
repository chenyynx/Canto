# HakoAgentKit

Anchor 控制面协议的 Swift 实现（纯逻辑包，不依赖 iOS 运行环境）。

## 内容

- `NoisePrimitives` / `NoiseXX`：Noise_XX_25519_AESGCM_SHA256 握手 + 传输加密（swift-crypto：Curve25519 / AES-256-GCM / SHA256）
- `Envelope`：信封帧建模 + 不变量校验 + JSON 编解码
- `PairingURI`：`hako://pair` 口令 URI 构造/解析
- `SessionLogic`：去重表（256 条/10 分钟）、指数退避、通道序号分配
- `AnchorIDs`：ULID / Crockford Base32 / 公钥派生 id

## 互验机制（重要）

与 agent 端（TS，`chenyynx/anchor`）共享两份黄金向量，任何一侧修改协议必须双侧同步：

| 向量 | 内容 |
|---|---|
| `Tests/Fixtures/vectors.json` | 信封合法/非法、配对 URI、路由、ops（JSON Schema 契约） |
| `Tests/Fixtures/vectors-noise.json` | Noise 原语逐字节黄金值 + 握手往返不变量（由 anchor 仓 `tools/gen-noise-vectors.ts` 生成） |

## 测试

```bash
cd apple/HakoAgentKit && swift test
```

CI：GitHub Actions `swift-test` job（Linux runner，swift-crypto 跨平台）。
