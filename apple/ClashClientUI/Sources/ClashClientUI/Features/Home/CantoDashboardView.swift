import SwiftUI

/// Canto 仪表页骨架：字标 + 连接开关、档案入口、模式行、连接异常、双流量卡、
/// Canto Agent 卡与快捷方式网格。
///
/// 只负责布局与无障碍，数据与动作全部来自 `CantoDashboardModel`；
/// 顶部安全区与页面背景延伸由外层壳负责。
public struct CantoDashboardView: View {
    private let model: CantoDashboardModel
    @Environment(\.locale) private var locale

    public init(model: CantoDashboardModel) {
        self.model = model
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CantoTheme.Spacing.section) {
                VStack(alignment: .leading, spacing: CantoTheme.Spacing.row) {
                    header
                    profileRow
                }
                connectionNotice
                traffic
                shortcuts
                cantoCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, CantoTheme.Spacing.standard)
            .padding(.bottom, CantoTheme.Spacing.section)
        }
        .background(CantoTheme.Palette.canvas)
    }

    // MARK: - 顶部

    /// 开关直接读写宿主注入的状态：动作失败或宿主拒绝时，开关会跟着真实状态回弹，
    /// 不会出现“界面已打开、内核仍未连接”的假状态。
    private var connectionBinding: Binding<Bool> {
        Binding(
            get: { model.isConnected },
            set: { isOn in
                guard isOn != model.isConnected else { return }
                model.onToggleConnection()
            }
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: CantoTheme.Spacing.compact) {
            HStack(alignment: .center, spacing: CantoTheme.Spacing.compact) {
                Text(verbatim: model.brandTitle)
                    .font(CantoTheme.Typography.pageTitle)
                    .foregroundStyle(CantoTheme.Palette.accent)
                    .accessibilityLabel(Text(verbatim: model.brandTitle))
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                Toggle(model.connectionLabel, isOn: connectionBinding)
                    .labelsHidden()
                    .tint(CantoTheme.Palette.accent)
                    .disabled(!model.isConnectionToggleEnabled)
                    .accessibilityLabel(Text(verbatim: model.connectionLabel))
            }

            Button(action: model.onSelectMode) {
                HStack(spacing: 5) {
                    Text(verbatim: model.modeTitle)
                        .font(CantoTheme.Typography.caption.weight(.medium))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(CantoTheme.Palette.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule().fill(CantoTheme.Palette.accent.opacity(0.08))
                )
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: model.modeTitle))

            if let connectionSubtitle = model.connectionSubtitle {
                Text(verbatim: connectionSubtitle)
                    .font(CantoTheme.Typography.caption)
                    .foregroundStyle(CantoTheme.Palette.secondaryInk)
                    .accessibilityLabel(Text(verbatim: connectionSubtitle))
            }

            connectionAction
        }
    }

    @ViewBuilder
    private var connectionAction: some View {
        if let title = model.connectionActionTitle,
           let action = model.onConnectionAction {
            Button(action: action) {
                Text(verbatim: title)
                    .font(CantoTheme.Typography.caption.weight(.semibold))
                    .foregroundStyle(CantoTheme.Palette.accent)
                    .padding(.horizontal, CantoTheme.Spacing.row)
                    .padding(.vertical, 6)
                    .background(
                        Capsule().fill(CantoTheme.Palette.accent.opacity(0.1))
                    )
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(!model.connectionActionEnabled)
            .accessibilityLabel(Text(verbatim: title))
        }
    }

    // MARK: - 档案入口

    @ViewBuilder
    private var profileRow: some View {
        if let title = model.profileTitle, let action = model.onOpenProfiles {
            Button(action: action) {
                HStack(spacing: CantoTheme.Spacing.compact) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(CantoTheme.Palette.secondaryInk)
                        .accessibilityHidden(true)

                    Text(verbatim: title)
                        .font(CantoTheme.Typography.rowSubtitle)
                        .foregroundStyle(CantoTheme.Palette.ink)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: CantoTheme.Spacing.compact)

                    Image(systemName: accessorySymbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(
                            model.profileAccessory == .add
                                ? CantoTheme.Palette.accent
                                : CantoTheme.Palette.secondaryInk
                        )
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: title))
            .accessibilityIdentifier("canto.dashboard.profile")
        }
    }

    private var accessorySymbol: String {
        switch model.profileAccessory {
        case .add:
            return "plus.circle.fill"
        case .picker, .none:
            return "chevron.up.chevron.down"
        }
    }

    // MARK: - 连接异常

    @ViewBuilder
    private var connectionNotice: some View {
        if let notice = model.connectionNotice {
            Button(action: notice.action) {
                HStack(alignment: .top, spacing: CantoTheme.Spacing.row) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(
                            notice.isDestructive
                                ? CantoTheme.Palette.danger
                                : CantoTheme.Palette.warning
                        )
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: CantoTheme.Spacing.tight) {
                        Text(verbatim: notice.message)
                            .font(CantoTheme.Typography.rowSubtitle)
                            .foregroundStyle(CantoTheme.Palette.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        if let actionTitle = notice.actionTitle {
                            Text(verbatim: actionTitle)
                                .font(CantoTheme.Typography.caption.weight(.semibold))
                                .foregroundStyle(
                                    notice.isDestructive
                                        ? CantoTheme.Palette.danger
                                        : CantoTheme.Palette.warning
                                )
                        }
                    }
                    .multilineTextAlignment(.leading)

                    Spacer(minLength: CantoTheme.Spacing.compact)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(CantoTheme.Palette.secondaryInk)
                        .padding(.top, CantoTheme.Spacing.tight)
                        .accessibilityHidden(true)
                }
                .padding(CantoTheme.Spacing.standard)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(
                        cornerRadius: CantoTheme.Radius.control,
                        style: .continuous
                    )
                    .fill(CantoTheme.Palette.card)
                )
                .overlay(
                    RoundedRectangle(
                        cornerRadius: CantoTheme.Radius.control,
                        style: .continuous
                    )
                    .stroke(CantoTheme.Palette.separator, lineWidth: 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("canto.dashboard.issue")
        }
    }

    // MARK: - 流量

    private var traffic: some View {
        HStack(alignment: .top, spacing: CantoTheme.Spacing.compact) {
            CantoTrafficTile(
                direction: .upload,
                label: model.uploadLabel,
                value: model.uploadValue,
                caption: model.uploadCaption
            )
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(verbatim: "\(model.uploadLabel) \(model.uploadValue), \(model.uploadCaption)")
            )

            CantoTrafficTile(
                direction: .download,
                label: model.downloadLabel,
                value: model.downloadValue,
                caption: model.downloadCaption
            )
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(verbatim: "\(model.downloadLabel) \(model.downloadValue), \(model.downloadCaption)")
            )
        }
    }

    // MARK: - Canto Agent

    @ViewBuilder
    private var cantoCard: some View {
        if let bridge = model.cantoBridge, let onOpen = model.onOpenCanto {
            CantoGroup {
                CantoAgentRow(proxy: bridge, onOpen: onOpen)
            }
        }
    }

    // MARK: - 快捷方式

    private var shortcuts: some View {
        VStack(alignment: .leading, spacing: CantoTheme.Spacing.row) {
            CantoSectionHeader(
                title: model.shortcutsTitle,
                actionTitle: model.shortcutsEditTitle,
                action: model.onEditShortcuts
            )

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                ],
                spacing: 10
            ) {
                // 卡片的合并朗读（标题作 label）由 CantoShortcutCard 自己负责。
                ForEach(model.shortcuts) { shortcut in
                    CantoShortcutCard(
                        title: ClashCopy.string(shortcut.titleKey, locale: locale),
                        subtitle: nil,
                        systemImage: shortcut.systemImage,
                        tint: CantoTheme.Palette.accent,
                        action: { model.onShortcut(shortcut) }
                    )
                }
            }
        }
    }
}

/// Canto Agent 的紧凑入口：复用设置页的分组行，不再用首页大卡片。
private struct CantoAgentRow: View {
    @ObservedObject var proxy: CantoBridgeProxy
    let onOpen: (CantoCardPage) -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        Button {
            onOpen(proxy.bridge.isPaired ? .settings : .pairing)
        } label: {
            CantoGroupRow(
                title: ClashCopy.string("Canto Agent", locale: locale),
                subtitle: CantoPhaseCopy.statusLine(
                    proxy.bridge.phase,
                    locale: locale
                ),
                systemImage: "sparkles",
                iconTint: CantoTheme.Palette.accent,
                showsDivider: false
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.card.canto")
    }
}
