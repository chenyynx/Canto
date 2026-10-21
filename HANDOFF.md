# Hako / Clash iOS 客户端 —— 项目交接文档

> 生成时间：2026-10-21
> 交接对象：Claude Code（全盘接手）
> 编写：Doris（前一轮主要贡献者）
> 用途：把「项目从哪来、改过什么、现在什么状态、哪些没修、怎么构建出包验证」一次性讲清楚，避免接手方重复踩坑。

---

## 0. TL;DR（先看这段）

- **项目**：`chenyynx/Hako-Client`（iOS/iPadOS/macOS/tvOS 原生 Clash 客户端，SwiftUI + Go 内核），是上游 `ProjectClash/Clash-Client`（原名 `TokenPLS/Hako-Client`）的 fork，**外加我们自己的一套 Anchor（远程 Agent 控制面）功能**。
- **当前痛点**：侧载（全能签）环境下，App 与隧道扩展之间的**控制通道（NETunnelProviderSession 消息）建立不起来**，导致「活动→连接」显示 `The connections stream is unavailable`、内核运行时内存 0.0MB、「说我没连接」。
- **已解决**：掉帧/发热（已由用户实测确认）、App Group 共享容器、iCloud 闪退、Agent 卡片打不开、Agent 信封 `v` 字段解码失败。
- **未解决**：控制通道（needs 下一步：IPC 底层错误码 + 扩展进程重启原因）。
- **一句话给接手者**：卡顿是两个独立问题的叠加——① 每秒重试风暴（已用指数退避止血）；② 通道本身没通（未解决）。**不要把它们混为一谈**，这也是前一轮花了很久才理清的。

---

## 1. 项目起源与仓库拓扑

### 1.1 上游演进

| 阶段 | 仓库 | 说明 |
|---|---|---|
| 原始 | `TokenPLS/Hako-Client` + `TokenPLS/Hako`（内核） | 项目最初形态，命名 Hako |
| 改名迁移 | `ProjectClash/Clash-Client` + `ProjectClash/Clash`（内核） | 2026-10 上游宣布迁移；代码整体 `Hako→Clash` 重命名，新增启动恢复、配置编辑体系、增量连接事件流等；**无 release、无 CI 产物** |

### 1.2 我们的 fork

| 仓库 | 用途 | 备注 |
|---|---|---|
| `chenyynx/Hako-Client` | 主仓库（App + CI + 出包） | 基于 `TokenPLS/Hako-Client` 旧命名；已合入部分上游新仓库的改进 |
| `chenyynx/Hako` | 内核镜像（Go） | 对应上游 `TokenPLS/Hako`；CI **不使用本地镜像**，见 §5.3 |
| `chenyynx/Hako-Adapter` | 内核适配层 | 跟随主仓库 |
| `/var/minis/shared/anchor`（本地，TS） | Anchor Agent daemon（Node/TS） | 与 App 端 Swift 协议对接；**未纳入主仓库 CI** |

### 1.3 本地工作副本（iSH 内）

- 主仓库：`/var/minis/shared/hako/Hako-Client`
- **注意**：本地副本曾因磁盘清理被整体删除过一次（2026-10-21），现为从 GitHub 重新拉取的快照，**git 历史通过 `git fetch + reset --mixed origin/main` 接回**。接手时先 `git fetch && git status` 确认。

---

## 2. 架构关键点（改代码前必读）

### 2.1 进程与通道

```
┌─────────────────────┐        NETunnelProviderSession        ┌──────────────────────────┐
│  App (HakoClient)   │ ─────── sendProviderMessage ────────▶ │ PacketTunnel 扩展进程      │
│  ClashCommandClient │ ◀────── completionHandler(reply) ──── │ ExtensionProvider         │
└─────────┬───────────┘                                        │  ├─ Go 内核 (Hako.xcframework)
          │                                                    │  └─ handleMessage → hello/runtimeDiagnostics/...
          │ Unix socket  <AppGroup>/clash.sock                  │
          └──────────────────────────────────────────────────▶ └──────────────────────────┘
```

两条独立通道，**必须分清**：

1. **provider message 通道**（`sendProviderMessage`）：用于 `hello` 握手、runtimeDiagnostics、Go crash report 等。**当前坏的是这条**。
2. **Unix socket 通道**（`<AppGroup>/clash.sock`）：Go 内核起控制面后监听，App 的 `HakoClashAPIClient` 据此拉流量/连接/日志。日志证明**内核每次都成功建立 socket**（`go-phase=clash-api-up`），所以 socket 不是问题。

`hello` 只走 ①；`hello` 失败则压根不会去连 ②。

### 2.2 App Group 与签名（侧载核心）

- 代码内建 group：`group.org.example.hako`（`HakoAppIdentifiers.appGroup`）
- **全能签重签后的描述文件实际授权**：`group.a05b266105020512.1~5`（实测，见 §6.1）
- `HakoAppGroupContainer.appGroupContainer`（`apple/HakoClient/Shared/`）实现了**运行时探测**：内建 group → 签名 entitlements 里的候选（SecTask SPI，`dlsym` 动态解析）→ 全失败才退化到沙盒 `Documents/HakoAppGroup`。
- ⚠️ 退化的沙盒路径**两边不共享**（App 与扩展各自沙盒），会直接导致隧道读不到配置——这是第一代「隧道提供方报错」的根因，现已由探测修好。
- iCloud 同理：`ICloudEntitlementProbe`（HakoClientKit）运行时探测，无权限走 unavailable 降级，避免 CKContainer 构造抛 NSException 闪退。

### 2.3 首页渲染与刷新（掉帧相关）

- `GoldenFlowHomeView` 构建 `AppleClientSnapshot`（Equatable）→ `HakoHomeView`（`.equatable()`）。
- **坑**：快照里包含 `traffic`，而内核 `/traffic` 每秒推一帧 → 快照每秒不等 → 整页 12+ 卡片重算。
- 上游只在 **Mac** 端注入了 `\.hakoTrafficFeed`（独立订阅，见 `HakoMacApp` 242/902/1014 行），**iOS 端漏了**。
- 我们在 `0c633a7` 补齐：App 持有 `HakoTrafficFeed`，快照内 `traffic` 冻结为 `.zero`，只有流量卡订阅 feed。

### 2.4 连接数据流（性能）

- 上游新仓库把 `CommandConnections`（250ms 全量快照）换成了 `CommandConnectionEvents`（增量事件，interval 1000）。
- 我们已在 `379104b` 文件级搬运（`ConnectionsModel` / `ConnectionRuntimeFeed` / `ConnectionObservationSource`），并把 `ClashCommandClient.statusInterval` 调到 1000（`46f5036`）。
- **内核要求**：`CommandConnectionEvents` 需要内核 ≥ `94377673`（events 提交）。`Dependencies.lock.json` 的 kernel pin 已从 `7ea70d15` 升到 `9437767346a63957c60bf027b6d9fb27e51d89c4`。

### 2.5 Anchor（远程 Agent 控制面，我们独有）

- Swift 端：`apple/HakoClient/Sources/AgentBridge/`（`AnchorConnector` / `AnchorPairingService` / `AnchorBridgeController` / `AnchorIdentityStore` / `AnchorAppCommandExecutor` / `AnchorPushService`）
- 扩展端：`Extension/AnchorAgentControlService.swift`、`Extension/AnchorMailboxService.swift`
- 协议包：`apple/HakoAgentKit`（`Envelope.swift` / `NoiseXX.swift` / `AnchorIDs.swift` / `SessionLogic.swift`）
- UI：`apple/HakoClientUI/.../Features/Anchor/`（`AnchorHomeCard` / `AnchorPairingView` / `AnchorSettingsView`）
- Agent 侧实现：`/var/minis/shared/anchor`（TS daemon + MCP server + gateway）
- 协议要点：Noise XX 握手 → 信封帧（`v/t/id/ref/seq/ch/op/args/data/ttl_ms/...`）→ `op` 命名空间路由（app/core/device/evt）。
- **已知坑**：TS 侧历史实现**不发 `v` 字段**，Swift 侧严格解码会 `keyNotFound("v")`（见 `7f5c966`，Swift 已容错、TS 已补发，但 **TS 侧需要重新部署 daemon**）。

---

## 3. 时间线（我们参与的变更）

> 上游历史到 `c3b7bff`（2026-10-10）为止；以下为我方提交，全部在 `chenyynx/Hako-Client` 的 `main`。

| 提交 | 日期 | 内容 | 结果 |
|---|---|---|---|
| `2fdbc19` | 10-15 | App Group 签名探测 + 首页导航容器（Home tab 包 `HakoFeatureNavigationContainer`） | 修「隧道提供方报错」与「Agent 卡片点击无效」✅ |
| `64a33d7` | 10-14 | iCloud entitlement gate | 修 sideload 启动闪退 ✅ |
| `f1b01f5` | 10-14 | App Group 不可用时降级到沙盒 | 过渡方案（后被 2fdbc19 取代） |
| `9fbe5ed`/`71e775f`/`f21a278` 等 | 10-14 | CI/出包脚本修复（退出码判定、去假红源） | 出包流水线可用 ✅ |
| `379104b` | 10-19 | 连接流切增量事件 + 1000ms | 性能方向 ✅ |
| `29a414d` | 10-19 | ConnectionHistory 升级 + 内核 pin 升 `94377673` | 修 CI 缺符号 ✅ |
| `955249f` | 10-19 | bootstrap 过期 SDK 自愈（缓存 restore-key 命中旧 SDK） | 修 CI provenance 失败 ✅ |
| `44bef7b`~`6e19e6f` | 10-19 | [hark] 5 个编译修复（palette 别名、clearRequests 等） | CI 转绿 ✅ |
| `46f5036` | 10-20 | statusInterval 250→1000 | 降空闲刷新 ✅ |
| `0c633a7` | 10-21 | **iOS 接独立流量 feed** | **掉帧主因之一 ✅** |
| `ca593c9` | 10-21 | hello 等待隧道就绪 + 错误分类 | 修「说我没连」的**误导报错**（未修通通道） |
| `7f5c966` | 10-21 | Envelope `v` 字段容错 | Agent 握手解码 ✅（TS 需重部署） |
| `465e113` | 10-21 | IPC 底层错误落日志 + 控制通道指数退避 | **卡顿止血 ✅**，错误可见 |
| `91d8f5f` | 10-21 | hello 2s×5 短超时重试 | **用户实测「现在不卡了」✅** |

---

## 4. 当前状态（2026-10-21 17:00）

### 4.1 已解决 ✅

| 问题 | 修复 | 验证方式 |
|---|---|---|
| 启动闪退（iCloud NSException） | `64a33d7` SecTask 探测 | 装机不闪退 |
| 「隧道提供方报告错误，VPN 已断开」 | `2fdbc19` App Group 探测 | VPN 可连接 |
| 首页「无法准备本地 Direct 配置」 | 同上 | 首页正常渲染 |
| Agent 卡片点击无反应 | `2fdbc19` 首页 NavigationStack | 卡片可进二级页 |
| Agent 卡片「握手/解码失败 keyNotFound("v")」 | `7f5c966`（+ TS 补发 v） | 卡片不再报该错 |
| **掉帧/发热** | `0c633a7` + `465e113`/`91d8f5f` | 用户实测「不卡了」；帧日志 `home.snapshot` 90-132 → 18 次/1.5s，fps 16 → 57-59 |

### 4.2 未解决 ❌

| 问题 | 现象 | 现有证据 | 已排除 |
|---|---|---|---|
| 控制通道建立失败 | 活动→连接：`The connections stream is unavailable`；内核运行时内存 0.0MB；提示「连接 Clash 后可读取内核诊断」 | 日志 `control-session/connect-failed: The tunnel extension did not reply to the command session.`（19:39:42、19:39:56 各一次）；此后无 `control hello ok` | ① 内核 socket 不是原因（`go-phase=clash-api-up` 每次都成功）② 不是 schema 真不兼容（0...0 是旧代码误报，已修）③ 不是启动竞态单次问题（已加 3s 等待 + 2s×5 重试仍未通） |
| 扩展进程疑似重启 | `fp` 内存足迹 14MiB → 7.8MiB（19:41:36），说明扩展进程重建 | go-phase 两次完整启动序列 | 无 crash 日志（MetricKit 空、Diagnostics Inbox 空） |

### 4.3 接手第一步建议

1. **先确认通道到底卡在哪**：`465e113` 已把 `sendProviderMessage` 的 NSError（domain/code）写进 App 日志。让用户导一次日志（工具→活动→日志→搜 `ipc`/`hello`），三种可能：
   - `ipc send failed domain=NEProviderErrorDomain code=...` → 苹果框架层拒绝，按码查（常见：session 未 connected、provider 未启动）
   - `transportNoReply`（无 ipc 行）→ 消息发出但扩展没回：查扩展 `handleAppMessage` 是否被执行（扩展日志里没有对应行）
   - `malformedHello(...)` → 扩展回了但内容不对
2. **若确认扩展不回**：重点查 `ExtensionProvider.handleMessage` 是否被主线程/actor 阻塞。当前实现是 `PacketTunnelProvider.handleAppMessage` → `Task { await provider.handleMessage(...) }`；`ExtensionProvider` 是 `final class`（非 actor），但 `start()` 走 `ProviderOperationGate`，`handleMessage` **不经过闸门**——理论上不互斥，需实测确认是否被启动期长任务占用。
3. **另一条独立线索**：扩展进程重建（14→7.8MiB）。可对比上游新仓库 `ClashStartRecovery`/`ClashTunnelStart`（启动结果记录、坏配置隔离、退避）——**我们还没搬这套**（见 §7.2）。

---

## 5. 构建 / 出包 / 签名

### 5.1 仓库内构建

```bash
cd apple/HakoClient
python3 ../../scripts/bootstrap.py        # 拉 pinned 内核 + adapter，构建 Hako.xcframework
python3 ../../scripts/configure.py --bundle-base org.example.hako   # 生成 xcodeproj
xcodebuild -project HakoClient.xcodeproj -scheme HakoClient -configuration Release ...
```

- 工程文件由 **XcodeGen**（`apple/HakoClient/project.yml`）生成，**新增 Swift 文件必须写进 project.yml 对应 target 的 sources**，否则不进包。
- `apple/HakoClientUI` 是 SwiftPM package（`Sources/` 自动全包含，新文件不用改配置）。
- Release 优化：各 target `SWIFT_OPTIMIZATION_LEVEL = -Osize`。

### 5.2 CI（GitHub Actions）

| Workflow | 文件 | 触发 |
|---|---|---|
| CI（编译 + HakoAgentKit 单测） | `.github/workflows/ci.yml` | push main |
| Unsigned IPA 出包 | `.github/workflows/unsigned-ipa.yml` | **手动 dispatch**：`POST /repos/chenyynx/Hako-Client/actions/workflows/unsigned-ipa.yml/dispatches` body `{"ref":"main"}` |

- 出包产物：artifact 名固定 `Hako-unsigned-ipa`（约 41-43MB）。⚠️ **多个 run 同名 artifact，交付时必须带 run 号**（曾踩过拿混）。
- 出包后需要 **全能签重签**，签 **4 个对象**：主 App + `HakoClientExtension`（隧道，必须签）+ `HakoControlsExtension` + `HakoShareExtension`；**装前先删旧 App**。

### 5.3 内核 pin 机制（重要）

- `scripts/bootstrap.py` 会 `git clone` `Dependencies.lock.json` 里 `kernel.repository` 的 **精确 revision**，产物 `Hako.xcframework` 用 `HakoBuildInfo.json` 校验 provenance（`sourceRevision` 必须等于 pin）。
- **CI 不使用本地 `/var/minis/shared/hako/Hako` 镜像**。所以要改内核，必须推到可访问的远端仓库并改 pin。
- 缓存坑：cache 用 `restore-keys` 前缀命中可能恢复**旧 pin 构建的 SDK**，`955249f` 已加自愈（provenance 不符 → 移开重建）。

### 5.4 测试设备与签名

- 用户设备：iPhone 15 Pro（iPhone15,2），iOS 26.2（23C55）
- 签名方式：**全能签**；描述文件 Team `RQ39WT35P2`，App ID `app.bronze6658.lychee6856`
- 该描述文件**包含**：`com.apple.developer.networking.networkextension`（packet-tunnel-provider 全套）、App Groups `group.a05b266105020512.1~5`、aps-environment、keychain-access-groups；**不包含** `group.org.example.hako`、iCloud 容器为空

---

## 6. 排查工具与方法论（接手直接用，省你几天）

### 6.1 解 IPA 看签名 entitlements（无需 codesign）

```bash
unzip -q Hako.ipa -d /tmp/ipa && APP=$(ls -d /tmp/ipa/Payload/*.app)
# 描述文件
python3 - <<'EOF'
import re
data=open('/tmp/ipa/Payload/XXX.app/embedded.mobileprovision','rb').read()
open('/tmp/host.plist','wb').write(re.search(rb'<\?xml.*?</plist>',data,re.S).group())
EOF
grep -A2 "application-groups\|networkextension\|icloud-services" /tmp/host.plist

# 二进制内嵌 entitlements（直接抓明文 XML 片段）
python3 - <<'EOF'
import re
b=open('<APP>/HakoClient','rb').read()
m=re.search(rb'<key>com\.apple\.security\.application-groups</key>.{0,400}?</array>',b,re.S)
print(m.group().decode() if m else 'none')
EOF
```

### 6.2 验证某个修复真的在包里（不是「CI 绿了」就算数）

```bash
strings <APP>/HakoClient | grep -c "not ready to receive commands"   # 例：验证 ca593c9
strings <APP>/HakoClient | grep -c "unreadable hello"
```

### 6.3 帧日志（**最有效的性能工具，比 MetricKit 快**）

- App 内置 `HakoFrameWatch`（`apple/HakoClientUI/.../Network/HakoFrameWatch.swift`），首页挂了 `.hakoFrameWatch("Home")`。
- 日志位置：**工具 → 活动 → 「日志」页 → 搜 `frames` / `hitch`**
- 格式：
```
frames Home drawn=68 late=6 worst=149.0ms fps≈45 over=1.50s [home.snapshot=18/2ms home.card=44/0ms ...]
hitch Home 149.0ms
```
- 读法：`late` = 迟到的帧数；`worst` = 最差单帧；方括号里是 `HakoPerf` 计数器（`次数/总耗时`）。**`home.snapshot` 每 1.5 秒的次数是最关键指标**：
  - 正常 ≈ 5-20
  - 异常 90-222（说明有东西在高频驱动整页重绘）
- 另有 `frameLogFile`：`Documents/hako-frames.log`（256KB 滚动，JSON 以外的最原始记录）。

### 6.4 日志导出的其它来源

| 来源 | 路径 / 入口 |
|---|---|
| App 内日志 | 工具 → 活动 → 日志 → 导出 |
| MetricKit 收件箱 | 工具 → Diagnostics Inbox（`MetricKitInboxView`，CPU 诊断要 24h 才投递，常为空） |
| 系统分析数据 | 设置 → 隐私与安全性 → 分析与改进 → 分析数据 → 搜 `Hako` |
| 扩展日志 | 混在同一个日志文件里，格式为 `HH:MM:SS.mmm  go-phase=...` / `fp=...` |

### 6.5 内核启动阶段日志（扩展侧）

`go-phase=` 序列是判断内核走到哪一步的关键：
```
setup:paths-wired → setup:dirs-probed → setup:crash-armed → setup:monitors-armed
→ start-first-statement → validated → core-count-bumped → pre-config-parse
→ bind:unmarshalled → apply:profile → apply:proxy-providers-loaded
→ tun-fd-ready → apply:tun → apply:tunnels → tun-verified → **clash-api-up**
→ start-return-done
```
`clash-api-up` 出现 = Unix socket 已建立。**目前每次都出现**，所以 socket 侧没问题。

---

## 7. 待办清单（按优先级）

### P0：控制通道没通（用户当前唯一阻塞）

1. 拿到 `465e113` 之后的日志，确认 `ipc send failed domain/code` 或 `transportNoReply`。
2. 若扩展不回：
   - 在 `ExtensionProvider.handleMessage` 入口/出口加日志（是否被调用、耗时多少）。
   - 检查 `PacketTunnelProvider.handleAppMessage` 里 `Task { await provider.handleMessage(...) }` 是否被 NE 的 completionHandler 生命周期影响（NE 要求尽快回调，若超时系统会丢弃）。
3. 若 `NEProviderErrorDomain` 报错：按码查，常见 `code=1`（session 未连接）/ `code=3`（provider 未运行）。
4. 备选思路：**给 hello 加一条不依赖 provider message 的旁路**——把 schema/capabilities 写进 App Group 里的文件（扩展启动时写，App 读），绕过 NE 消息通道直接进 socket。这是最坏情况的兜底方案。

### P1：扩展进程疑似重启

- 对比 `fp` 变化时间点与 `go-phase` 完整序列，确认是否 crash。
- 上游新仓库有 `ClashTunnelStart` / `ClashStartRecovery`（启动结果落盘 + 坏配置隔离 + 失败退避），我们**未搬**。建议评估搬运。

### P2：上游新仓库未搬运的部分

| 模块 | 上游文件 | 价值 |
|---|---|---|
| 启动恢复 | `Shared/ClashTunnelStart.swift`、`Shared/ClashStartRecovery.swift` | 启动失败可诊断、坏配置隔离 |
| Go 崩溃报告 | `Sources/AppArchitecture/AppGoCrashReport.swift` | 内核崩溃可读 |
| App Group 直连兜底 | `AppGroupDirectFetch`（在 `ClashCommandClient.swift` 末尾） | 控制通道不通时仍能下载订阅 |
| 配置编辑体系 | `ConfigUI/Configuration*.swift`（17 个文件，约 5000 行） | 上游重构的一页式配置编辑 |
| Feedback 体系 | `Design/ClashFeedback*` + `Sources/Feedback/*` | 统一的 toast/撤销/生命周期 |
| 其它 | `ProxyNodeCatalogForm`、`ExternalControllerSettingsView`、`ProfileRuntimeTrustEditor` | 功能增强 |

> **注意**：`/var/minis/shared/hako-port-staging/` 里存着上一轮已经机械搬运并改名的一部分（TunnelStart / StartRecovery / GoCrashReport / Feedback 三件套 / Clipboard / AppGroupDirectFetch / ResourceDownloader.new），可直接复用，但**未接入 project.yml**、未编译验证。

### P3：细节完善

- `ClashCommandClient` 里 `statusInterval` 已 1000；`ConnectionsModel` 已 1000。
- `HakoHomeView` 里 `equatable` 的 `==` 只比较 `snapshot` + `presentationClass`，若后续再加环境依赖记得同步。
- `HakoActivityRequestsPause` 已加 `@MainActor`（Swift 6 严格并发要求）。

---

## 8. 环境与坑（血泪）

### 8.1 iSH 本地环境

- iSH 磁盘 **120G 只剩 ~1.9G**（iOS 系统占大头）。**不要在本地跑 Go 全量编译**，会 `no space left on device` 或 segfault。
- `rm -rf` 大目录会 `fts_read failed` 并静默留残骸；用 Python `os.walk(topdown=False)` 逐文件删。
- `du -sh` 对 `/var/minis/shared` 会误报 0，要 `os.lstat().st_size` 累加。
- Shell 是 BusyBox ash + 部分 GNU 工具；`grep -r --include=` 不支持，用 `rg`。
- iSH 直连 GitHub 不通，用 `gh.llkk.cc` 代理下载（`https://gh.llkk.cc/https://github.com/...`）；但 **git push 可直连**（`https://github.com/...` 可用）。

### 8.2 CI 坑

- `bootstrap.py` 的 SDK 缓存会因 `restore-key` 前缀命中旧版本 → 已加自愈逻辑（`955249f`），改 pin 时注意。
- CI 比较慢：内核 SDK 全量重建 15-25 分钟（缓存命中会快很多）。
- GitHub Actions 免费 runner 高峰期会排队。

### 8.3 出包 / 安装坑

- artifact 名固定 → **必须用 run 号区分**。
- 全能签重签必须签 **4 个 target**，隧道扩展漏签会导致「提供方报错」。
- 装前删旧 App；bundle id 相同会覆盖，但扩展缓存可能不刷新。

### 8.4 代码结构坑

- `apple/HakoClient/project.yml` 是**显式文件清单**，新增文件必须登记（`HakoClientUI` 例外，SwiftPM 自动包含）。
- `apple/HakoClientUI` 与上游 `ClashClientUI` **除 Package.swift 外完全一致**（1 个文件差异）——改 UI 时可直接对照上游。
- 内核框架里的 Swift 符号名由 **Go 包名 + Go 类型名** 决定（`package hako` + `type ClashAPIClient` → `HakoClashAPIClient`）。改内核命名时两边要一起对齐。
- `HakoCommandSchemaVersion` 等常量来自内核绑定；若为 0 说明 SDK 版本不对（不是协议问题）。

---

## 9. 关键文件索引

### App 侧

| 文件 | 作用 |
|---|---|
| `apple/HakoClient/Sources/HakoClientApp.swift` | App 入口、shell（compactTabs / regularSidebar）、`goldenFlowShell`、流量 feed 注入、rebind |
| `Sources/ClashCommandClient.swift` | 控制通道（hello / socket 客户端 / 重连退避 / 流量 reducer / 日志批处理） |
| `Sources/HakoClient.swift` | `HakoIPCChannel`（sendProviderMessage 串行队列）、`HakoClient.hello()`、错误枚举 |
| `Sources/ConnectionsModel.swift` | 连接流（增量事件 Table）、`ConnectionEventTable`、`syncScene` |
| `Sources/ConnectionObservationSource.swift` | 连接观测（信箱、去重、配对确认、`HakoReconnectBackoff`） |
| `Sources/ConnectionRuntimeFeed.swift` | 运行时身份识别 + 事件 writer 适配 |
| `Sources/ConfigUI/GoldenFlowHomeView.swift` | 首页快照构建（`untimedSharedSnapshot`）、编辑器 sheet |
| `Sources/ConfigUI/ConnectionHistory.swift` | 连接历史（seal/recordClosed/clear，事件流合并用） |
| `Shared/HakoAppGroupContainer.swift` | **App Group 探测（签名适配核心）** |
| `Shared/HakoAppIdentifiers.swift` | bundle id / group / iCloud 常量 |
| `Extension/ExtensionProvider.swift` | 扩展主体：start/stop、`handleMessage`（hello 等）、Go 内核桥 |
| `Extension/PacketTunnelProvider.swift` | `NEPacketTunnelProvider` 薄壳，`handleAppMessage` 转发 |
| `Sources/AgentBridge/*` | Anchor 连接器 / 配对 / 桥 / 命令执行 / 推送 |
| `apple/HakoAgentKit/.../Envelope.swift` | Anchor 信封协议（v 字段容错） |

### UI 包

| 文件 | 作用 |
|---|---|
| `Features/Home/HakoHomeView.swift` | 首页（卡片、`hakoTracksScrollDistance`、`HakoTrafficCard`、`HakoActivityRequestsPause` 使用方） |
| `Features/Home/HakoTrafficFeed.swift` | 独立流量订阅对象 + 环境键 |
| `Navigation/HakoRoutedViewLink.swift` | 路由 push（`hakoPushRoute` / `HakoViewRoute`） |
| `Navigation/HakoRegularClientShell.swift` | iPad/macOS 侧栏壳、`HakoRoutePusher` |
| `Layout/HakoSingleColumnPresentation.swift` | 单列 NavigationStack 容器 |
| `Components/HakoFrameWatch.swift` | 帧监控 + `HakoPerf` 计数器 |
| `Features/Anchor/AnchorHomeCard.swift` | Agent 卡片（整卡跳转） |

### 脚本 / 配置

| 文件 | 作用 |
|---|---|
| `Dependencies.lock.json` | 内核/adapter pin（**改内核必须改这里**） |
| `scripts/bootstrap.py` | 拉内核 + 构建 xcframework + provenance 校验 |
| `scripts/configure.py` | 生成 Xcode 工程（bundle base 可配） |
| `apple/HakoClient/project.yml` | target / entitlements / 源文件清单 |
| `.github/workflows/ci.yml` | 编译 + 单测 |
| `.github/workflows/unsigned-ipa.yml` | 出未签名 IPA |

---

## 10. 已知误导性信息（不要被带偏）

1. **`invalid command schema range 0...0`**：这是旧代码把「传输失败」伪装成 schema 错误，**不代表扩展真的返回 0**。已修（`ca593c9`）。
2. **`The tunnel extension did not reply`**：可能是「发送就失败」也可能是「发出去了没人回」，`465e113` 之后日志能区分。
3. **MetricKit CPU 报告**：只覆盖 **App 进程**，不包含隧道扩展；扩展发热/CPU 高时该报告看不出来。
4. **`fp`（footprint）下降**：不一定是 leak 修复，可能是**扩展进程重建**（见 `14MiB → 7.8MiB`）。
5. **上游「没这问题」**：上游新仓库（Clash-Client）确实修了连接流性能，但**控制通道/首包竞态代码与我们同源**；差异主要来自我们升了内核 pin（扩展启动时序变长）。
6. **`home.snapshot` 计数**：它是「每次访问 `sharedSnapshot` 计算属性」的次数（含 body 多次访问），不要当成纯 body 次数。

---

## 11. 交接建议顺序

1. `git log --oneline -20` 看历史 → 读 §2 架构 → 读 §4 当前状态
2. 要一份**最新日志**（工具→活动→日志），确认 `ipc` / `hello` / `frames` 三类行
3. 按 §7 P0 推进控制通道；**先拿证据再改代码**（这一轮最大的教训）
4. 改动遵循仓库惯例：`[名字] fix/perf: 中文摘要`，一次一个主题，推 main 触发 CI
5. 出包：CI 绿后 dispatch `unsigned-ipa`，交付链接带 run 号

---

## 附：最近一次验证数据（供对比基线）

**旧包（2fdbc19）**：
```
frames Home drawn=37 late=24 worst=109.5ms fps≈24 over=1.51s
  [home.snapshot=104/21ms home.card=212/1ms home.body=53/0ms]
```

**新包（91d8f5f，未连接时）**：
```
frames Home drawn=89 late=1 worst=33.1ms fps≈59 over=1.51s
  [home.snapshot=18/1ms home.card=44/0ms home.body=11/0ms]
```

**新包（91d8f5f，连接后）**：
```
frames Home drawn=87 late=1 worst=60.8ms fps≈58 over=1.50s
  [home.snapshot=222/16ms ...]   ← 连接后控制通道重试风暴（已用退避止血）
control-session/connect-failed: The tunnel extension did not reply to the command session.
```
