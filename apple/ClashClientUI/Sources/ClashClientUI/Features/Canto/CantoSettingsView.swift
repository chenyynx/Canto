import Foundation
import SwiftUI

// MARK: - 设置/管理页

/// 已配对 Agent 的管理页：身份信息 / 断开忘记 / 最近操作记录。
///
/// 数据：CantoBridgeObservable（phase、agentID、recentActivity、forgetPairing）
/// + 宿主汇总的 CantoAgentProfile（id / 名称 / 指纹 / endpoint）。
public struct CantoSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var proxy: CantoBridgeProxy
    private var bridge: any CantoBridgeObservable { proxy.bridge }
    private let profile: CantoAgentProfile
    private let palette: ClashClientUI.ClashProductPalette
    /// 忘记配对完成后的回调（宿主可借此返回首页；默认 dismiss 当前页）。
    private let onForget: (() -> Void)?

    @State private var confirmsForget = false
    @State private var isForgetting = false

    /// 列表一次显示多少条操作记录。
    private static let activityLimit = 20

    public init(
        proxy: CantoBridgeProxy,
        profile: CantoAgentProfile,
        palette: ClashClientUI.ClashProductPalette,
        onForget: (() -> Void)? = nil
    ) {
        self.proxy = proxy
        self.profile = profile
        self.palette = palette
        self.onForget = onForget
    }

    public var body: some View {
        CantoPageScaffold(
            palette: palette,
            accessibilityIdentifier: "canto.settings.root"
        ) {
            agentSection
            undoSection
            forgetSection
            activitySection
        }
        .navigationTitle(Text(clash: .copy("Agent 管理")))
        .confirmationDialog(
            Text(clash: .copy("断开并忘记配对？")),
            isPresented: $confirmsForget,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                forgetPairing()
            } label: {
                Text(clash: .copy("断开并忘记"))
            }
            Button(role: .cancel) {
                confirmsForget = false
            } label: {
                Text(clash: .copy("取消"))
            }
        } message: {
            Text(
                clash: .copy(
                    "本机保存的 Agent 身份与端点会被清除，之后需要重新扫码或粘贴口令配对。"
                )
            )
        }
    }

    // MARK: 身份信息

    private var agentSection: some View {
        ClashClientUI.ClashProductGroup("已配对 Agent", palette: palette) {
            if hasIdentity {
                VStack(spacing: ClashClientUI.ClashTheme.Spacing.row) {
                    CantoValueRow(
                        title: "名称",
                        value: profile.displayName,
                        symbol: .serverRack,
                        monospaced: false
                    )
                    CantoValueRow(
                        title: "Agent ID",
                        value: profile.displayID,
                        symbol: .key
                    )
                    CantoValueRow(
                        title: "指纹",
                        value: profile.displayFingerprint,
                        symbol: .shieldLefthalfFilled
                    )
                    CantoValueRow(
                        title: "端点",
                        value: profile.displayEndpoint,
                        symbol: .network
                    )
                    CantoValueRow(
                        title: "会话",
                        value: CantoPhaseCopy.statusLine(bridge.phase),
                        symbol: .arrowTriangle2Circlepath,
                        monospaced: false,
                        selectable: false
                    )
                }
            } else {
                ClashClientUI.ClashCardEmptyState(
                    title: "还没有配对任何 Agent",
                    message: "回到首页点「连接 Agent」，扫码或粘贴配对口令即可。",
                    icon: { CantoSymbolImage(symbol: .rectangleStack) }
                )
            }
        }
    }

    private var hasIdentity: Bool {
        profile.agentID != nil || profile.endpoint != nil || bridge.isPaired
    }

    // MARK: 断开 / 忘记

    private var forgetSection: some View {
        ClashClientUI.ClashProductGroup(
            footer: .copy("忘记配对只清除本机保存的 Agent 身份；设备私钥保留，重装后仍是同一台手机。"),
            palette: palette
        ) {
            Button(role: .destructive) {
                confirmsForget = true
            } label: {
                Label {
                    Text(clash: .copy("断开并忘记配对"))
                        .frame(maxWidth: .infinity)
                } icon: {
                    CantoSymbolImage(symbol: .xmarkCircle)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isForgetting || (!bridge.isPaired && !hasIdentity))
            .accessibilityIdentifier("canto.settings.forget")
        }
    }

    private func forgetPairing() {
        isForgetting = true
        Task {
            await bridge.forgetPairing()
            isForgetting = false
            if let onForget {
                onForget()
            } else {
                dismiss()
            }
        }
    }

    // MARK: 最近操作

    /// P3：有待确认的配置 apply 时显示一键撤销（回滚到 apply 前的快照）。
    @State private var isUndoing = false
    @State private var undoError: String?

    private var undoSection: some View {
        Group {
            if bridge.hasPendingConfigApply {
                ClashClientUI.ClashProductGroup(
                    footer: .copy("Agent 刚下发的配置还在确认窗口内；撤销立即回滚到改动前的状态。"),
                    palette: palette
                ) {
                    Button {
                        isUndoing = true
                        Task {
                            defer { isUndoing = false }
                            do {
                                try await bridge.undoLastConfigApply()
                                undoError = nil
                            } catch {
                                undoError = error.localizedDescription
                            }
                        }
                    } label: {
                        Label {
                            Text(clash: .copy("撤销最近一次配置改动"))
                                .frame(maxWidth: .infinity)
                        } icon: {
                            CantoSymbolImage(symbol: .arrowUturnBackward)
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(isUndoing)
                    .accessibilityIdentifier("canto.settings.undo")
                    if let undoError {
                        Text(clash: .copy(undoError))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var activitySection: some View {
        ClashClientUI.ClashProductGroup(
            "最近操作",
            footer: .copy("Agent 通过本机执行过的命令；最多保留最近 200 条。"),
            palette: palette
        ) {
            if visibleActivity.isEmpty {
                ClashClientUI.ClashCardEmptyState(
                    title: "还没有操作记录",
                    message: "Agent 执行过的命令会显示在这里。",
                    icon: { CantoSymbolImage(symbol: .clock) }
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleActivity) { entry in
                        CantoActivityRow(entry: entry, palette: palette)
                        if entry.id != visibleActivity.last?.id {
                            ClashClientUI.ClashRowDivider()
                        }
                    }
                }
            }
        }
    }

    private var visibleActivity: [CantoActivityEntry] {
        Array(bridge.recentActivity.prefix(Self.activityLimit))
    }
}

// MARK: - 操作记录行

/// 一条操作记录：中文动作标题 + 相对时间 + 状态徽标。
struct CantoActivityRow: View {
    @Environment(\.locale) private var locale

    let entry: CantoActivityEntry
    let palette: ClashClientUI.ClashProductPalette

    var body: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: ClashClientUI.ClashTheme.Spacing.row
        ) {
            VStack(
                alignment: .leading,
                spacing: ClashClientUI.ClashTheme.Spacing.tight
            ) {
                Text(clash: .copy(CantoActivityPresentation.title(for: entry.op)))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    verbatim: CantoActivityPresentation.relativeTime(
                        entry.at,
                        locale: locale
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: ClashClientUI.ClashTheme.Spacing.compact)

            ClashClientUI.ClashStatusBadge(
                title: CantoActivityPresentation.statusLine(entry.status),
                tint: CantoActivityPresentation.statusTint(entry.status),
                role: .status,
                categoryFill: palette.raisedFill,
                requirementFill: palette.surface,
                separator: palette.separator
            )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: ClashClientUI.ClashTheme.Control.pointerRowTarget,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("canto.settings.activity.\(entry.id)")
    }
}

#if DEBUG
#Preview("Agent 管理 · 已配对") {
    CantoSettingsView(
        proxy: CantoBridgeProxy(CantoPreviewBridge(
            phase: .connected,
            isPaired: true,
            agentID: "4N7Q2W8Z0R5TVK9Y",
            recentActivity: cantoPreviewActivity([
                ("core.proxy.select", -180, "applied"),
                ("core.provider.update", -2400, "applied"),
                ("core.config.reload", -5400, "deferred"),
                ("core.conn.close", -7200, "rejected"),
                ("app.subscription.update", -86400, "applied"),
            ])
        )),
        profile: cantoPreviewProfile,
        palette: .cantoPreview
    )
}

#Preview("Agent 管理 · 未配对") {
    CantoSettingsView(
        proxy: CantoBridgeProxy(CantoPreviewBridge()),
        profile: CantoAgentProfile(),
        palette: .cantoPreview
    )
}
#endif
