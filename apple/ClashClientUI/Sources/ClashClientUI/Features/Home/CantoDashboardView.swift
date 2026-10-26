import SwiftUI

/// Canto 仪表页骨架：字标 + 连接开关、模式行、双流量卡与快捷方式网格。
///
/// 只负责布局与无障碍，数据与动作全部来自 `CantoDashboardModel`；
/// 顶部安全区与页面背景延伸由外层壳负责。
public struct CantoDashboardView: View {
    private let model: CantoDashboardModel

    /// `model.isConnected` 是不可变值，而 `Toggle` 需要可变绑定：
    /// 本地状态先承接用户操作，`onChange` 再回调宿主；宿主刷新
    /// `isConnected` 时以外部值为准回写本地状态。
    @State private var connected: Bool
    @Environment(\.locale) private var locale

    public init(model: CantoDashboardModel) {
        self.model = model
        _connected = State(initialValue: model.isConnected)
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: CantoTheme.Spacing.section) {
                header
                traffic
                shortcuts
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, CantoTheme.Spacing.standard)
            .padding(.bottom, CantoTheme.Spacing.section)
        }
        .background(CantoTheme.Palette.canvas)
        .onChange(of: connected) { isOn in
            guard isOn != model.isConnected else { return }
            model.onToggleConnection()
        }
        .onChange(of: model.isConnected) { isOn in
            connected = isOn
        }
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(alignment: .leading, spacing: CantoTheme.Spacing.compact) {
            HStack(alignment: .center, spacing: CantoTheme.Spacing.compact) {
                Text(verbatim: model.brandTitle)
                    .font(CantoTheme.Typography.pageTitle)
                    .foregroundStyle(CantoTheme.Palette.accent)
                    .accessibilityLabel(Text(verbatim: model.brandTitle))
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 0)

                Toggle(model.connectionLabel, isOn: $connected)
                    .labelsHidden()
                    .tint(CantoTheme.Palette.accent)
                    .accessibilityLabel(Text(verbatim: model.connectionLabel))
            }

            Button(action: model.onSelectMode) {
                HStack(spacing: CantoTheme.Spacing.tight) {
                    Text(verbatim: model.modeTitle)
                        .font(CantoTheme.Typography.rowTitle)
                    Image(systemName: "chevron.down")
                        .font(CantoTheme.Typography.caption.weight(.semibold))
                }
                .foregroundStyle(CantoTheme.Palette.accent)
                .contentShape(Rectangle())
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
                Text(verbatim: "\(model.uploadLabel) \(model.uploadValue)，\(model.uploadCaption)")
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
                Text(verbatim: "\(model.downloadLabel) \(model.downloadValue)，\(model.downloadCaption)")
            )
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
                        tint: shortcut.tint,
                        action: { model.onShortcut(shortcut) }
                    )
                }
            }
        }
    }
}
