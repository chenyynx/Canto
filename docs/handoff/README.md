# Anchor P5 出包交接（muse 用）— 2026-10-14

## 你要修的（就一件事）

**最后 1 条编译错误**：
- `apple/HakoClientUI/Sources/HakoClientUI/Features/Anchor/AnchorPairingView.swift:357:55`
- `sending value of non-Sendable type '() async -> Bool' risks causing data races`（Swift 6 严格并发）

**修法**（二选一）：
1. `AnchorSASDecision`（同文件 ~20 行处，continuation 包装类）→ 改 `final class AnchorSASDecision: @unchecked Sendable`
2. `pair(bonjour:sasConfirmed:)` 的 `sasConfirmed` 参数类型标 `@Sendable`（协议在 `AnchorBridge.swift` 的 `AnchorPairingServiceProtocol`，实现类 `AnchorPairingService`）

推荐 1——改动最小，语义正确（该类内部就是 continuation + 状态位，无共享可变状态）。

## 修好后出包（零额外工作）

```
gh workflow run unsigned-ipa.yml --repo chenyynx/Hako-Client --field bundle_base=org.example.hako
# 或 Actions 页面手动触发 Unsigned IPA
```
- 约 4-5 分钟（内核缓存已生效）
- artifact：`Hako-unsigned-ipa`（未签名，含主 App + 3 扩展）
- pp 拿全能签签装；**4 个 target 都要签**（尤其 PacketTunnel 扩展，漏签 VPN 开不了）

## 勿动

1. `ci.yml` 的 Build 步骤——`set -uo pipefail` + scheme+逐 target 两段式 + 错误聚合过滤假模块错。这是修「假绿」的根因（之前 `xcodebuild|tee` 吞退出码，27 条编译错被标 success）
2. `unsigned-ipa.yml` 的两段式结构（同上，本轮趟出来的）
3. 缓存 restore/save 分离（`actions/cache/restore@v4` + always-save）——删了每轮回 13 分钟

## 踩坑清单（本轮全趟平，别再踩）

| # | 坑 | 正解 |
|---|---|---|
| 1 | `Envelope` 无 public 成员初始化器 | 已加 `public init(t:id:)`（Envelope.swift 42 行附近） |
| 2 | `anchorPreview` 调色板扩展曾被 `#if DEBUG` 包住，Release 缺失 | 已移出；修复时剪切错位置搞坏过结构，已整段重建 |
| 3 | xcodebuild `-keepGoing` 在 runner Xcode 上不存在 | 已用 scheme+逐 target 替代 |
| 4 | `HakoPasteControl` 在 App target，UI 包不可见 | 已建包内自足 `AnchorPasteButton`（iOS16+ PasteButton / 回退 UIPasteboard） |
| 5 | `any AnchorBridgeObservable` 不能 @ObservedObject | 已建 `AnchorBridgeProxy`（类型擦除桥）+ 协议加 `observeChanges` 要求 |
| 6 | `GlobalConfig` 在 Extension target 不可见 | Extension 里直接 `UserDefaults(suiteName:)` |
| 7 | @MainActor 协议方法被 nonisolated 调用 | `AnchorBridgeProxy.init` 标 `@MainActor` |

## 验证手段

- 本机（iPhone iSH）**跑不了** tsc/Swift 编译（环境限制），一切验证走 GitHub Actions
- 跑完 CI 看错误聚合区（`=== 全部编译错误（N 条）===`），它已过滤 `-target` 构建的假模块错误
- swift-test 在 Linux runner（HakoAgentKit 的 swift-crypto 跨平台）

## 相关文档

- `docs/handoff/生产级方案-v4-终版.md` — 设计总纲（协议语义/架构/威胁模型）
- `docs/handoff/项目简报.md` — 项目背景与约束
- `docs/handoff/handoff-2026-10-1{3,4}.md` — 每期完成的详细记录
- `docs/anchor-p4-wake.md` — P4 Gateway 部署 runbook
