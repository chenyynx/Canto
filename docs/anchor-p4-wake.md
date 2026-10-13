# P4 · 后台可达（Wake Gateway + APNs + 挂起队列）

> 目标：App 不在前台时，agent 的命令也能到达并执行（「接近零操作」= 里程碑 M3）。
> 状态：代码全量交付；**端到端唤醒需真机 + 发布方 APNs 密钥验证**。

## 1. 组件与数据流

```
agent (Claude Code / MCP)
   │  ① 下命令
   ▼
daemon ── 设备不在线？──► WakeClient ──② HMAC 签名请求──► Wake Gateway
   │                                                        │ ③ APNs 静默推送
   │                                                        ▼
   │                                              iPhone 被拉起 ~30s
   │                                                        │ ④ 重连 + hello(token 上报)
   ▼◄──────────────── ⑤ hello → 补发队列命令 ───────────────┘
```

| 组件 | 位置 | 说明 |
|---|---|---|
| WakeClient | `src/daemon/wake.ts` | HMAC-SHA256(ts.body) 签名、60s 限频、网关不可达时静默降级 |
| Wake Gateway | `gateway/wake-gateway.ts` | 无状态：请求即转发，不存设备/业务数据 |
| 挂起队列 | `src/daemon/queue.ts` | 离线命令留在队列，设备 hello 时 `flush` 补发 |
| deferred 语义 | `src/daemon/sessions.ts` | 设备回「已接受未生效」→ 命令重排回队列（上限 5 次转 rejected） |
| APNs 注册 | `HakoClient/Sources/AgentBridge/AnchorPushService.swift` | provisional 授权 → 注册 → token 存 App Group → hello 上报 |
| 唤醒响应 | `AnchorBridgeController.wakeAndResync()` | 静默推送拉起 → 补连 daemon → hello 自动补发 |
| On-Demand | 上游 `OnDemandSettings`（App 内设置页） | 系统级兜底；Anchor 只读暴露于 `app.state.get.on_demand`，不新增规则 |

## 2. 启动 Gateway

前置（发布方持有，一次性）：

1. Apple Developer 账号 → Keys → 新建 APNs Key（勾选 Apple Push Notifications service）
   - 下载 `.p8`（只能下一次），记下 **Key ID**（10 位）与 **Team ID**
2. App 的 bundle id = APNs topic（默认 `org.example.hako`；自编译改过 bundle id 时，
   daemon 侧 `apns.topic` 会随 hello 上报，Gateway 按请求里的 topic 发送）

启动：

```bash
export ANCHOR_WAKE_SECRET='<与 daemon 共享的随机串>'
export APNS_KEY_P8="$(cat AuthKey_XXXXXXXXXX.p8)"
export APNS_KEY_ID='XXXXXXXXXX'
export APNS_TEAM_ID='YYYYYYYYYY'
export ANCHOR_APNS_TOPIC='org.example.hako'
export APNS_ENV='prod'          # 开发/TestFlight 用 sandbox
export PORT=8787
npx tsx gateway/wake-gateway.ts
```

健康检查：`curl http://127.0.0.1:8787/health` → `ok`

systemd 单元素示例：

```ini
[Unit]
Description=Anchor Wake Gateway
After=network.target

[Service]
EnvironmentFile=/etc/anchor-wake.env
ExecStart=/usr/bin/npx tsx /opt/anchor/gateway/wake-gateway.ts
Restart=always

[Install]
WantedBy=multi-user.target
```

## 3. 配置 daemon

daemon 侧开启唤醒（`DaemonOptions.wake`，经 CLI/MCP 装配传入）：

```jsonc
{
  "agentId": "agent_xxx",              // 本机 agent 身份
  "wake": {
    "gatewayUrl": "https://wake.example.com",
    "secret": "<与 Gateway 同值>"       // 或环境变量 ANCHOR_WAKE_SECRET
  }
}
```

未配置 `wake` → 唤醒为 no-op（设备仍在前台可达；命令留在队列等下次 hello）。

## 4. 请求协议（自定义 Gateway 时对照）

```http
POST /v1/wake
x-anchor-ts: 1760000000                       # unix 秒，±300s 有效
x-anchor-sig: <hex HMAC-SHA256(ts + "." + rawBody)>
content-type: application/json

{"dev_id":"dev_xxx","agent_id":"agent_xxx","token":"<APNs hex token>","apns_topic":"org.example.hako"}
```

响应：`200 ok` / `401 bad signature` / `429 rate limited` / APNs 错误码原样透传。

APNs 侧请求要素（Gateway 已实现）：

| 字段 | 值 | 说明 |
|---|---|---|
| `apns-push-type` | `background` | 静默推送必须 |
| `apns-priority` | `5` | **必须 5**；写 10 会被 APNs 直接拒 |
| `apns-topic` | bundle id | 由请求方指定或默认 |
| `apns-expiration` | `0` | 设备不在线就丢弃（醒来后 hello 补发，无需重放） |
| payload | `{"aps":{"content-available":1},"anchor":{"dev":"…","reason":"wake"}}` | **不含业务数据** |

## 5. 安全边界（如实说明）

- **Gateway 不存任何数据**：无设备表、无配对表、无命令内容。伪造唤醒最多浪费一次推送。
- 命令面安全由 **Noise 会话层**把守：只有配对 agent 的握手能通过，唤醒本身不产生权限。
- 限频 60s/设备（内存 LRU），且 APNs 自身对静默推送有节流。
- 未配对设备即使被唤醒，也会被 daemon 以 `bye: unpaired` 拒绝。
- ⚠️ **免签名侧载**（无开发者账号推送能力）：`registerForRemoteNotifications` 会失败，
  App 记 warning 并降级为**前台可达**（P2 行为）——其余功能不受影响。

## 6. 验收清单

| 层 | 项 | 状态 |
|---|---|---|
| 单测 | Wake 签名/限频/降级（4 条） | ✅ CI |
| 单测 | 挂起队列 + deferred 重排/超限（5 条） | ✅ CI |
| 单测 | 消息 codec 鉴权（7 条，P3） | ✅ CI |
| 真机 | 配对 + 扫码（P2 遗留） | ⬜ 待 pp |
| 真机 | 后台静默推送拉起 App（需付费开发者账号 + .p8） | ⬜ 待 pp |
| 真机 | 端到端：agent 下命令 → 手机锁屏 → 命令被执行 | ⬜ 待 pp |

## 7. 排障

| 症状 | 检查 |
|---|---|
| Gateway 401 | daemon 与 Gateway 的 `ANCHOR_WAKE_SECRET` 是否一致；系统时间是否偏差 >5min |
| Gateway 429 | 同设备 60s 内重复唤醒（限频正常行为） |
| APNs 400 `BadDeviceToken` | token 与环境不匹配（sandbox token 发到 prod）；用 `APNS_ENV=sandbox` 复测 |
| APNs 403 `InvalidProviderToken` | `.p8`/Key ID/Team ID 不匹配，或 P8 换行被吞（支持 `\n` 转义或真实换行） |
| 推送发出但 App 没动 | iOS 后台刷新是否被用户关闭（设置→通用→后台 App 刷新）；低电量模式会压制静默推送 |
| 设备一直显示离线 | 隧道/App 均未运行；确认 hello 里带上了 `apns.token`（日志 `anchor push: registered token …`） |
