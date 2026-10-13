import Foundation
import SwiftUI

// MARK: - 设置/管理页

/// 已配对 Agent 的管理页：身份信息 / 断开忘记 / 最近操作记录。
///
/// 数据：AnchorBridgeObservable（phase、agentID、recentActivity、forgetPairing）
/// + 宿主汇总的 AnchorAgentProfile（id / 名称 / 指纹 / endpoint）。
public struct AnchorSettingsView<Bridge: AnchorBridgeObservable>: View {
    @Environment(\.dismiss) private var dismiss

    /// 用泛型约束而非 `any AnchorBridgeObservable`：ObservableObject 带关联类型，
    /// 存在类型不满足 `@ObservedObject` 的具体类型要求。
    @ObservedObject private var bridge: Bridge
    private let profile: AnchorAgentProfile
    private let palette: HakoClientUI.HakoProductPalette
    /// 忘记配对完成后的回调（宿主可借此返回首页；默认 dismiss 当前页）。
    private let onForget: (() -> Void)?

    @State private var confirmsForget = false
    @State private var isForgetting = false

    /// 列表一次显示多少条操作记录。
    private static let activityLimit = 20

    public init(
        bridge: Bridge,
        profile: AnchorAgentProfile,
        palette: HakoClientUI.HakoProductPalette,
        onForget: (() -> Void)? = nil
    ) {
        self.bridge = bridge
        self.profile = profile
        self.palette = palette
        self.onForget = onForget
    }

    public var body: some View {
        AnchorPageScaffold(
            palette: palette,
            accessibilityIdentifier: "anchor.settings.root"
        ) {
            agentSection
            forgetSection
            activitySection
        }
        .navigationTitle(Text(hako: .copy("Agent 管理")))
        .confirmationDialog(
            Text(hako: .copy("断开并忘记配对？")),
            isPresented: $confirmsForget,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                forgetPairing()
            } label: {
                Text(hako: .copy("断开并忘记"))
            }
            Button(role: .cancel) {
                confirmsForget = false
            } label: {
                Text(hako: .copy("取消"))
            }
        } message: {
            Text(
                hako: .copy(
                    "本机保存的 Agent 身份与端点会被清除，之后需要重新扫码或粘贴口令配对。"
                )
            )
        }
    }

    // MARK: 身份信息

    private var agentSection: some View {
        HakoClientUI.HakoProductGroup("已配对 Agent", palette: palette) {
            if hasIdentity {
                VStack(spacing: HakoClientUI.HakoTheme.Spacing.row) {
                    AnchorValueRow(
                        title: "名称",
                        value: profile.displayName,
                        symbol: .serverRack,
                        monospaced: false
                    )
                    AnchorValueRow(
                        title: "Agent ID",
                        value: profile.displayID,
                        symbol: .key
                    )
                    AnchorValueRow(
                        title: "指纹",
                        value: profile.displayFingerprint,
                        symbol: .shieldLefthalfFilled
                    )
                    AnchorValueRow(
                        title: "端点",
                        value: profile.displayEndpoint,
                        symbol: .network
                    )
                    AnchorValueRow(
                        title: "会话",
                        value: AnchorPhaseCopy.statusLine(bridge.phase),
                        symbol: .arrowTriangle2Circlepath,
                        monospaced: false,
                        selectable: false
                    )
                }
            } else {
                HakoClientUI.HakoCardEmptyState(
                    title: "还没有配对任何 Agent",
                    message: "回到首页点「连接 Agent」，扫码或粘贴配对口令即可。",
                    icon: { AnchorSymbolImage(symbol: .rectangleStack) }
                )
            }
        }
    }

    private var hasIdentity: Bool {
        profile.agentID != nil || profile.endpoint != nil || bridge.isPaired
    }

    // MARK: 断开 / 忘记

    private var forgetSection: some View {
        HakoClientUI.HakoProductGroup(
            footer: .copy("忘记配对只清除本机保存的 Agent 身份；设备私钥保留，重装后仍是同一台手机。"),
            palette: palette
        ) {
            Button(role: .destructive) {
                confirmsForget = true
            } label: {
                Label {
                    Text(hako: .copy("断开并忘记配对"))
                        .frame(maxWidth: .infinity)
                } icon: {
                    AnchorSymbolImage(symbol: .xmarkCircle)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(isForgetting || (!bridge.isPaired && !hasIdentity))
            .accessibilityIdentifier("anchor.settings.forget")
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

    private var activitySection: some View {
        HakoClientUI.HakoProductGroup(
            "最近操作",
            footer: .copy("Agent 通过本机执行过的命令；最多保留最近 200 条。"),
            palette: palette
        ) {
            if visibleActivity.isEmpty {
                HakoClientUI.HakoCardEmptyState(
                    title: "还没有操作记录",
                    message: "Agent 执行过的命令会显示在这里。",
                    icon: { AnchorSymbolImage(symbol: .clock) }
                )
            } else {
                VStack(spacing: 0) {
                    ForEach(visibleActivity) { entry in
                        AnchorActivityRow(entry: entry, palette: palette)
                        if entry.id != visibleActivity.last?.id {
                            HakoClientUI.HakoRowDivider()
                        }
                    }
                }
            }
        }
    }

    private var visibleActivity: [AnchorActivityEntry] {
        Array(bridge.recentActivity.prefix(Self.activityLimit))
    }
}

// MARK: - 操作记录行

/// 一条操作记录：中文动作标题 + 相对时间 + 状态徽标。
struct AnchorActivityRow: View {
    @Environment(\.locale) private var locale

    let entry: AnchorActivityEntry
    let palette: HakoClientUI.HakoProductPalette

    var body: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: HakoClientUI.HakoTheme.Spacing.row
        ) {
            VStack(
                alignment: .leading,
                spacing: HakoClientUI.HakoTheme.Spacing.tight
            ) {
                Text(hako: .copy(AnchorActivityPresentation.title(for: entry.op)))
                    .font(.body)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(
                    verbatim: AnchorActivityPresentation.relativeTime(
                        entry.at,
                        locale: locale
                    )
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: HakoClientUI.HakoTheme.Spacing.compact)

            HakoClientUI.HakoStatusBadge(
                title: AnchorActivityPresentation.statusLine(entry.status),
                tint: AnchorActivityPresentation.statusTint(entry.status),
                role: .status,
                categoryFill: palette.raisedFill,
                requirementFill: palette.surface,
                separator: palette.separator
            )
        }
        .frame(
            maxWidth: .infinity,
            minHeight: HakoClientUI.HakoTheme.Control.pointerRowTarget,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("anchor.settings.activity.\(entry.id)")
    }
}

#if DEBUG
#Preview("Agent 管理 · 已配对") {
    AnchorSettingsView(
        bridge: AnchorPreviewBridge(
            phase: .connected,
            isPaired: true,
            agentID: "4N7Q2W8Z0R5TVK9Y",
            recentActivity: anchorPreviewActivity([
                ("core.proxy.select", -180, "applied"),
                ("core.provider.update", -2400, "applied"),
                ("core.config.reload", -5400, "deferred"),
                ("core.conn.close", -7200, "rejected"),
                ("app.subscription.update", -86400, "applied"),
            ])
        ),
        profile: anchorPreviewProfile,
        palette: .anchorPreview
    )
}

#Preview("Agent 管理 · 未配对") {
    AnchorSettingsView(
        bridge: AnchorPreviewBridge(),
        profile: AnchorAgentProfile(),
        palette: .anchorPreview
    )
}
#endif
