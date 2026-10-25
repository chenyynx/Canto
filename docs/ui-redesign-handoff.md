# Canto UI 改造交接（2026-10-25）

## 1. 一句话状态

上游全量同步已完成、CI 绿、IPA 已出；**P4 真机还有 3 项待确认**；下一步是 UI 改造，但**开工前先产出「现有功能清单」给 pp**。

## 2. 仓库与分支

- 工作副本：`/data/canto/Canto`（2026-10-25 本地目录已迁移并改名为 Canto）
- 分支：`sync/upstream-full-20261024`（全量同步工作分支），工作区应保持干净
- 回滚：tag `pre-sync-20261024`（c7a63dc）
- 仓库（均公开）：
  - `chenyynx/Canto`（App）
  - `chenyynx/Canto-Core`（内核镜像，非 fork）
  - `chenyynx/Canto-Adapter`（适配层镜像，非 fork）
  - `chenyynx/Canto-Agent`
- pin：kernel `d1aff39`，adapter `bdf40d4`（`Dependencies.lock.json`，已指向自有镜像）

## 3. CI / 出包现状

- `ci.yml`：Debug 编译门禁，缓存命中整轮 **194s（3.2 分钟）**；缓存 1.3GB
- `unsigned-ipa.yml`：Release 真机出包，产物 `Canto-unsigned-ipa`（约 56MB）
- Xcode 26.6 适配（runner 没有 27）：
  - Go 1.26.10
  - `buildIf` 条件移进 ToolbarItem（iOS 15 部署目标）
  - `ICloudEntitlementProbe` 改 public
  - 真机打包关闭 explicit modules，且不逐 target 编 `ClashiOSExtension`

## 4. P4 真机待确认（3 项）

1. 首页 **Canto 卡片**是否出现，点进去能否进配对
2. 导入一个 Surge `.sgmodule` 或 Loon `.lpx`，规则/重写是否生效
3. 扩展内存稳态 <35MiB，挂 2 小时不被 jetsam 杀

重签要求：`group.org.example.canto`；bundle 前缀 `org.example.canto`；旧安装/旧配对失效，需干净重装。

## 5. 下一步（按顺序）

1. **多子代理并行产出功能清单** → 汇总成 `docs/feature-inventory.md` → **先给 pp**
2. pp 确认清单与 UI 三个决策后，开 `feat/ui-redesign` 分支
3. 概念图 → tokens → 实现 → 审查打磨

### 5.1 功能清单的子代理分工（并行）

| 子代理 | 范围 |
|---|---|
| A | 首页/仪表盘/概览：GoldenFlowHomeView、ClashHomeView、CantoHomeCard、流量/延迟/运行状态 |
| B | 连接/请求/流量明细：ConnectionsView、RequestsView、实时数据流 |
| C | 配置/订阅/策略组/规则：ConfigUI、ConfigurationEditorViews、策略切换、规则预览 |
| D | 日志/诊断/活动：LogsView、诊断导出、运行日志 |
| E | 设置/系统集成：设置页、通知、URL scheme、iCloud 备份、快捷指令/小组件 |
| F | Canto/Agent 子系统：配对、桥接、命令执行、APNs 唤醒 |
| G | 内核能力面：TUN/DNS/规则/重写/脚本/MITM/模块格式（有内核能力但无 UI 的也要列） |
| H | UI 主题与组件：ClashTheme、ClashSymbol、导航结构、可访问性、本地化 |

每条统一格式：**功能名 / 用户入口 / 代码位置 / 实现状态（可用｜半成品｜仅内核无 UI）/ 备注**。

### 5.2 UI 三个待定决策（pp 未定）

- 范围：全局重做 / 只重做视觉层 / 只换 Logo + 首页
- 风格参考：Loon 极简白 / Surge 专业深色 / 提供截图做风格蒸馏
- Logo：继续用 moro（临时占位）还是做 Canto 字标

### 5.3 可用的设计类 skill

`swiftui-pro`（SwiftUI 实现审查）、`ui-ux-pro-max`（风格/配色/字体/UX 规则库）、`design-system`（token 体系）、`impeccable`（产品 UI 打磨）、`redesign-existing-projects`（现有界面重做）、`imagegen-frontend-mobile`（概念图）、`visual-style-distill` + `use-style`（参考图风格蒸馏）、`brandkit`/`design`（品牌/字标）。

## 6. 关键路径

- App 入口：`/data/canto/Canto/apple/ClashClient/Sources/ClashClientApp.swift`
- 首页：`apple/ClashClient/Sources/ConfigUI/GoldenFlowHomeView.swift`、`apple/ClashClientUI/Sources/ClashClientUI/Features/Home/ClashHomeView.swift`
- Canto 卡：`apple/ClashClientUI/Sources/ClashClientUI/Features/Canto/CantoHomeCard.swift`
- 主题/图标：`apple/ClashClientUI/Sources/ClashClientUI/ClashTheme.swift`、`ClashSymbol`
- 任务单：`docs/upstream-full-sync-task-sheet.md`

## 7. 约束

- 不 push main、不合并、不改远端共享状态；分支和裸提交不打扰
- 提交信息 Conventional Commits，不带 `[cc]`，末尾 `Co-Authored-By: Claude Code <noreply@anthropic.com>`
- token 不写进仓库/记忆/输出
- 面向用户的叙述全中文；文件路径给完整绝对路径
- 先清单、后设计、再动代码；UI 改造单独分支 `feat/ui-redesign`

## 8. 新会话提示词（直接粘贴）

```
读 /data/canto/Canto/docs/ui-redesign-handoff.md 和 /data/canto/Canto/docs/upstream-full-sync-task-sheet.md。

任务：先派多个子代理并行审查客户端现有功能，产出功能清单 docs/feature-inventory.md，把清单给我确认；**先不要改 UI 代码**。

子代理按域拆分：首页仪表盘、连接/请求、配置/订阅/策略、日志/诊断、设置/系统集成、Canto/Agent、内核能力面、UI 主题与组件。
每条统一格式：功能名 / 用户入口 / 代码位置 / 实现状态（可用｜半成品｜仅内核无 UI）/ 备注。

约束：工作副本 /data/canto/Canto，分支 sync/upstream-full-20261024，工作区保持干净；不 push main、不合并；不写 token。
```
