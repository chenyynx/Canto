# 上游全量同步任务单（Clash-Client 3b8ea95 → 本仓）

- 日期：2026-10-24
- 级别：L（跨模块 / 构建链 / pin）
- 状态：P0–P3 完成（CI 绿 run 40114363290，缓存已建 1.3GB）；P4 真机、P5 UI 改造待执行
- 回滚：tag `pre-sync-20261024`（c7a63dc）；分支 `diag/ipc-channel-evidence`

## 1. 目标与边界

- 以 `ProjectClash/Clash-Client@3b8ea95` 为树基座全量导入。
- 保留本地改动：P0 文件通道/IPC 修复、Agent/Canto、CI、构建标识、连接流优化。
- 品牌层已完成：产品名 Canto，Hako/Anchor 功能名全部清掉；上游 `Clash*` 内部代码名保留。
- 不做全局 Clash→Canto 改名；内部保留 upstream 的 `Clash*` 命名，避免每次同步重跑改名。

## 2. 上游事实（2026-10-24 实测）

- App：`ProjectClash/Clash-Client@3b8ea95`（2026-10-21）；相对基线 `3e93b98` 18 commits / 389 files / +108,155 −6,034。
- Kernel：`ProjectClash/Clash`，App pin `a5cb38d`；main `d1aff39`（2026-10-23）含 mihomo v1.19.33、CVE-2026-97031、dns-mode、配置解析性能。候选 pin `d1aff39`，不兼容回退 `a5cb38d`。
- Adapter：`ProjectClash/Clash-Adapter`，App pin `821b6e4`；main `bdf40d4`（docs-only）。
- 构建：`scripts/bootstrap.py` 按 pin 克隆 kernel/adapter，`make lib_apple` 生成 `Clash.xcframework`；adapter vendor 到 `Vendor/ClashAdapter`。
- 许可证：App / Kernel / Adapter 均 GPL-3.0；闭源分发在 100% 替换前不成立。

## 3. 分支与回滚

- tag：`pre-sync-20261024` @ `c7a63dc`
- 工作分支：`sync/upstream-full-20261024`（从 `diag/ipc-channel-evidence` 开）
- 回滚：`git switch diag/ipc-channel-evidence` 或 `git switch pre-sync-20261024`

## 4. 阶段

- P0（完成）：tag / 分支 / 任务单 / 上游树导出。
- P1（完成）：导入上游树 `chore: import upstream 3b8ea95`（dfba835）。
- P2（完成）：重放本地改动：
  - 新增文件：Agent/Canto（约 6.8k 行）、`CantoAgentKit`、CI workflow。
  - 共享 UI：`ClashClientApp`、`GoldenFlowHomeView`、`ConnectionsView`、`RequestsView`、`LogsView`、`AppleClientActions`、`ClashTheme`。
  - 集成点：`ExtensionProvider`、`PacketTunnelProvider`、`ClashCommandClient`、`project.yml`；P2c 提交 `6aa24aa`。
- P3（完成）：pin `d1aff39` / `bdf40d4`；镜像已切到公开仓 `chenyynx/Canto-Core` / `Canto-Adapter`（本地 mirror clone + push，非 fork，SHA 保留）；CI 绿 run 40114363290（commit 54442c7）。runner 只有 Xcode 26.6（上游 README 要求 27），据此做了三处适配：Go 1.26.10、`buildIf` 条件移进 ToolbarItem、`ICloudEntitlementProbe` 改 public。
- P4（待执行）：真机冒烟 + 模块测试（Surge `.sgmodule` / Loon `.lpx` / QX module）。
- P5（部分完成）：Canto 显示名 / bundle / App Group / URL scheme 已改，外部仓库已改名；待真机复测签名与 App Group。

## 5. 冲突清单（本地 vs 上游）

- 真冲突：`ClashClientApp.swift`（上游 +210/−7 vs 本地 +41）、`GoldenFlowHomeView.swift`（上游 +578/−336 vs 本地 28）、`project.yml`（上游 +79/−2 vs 本地 CantoAgentKit target）。
- 小改：`LogsView.swift`（上游 +4 vs 本地 +3）、`AppleClientActions.swift`（上游 +13 vs 本地 +1）。
- 上游未改：`RequestsView.swift`、`ConnectionsView.swift`。
- 集成热点：`ExtensionProvider`、`PacketTunnelProvider`、`ClashCommandClient`、`ConfigStore`。

## 6. 验收

- CI：`ci.yml` 编译 + `CantoAgentKit` 单测；`unsigned-ipa.yml` 出包。
- 真机：VPN 连接、连接列表、策略切换、App Group 文件通道 hello/diagnostics、Canto 配对。
- 模块：装 1 个 Surge `.sgmodule` + 1 个 Loon `.lpx` + 1 个 QX module，确认规则/重写/脚本生效。
- 内存：扩展 footprint 稳态 < 35MiB；连续 2 小时不因 jetsam 重启。

## 7. 未决

- 产品名：Canto（已定，品牌层已完成）。
- Kernel pin：当前 `d1aff39` / `bdf40d4`，CI 已验证；回退备选 `a5cb38d`。
- 镜像策略（已落地）：`chenyynx/Canto`（App）/ `Canto-Core`（内核镜像）/ `Canto-Adapter`（适配层镜像），均为公开仓、非 fork。旧 `*-Legacy` 私有仓与临时 fork 仓待清理。
