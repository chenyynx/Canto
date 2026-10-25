# Canto UI 改造任务单（2026-10-25）

- 状态：布局与概念图已由 pp 确认；待批准后开 `feat/ui-redesign`
- 工作副本：`/data/canto/Canto`（分支 `sync/upstream-full-20261024`，工作区干净）
- 设计参考：Loon 3.5.2 真机截图 + `/data/canto/reverse/loon/loon-ui-analysis.md`
- 概念图：`/data/canto/reverse/loon/concepts/loon-dashboard.png`、`loon-policy.png`、`loon-config.png`
- 本文档只覆盖 UI 改造；24 项半成品的逻辑修复不在本轮范围

## 1. 已确认的决定

1. **4 个一级 Tab**：仪表 / 策略 / 配置 / 更多
2. **连接/请求放仪表**，不单独占 Tab
3. **布局照 Loon**：白底、白色卡片、2 列快捷方式、列表；不做彩色大砖、线纹、衬线
4. **快捷方式初始 6 个**，用户可通过「编辑」增删、排序、恢复默认
5. **浅色为主**，深色模式作为完整第二主题（跟随系统）
6. **业务逻辑冻结**：只动表现层与导航；不修 Canto 接线/APNs/URL scheme 等半成品

## 2. 信息架构

### 仪表
- 顶部：`CANTO` 字标 + 连接开关；副行「规则模式 ▾」切换出站模式
- 双流量卡：上传（绿）、下载（蓝紫），实时速率 + 累计
- 快捷方式：2 列白卡，初始 6 个：
  1. 节点
  2. 请求记录
  3. DNS 记录
  4. 配置文件
  5. 模块
  6. 网络共享
- 右上「编辑」：进入快捷方式编辑页
- 不放实时连接长列表；连接/请求通过「请求记录」快捷方式进入

> 术语修正：Loon 的「插件 + 模块」在 Canto 合并为「模块」（重写/脚本/MITM 都在模块里）。概念图中的「插件/模块」是 Loon 术语占位，实现时只保留「模块」，脚本作为模块子项。

### 策略
- 标题「策略」+ 右上「⋯」
- 策略组列表：白卡、左侧图标、组名、当前节点/延迟、右侧 `select` + chevron
- 点击行为复用现有策略组切换逻辑；不改数据源

### 配置（Loon 式长列表）
- 标题「配置」+ 右上「⋯」
- 分节标题 + 白色分组行，整页纵向滚动：
  - 节点：所有节点 / 筛选节点 / 代理链
  - 规则：规则总览 / 规则集
  - 模块：模块列表
  - 复写：所有模块里的复写聚合
  - 脚本：所有模块脚本 + 配置覆写脚本聚合
  - MitM：解密域名 / MitM 配置
  - DNS：DNS 服务器 / 域名、IP、协议栈映射
  - 文件：快速编辑 / 所有配置文件 / 示例模板 / 外部资源
  - 其他：高级配置 / Apple TV / 外部控制器
- 复写/脚本/MitM 在 UI 上是顶层入口，方便找到；数据仍来自模块，不新增独立数据模型。
- 全部复用现有页面与逻辑；只换容器和行样式

### 更多
- 标题「更多」
- 分组：
  - 连接：VPN / 按需连接 / 客户端设置 / 外部控制器
  - 外观与数据：外观 / 存储 / 备份与恢复 / Geo 资源
  - 工具：网络质量 / STUN & NAT / DNS 查询 / LAN 分享 / 运行时诊断 / 诊断收件箱 / 日志
  - 关于：版本 / 许可 / 开源声明
- 低频入口集中在这里，不再嵌套「客户端设置 → 外部控制器」

## 3. 视觉规范

- 页面底：`#F2F4F7`；卡片：`#FFFFFF`；主文字：`#101217`；次文字：`#8A8F98`；分隔线：`#EDEFF2`
- 强调色：`#2F6BFF`；成功：`#34C759`；警告：`#FF9F0A`；错误：`#FF3B30`
- 字体：SF Pro / PingFang SC / Noto Sans CJK；数字用等宽（流量、延迟、连接数）
- 字号：标题 32/22/18/17；正文 16/14；辅助 12/10
- 圆角：大卡 18、列表组 18、按钮 14、胶囊 999
- 阴影：`0 2px 10px rgba(18,24,40,.035)`，不用重阴影
- 图标：SF Symbols 为主 + 少量自绘；彩色图标只用于快捷方式/策略行的小图标底
- 动效：Tab 选中胶囊、按压缩放、连接成功触感；不做装饰动画
- 深色：石墨黑底 + 抬升卡片，强调色提亮；不纯黑

## 4. 快捷方式（本轮唯一新增的状态）

### 类型
`CantoShortcut` 枚举，至少包含：
- `nodes` 节点
- `requests` 请求记录
- `dnsRecords` DNS 记录
- `profiles` 配置文件
- `modules` 模块
- `lanShare` 网络共享
- `rules` 规则
- `scripts` 脚本
- `cantoAgent` Canto Agent
- `diagnostics` 诊断

### 默认值
`[nodes, requests, dnsRecords, profiles, modules, lanShare]`

### 规则
- 最少 1 个，最多 8 个
- 「编辑」页支持勾选/取消、拖动排序、恢复默认
- 持久化：`UserDefaults` key `canto.home.shortcuts.v1`，存 raw string 数组
- 读取时过滤未知 raw、去重、补齐默认；不因脏数据崩溃
- 保留旧 `home.favorite.cards.v3` 不动，便于回滚；不做自动迁移
- 编辑页是 sheet，不改变现有导航

## 5. 实现顺序

1. **设计 token + 基础组件**
   - `CantoTheme`（颜色/字号/间距/圆角）
   - `CantoCard`、`CantoSectionHeader`、`CantoListRow`、`CantoToggle`、`CantoTrafficTile`、`CantoShortcutCard`、`CantoTabBar`、`CantoEmptyState`
2. **壳与导航**
   - 4 Tab；iPhone 底部、iPad/Mac 侧栏
   - 路由映射、深链、快捷指令/小组件入口同步
   - 保留现有 sheet 行为（配置编辑、模块、诊断等）
3. **仪表**
   - 复用 `ClashHomeSnapshot` / `ClashTrafficFeed` / `StatsModel`
   - 新布局；快捷方式模型 + 编辑页
4. **策略**
   - 复用 `NodesModel` / 策略组数据；只换行与容器
5. **配置**
   - 复用 `Profiles` / `ConfigStore` / `Module` / `Rules` 页面；新入口分组
6. **更多**
   - 复用 `More` / `Utilities` 页面；新分组
7. **收尾**
   - 深色模式、动态字号、VoiceOver、中英繁
   - 截图对比（iPhone/iPad/Mac）
   - CI 构建 + 手工回归

## 6. 文件范围（预估）

- 新增：`apple/ClashClientUI/Sources/ClashClientUI/Design/CantoTheme.swift`
- 新增：`apple/ClashClientUI/Sources/ClashClientUI/Components/Canto*.swift`
- 新增：`apple/ClashClientUI/Sources/ClashClientUI/Features/Home/CantoShortcut.swift`、`CantoShortcutsEditor.swift`
- 修改：`ClashClientApp.swift`（Tab/路由）、`AppNavigation.swift`、`ClashPresentationPolicy.swift`
- 修改：`Features/Home/ClashHomeView.swift`、`ClashHomeSnapshot.swift`、`ConfigUI/GoldenFlowHomeView.swift`
- 修改：`Features/Proxies/ClashProxiesView.swift`、`Features/Profiles/*`、`Features/Module/*`、`Features/Rules/*`、`Features/More/*`、`Features/Utilities/*`
- 不修改：VPNController、PacketTunnelProvider、ConfigStore、ConnectionsModel、Canto 协议/APNs、内核桥接

## 7. 验收标准

- 4 个 Tab 可切换；仪表/策略/配置/更多入口完整
- 仪表初始 6 个快捷方式；编辑页可增删/排序/恢复默认；重启后保持
- 连接/断开、出站模式切换、策略组切换、配置激活、各快捷方式跳转行为与改造前一致
- 浅色/深色、动态字号、VoiceOver、中文/英文/繁體可用
- iPhone/iPad/Mac 无标题裁切、无内容被 Tab 栏遮挡
- CI 构建通过；无新增业务逻辑回归
- 工作区干净；不 push main、不合并

## 8. 不做 / 风险

**不做**
- 不修 24 项半成品（Canto 接线、APNs、URL scheme、已连接时长等）
- 不新增功能；不改数据契约
- 不复制 Loon 代码/图标/插画

**风险**
- `ClashHomeView.swift` 约 2455 行，需先拆视图再改，避免回归
- 导航改动会影响深链、快捷指令、小组件、无障碍标识，需逐项核对
- 快捷方式持久化是唯一新增状态，必须有单测覆盖默认值/脏数据/排序
- 半成品入口在新 UI 中要隐藏或明确空态，不能做成“看起来能用”
- 深色模式与动态字号需要逐页检查，不能只做浅色截图
