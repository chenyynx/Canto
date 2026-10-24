# 上游同步方案（ProjectClash/Clash-Client → chenyynx/Canto-Client）

> 2026-10-22 盘点。基线：我们 fork 的代码快照 = 上游 `3e93b98`（2026-10-10）。
> 上游 HEAD：`3b8ea95`（2026-10-21）。

## 1. 差距（已量化）

| 项 | 数字 |
|---|---|
| 上游新增提交 | **18 个** |
| 文件变更 | **383 个**（新增 168 / 修改 215 / 删除 0） |
| 代码量 | **+108,067 / −6,017 行** |
| 主要新增子系统 | AdBlock 引擎（~1.6 万行）、Module 子系统（MITM/重写/脚本）、大列表分页与规则集预编译、macOS 修复 |

> 注意：我们的仓库是「改名 fork」（Clash→Canto），直接 `git merge` 不可行（新上游是独立历史，无共同祖先）。所有同步必须做**文件级语义合并 + 改名变换**。

## 2. 两种方案

### 方案 A：全量同步（对齐上游 HEAD）

- 把上游 383 个文件全部搬过来（改名变换），再重放我们的本地改动
- 优点：一次到位，后续跟上游零摩擦
- 缺点：上游这批含大量 UI 重构（分页、Home 卡片、设置），会与我们已有的 UI/无障碍改动冲突；风险面最大；估 **5–8 天**

### 方案 B：定向同步（推荐）——只搬 Module / AdBlock 闭包

- 只取「可编程面」相关文件及其依赖闭包：**新增 128 个 + 修改约 30 个**
- 修改文件里最关键的是集成点：
  - `Extension/ExtensionProvider.swift`、`Extension/PacketTunnelProvider.swift`（引擎接线）
  - `Sources/ClashCommandClient.swift`、`Sources/ClashClientApp.swift`
  - `Sources/ConfigStore/`（ProviderMaterializer / ProfileActivationCoordinator / BackgroundRefresh / ResourceDownloader）
  - `Sources/ConfigUI/`（模块页、设置项、Home 卡片钩子）
  - `apple/ClashClientUI`（21 个新文件）
- 优点：直接拿到「兼容 Surge/Loon/QX 模块」的能力，风险可控，估 **3–5 天**
- 缺点：不追 UI/分页/macOS 修复；下次还得再同步一次

## 3. 推荐：方案 B，分四步

**P0 准备（0.5 天）**
1. 打快照 tag `pre-upstream-sync-20261022`（回滚锚）
2. 写改名变换脚本（`Clash`→`Canto`、`clash`→`canto` 的标识符/路径映射，排除第三方与系统 API 名）
3. 生成闭包清单（新增 128 + 修改 30），逐项标注：直接搬 / 需三方合并

**P1 新增文件落库（1–1.5 天）**
- 128 个新文件按变换搬入，登记 `apple/CantoClient/project.yml` 对应 target
- 先保证能编译（允许功能未接线）

**P2 集成点合并（1.5–2 天）**
- 对约 30 个「我们也改过、上游也改了」的文件做三方合并
- 重点：ExtensionProvider / PacketTunnelProvider / CommandClient / App / ConfigStore / project.yml
- 保留我们自己的改动：App Group 探测、Canto 桥、文件通道（hello/diagnostics）、构建标识、连接流优化、UI 导航

**P3 验证（1 天）**
- CI 编译 + CantoAgentKit 单测
- 真机冒烟：VPN 连接、连接列表、节点/配置、文件通道、Canto 配对
- 帧日志：`home.snapshot` 不劣化（基线 18–222）
- 模块验证：装 1 个 Surge `.sgmodule` + 1 个 Loon `.lpx`，确认规则/重写/脚本生效

## 4. 风险与对策

| 风险 | 对策 |
|---|---|
| 上游 Module 依赖我们缺失的新架构（ProviderMaterializer 等） | 闭包已包含；P1 先编译，暴露缺失项再补 |
| 改名变换误伤（字符串里的 UI 文案、URL scheme） | 脚本白名单 + 人工复核 diff；CI 兜底 |
| 与我们文件通道改动冲突（CommandClient/ExtensionProvider） | 三方合并时以「我们的兜底逻辑 + 上游新结构」为准，逐处复核 |
| 内存增长（AdBlock + Module 在扩展内） | 保留 `ModuleMemoryLadder`；上线前看 fp 峰值（当前 24MiB/50MiB） |
| 一次搬太多无法定位回归 | 按 P1/P2 小步提交，每步 CI 绿再继续 |

## 5. 回滚

- 同步全程在新分支 `sync/upstream-module-20261022`
- 出问题回到 tag `pre-upstream-sync-20261022`
- 不合并 `diag/ipc-channel-evidence`（文件通道）分支的既有改动会先合入同步分支，避免二次冲突
