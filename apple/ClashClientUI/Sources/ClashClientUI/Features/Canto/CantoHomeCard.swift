import Foundation
import SwiftUI

// MARK: - 首页 Agent 卡

/// 首页 Agent 卡（三状态）：未配对 / 连接中 / 已连接。
///
/// 与宿主首页卡同构：
///   [图标] 标题 ⋯ 右箭头 → 大字状态行 → 灰色副行；整卡 push 二级页，卡内不放按钮。
/// 卡面沿用 ClashHomePrimaryPageCard 的结构（iOS 26 系统玻璃 / 其余卡片底），
/// 布局常量全部取 ClashClientUI.ClashTheme，配色全部走语义色（强调色 = 宿主 AppAccent）。
///
/// 跳转：
///   - 默认用 NavigationLink 原生 push（紧凑触摸壳）；
///   - 常规壳（iPad 侧栏 / macOS）可用 `onOpen` 接管，由宿主写入自己的会话页。
public struct CantoHomeCard<Icon: View>: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// 类型擦除桥（环境注入：CantoBridgeProxy 是可订阅的具体类型）
    @ObservedObject private var proxy: CantoBridgeProxy
    private var bridge: any CantoBridgeObservable { proxy.bridge }
    private let palette: ClashClientUI.ClashProductPalette
    private let profile: CantoAgentProfile
    private let pairingService: CantoPairingServiceProtocol?
    private let onOpen: ((CantoCardPage) -> Void)?
    private let icon: (ClashSymbol) -> Icon

    public init(
        proxy: CantoBridgeProxy,
        palette: ClashClientUI.ClashProductPalette = .cantoPreview,
        profile: CantoAgentProfile = CantoAgentProfile(),
        pairingService: CantoPairingServiceProtocol? = nil,
        onOpen: ((CantoCardPage) -> Void)? = nil,
        @ViewBuilder icon: @escaping (ClashSymbol) -> Icon
    ) {
        self.proxy = proxy
        self.palette = palette
        self.profile = profile
        self.pairingService = pairingService
        self.onOpen = onOpen
        self.icon = icon
    }

    public var body: some View {
        linkedCard
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.card.canto")
    }

    // MARK: 整卡跳转

    private var page: CantoCardPage {
        bridge.isPaired ? .settings : .pairing
    }

    @ViewBuilder
    private var linkedCard: some View {
        if let onOpen {
            Button {
                onOpen(page)
            } label: {
                cardBody
            }
            .buttonStyle(CantoCardPressStyle())
        } else {
            NavigationLink {
                ClashClientUI.ClashLazyView {
                    destination
                }
                .clashNativePushBoundary()
            } label: {
                cardBody
            }
            .buttonStyle(CantoCardPressStyle())
        }
    }

    @ViewBuilder
    private var destination: some View {
        if bridge.isPaired {
            CantoSettingsView(
                proxy: proxy,
                profile: profile,
                palette: palette
            )
        } else {
            CantoPairingView(
                proxy: proxy,
                pairingService: pairingService,
                palette: palette
            )
        }
    }

    // MARK: 卡面

    private var cardBody: some View {
        CantoCardSurface(palette: palette) {
            VStack(
                alignment: .leading,
                spacing: ClashClientUI.ClashTheme.Spacing.standard
            ) {
                titleRow
                VStack(
                    alignment: .leading,
                    spacing: ClashClientUI.ClashTheme.Typography.rowSubtitleGap(locale)
                ) {
                    statusLine
                    subtitleLine
                }
            }
        }
    }

    /// 图标 + 标题 + 右箭头（与首页卡标题行同构：图标与标题跟随 AppAccent）。
    private var titleRow: some View {
        HStack(
            alignment: .firstTextBaseline,
            spacing: ClashClientUI.ClashTheme.Spacing.row
        ) {
            ClashClientUI.ClashCardTitle(
                titleTint: .primary,
                iconTint: .primary,
                followsAccent: true
            ) {
                Text(clash: .copy("连接 Agent"))
            } icon: {
                icon(.rectangleStack)
            }

            Spacer(minLength: ClashClientUI.ClashTheme.Spacing.compact)

            icon(.chevronForward)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    /// 大字状态行：未连接 / 连接中… / 已连接（+ 已挂起 / 连接失败）。
    private var statusLine: some View {
        HStack(spacing: ClashClientUI.ClashTheme.Spacing.compact) {
            if isConnecting, !dynamicTypeSize.isAccessibilitySize {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            Text(clash: .copy(CantoPhaseCopy.statusLine(bridge.phase)))
                .font(
                    dynamicTypeSize.isAccessibilitySize
                        ? .title3.weight(.bold)
                        : .title3.weight(.semibold)
                )
                .foregroundStyle(statusStyle)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                .minimumScaleFactor(0.85)
                .fixedSize(
                    horizontal: false,
                    vertical: dynamicTypeSize.isAccessibilitySize
                )
        }
    }

    /// 灰色副行：未配对 → 能力说明；已连接 → agent 名 · 相对时间 · 最近操作。
    private var subtitleLine: some View {
        Text(verbatim: subtitleText)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
            .truncationMode(.tail)
            .fixedSize(
                horizontal: false,
                vertical: dynamicTypeSize.isAccessibilitySize
            )
    }

    private var subtitleText: String {
        CantoPhaseCopy.subtitleLine(
            bridge.phase,
            profile: profile,
            activity: bridge.recentActivity.first,
            locale: locale
        )
    }

    private var isConnecting: Bool {
        bridge.phase == .connecting
    }

    /// 状态行配色：已连接 = 强调色；失败 = 语义红；其余 = 主文本色。
    private var statusStyle: AnyShapeStyle {
        if CantoPhaseCopy.isAccented(bridge.phase) {
            return AnyShapeStyle(.tint)
        }
        if CantoPhaseCopy.isFailure(bridge.phase) {
            return AnyShapeStyle(Color.red)
        }
        return AnyShapeStyle(.primary)
    }
}

// MARK: - 卡面容器

/// 卡面：结构对齐 ClashHomePrimaryPageCard（包内 private，无法跨模块复用）。
/// iOS 26 走系统玻璃，其余走 ClashCardSurface 卡片底，内边距统一 Spacing.standard。
private struct CantoCardSurface<Content: View>: View {
    private let palette: ClashClientUI.ClashProductPalette
    private let content: Content

    init(
        palette: ClashClientUI.ClashProductPalette,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.content = content()
    }

    var body: AnyView {
        let padded = content
            .padding(ClashClientUI.ClashTheme.Spacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)

        let wearsPlatformMaterial: Bool = {
            if ClashClientUI.ClashPlatformLayout.primaryPageCardUsesLiquidGlass {
                return true
            }
            if ClashClientUI.ClashPlatformLayout.pageUsesSystemSettingsIdiom {
                return false
            }
            return ClashClientUI.ClashPlatformLayout.touchCardWearsSystemMaterial
        }()

        let corner = ClashClientUI.ClashPlatformLayout.primaryPageCardUsesLiquidGlass
            ? ClashClientUI.ClashTheme.Radius.card
            : ClashClientUI.ClashTheme.Radius.liquidGlassCard

        if wearsPlatformMaterial,
           #available(iOS 26.0, macOS 26.0, tvOS 26.0, *) {
            return AnyView(
                padded
                    .clipShape(
                        RoundedRectangle(cornerRadius: corner, style: .continuous)
                    )
                    .glassEffect(.regular, in: .rect(cornerRadius: corner))
            )
        }
        return AnyView(
            ClashClientUI.ClashCardSurface(
                fill: palette.card,
                separator: palette.separator,
                paintsInSettingsIdiom: true
            ) {
                padded
            }
        )
    }
}

/// 整卡按压反馈：只调透明度，不引入色值。
private struct CantoCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("首页卡 · 未配对") {
    NavigationView {
        CantoHomeCard(
            proxy: CantoBridgeProxy(CantoPreviewBridge()),
            palette: .cantoPreview,
            pairingService: CantoPreviewPairingService()
        ) { symbol in
            CantoSymbolImage(symbol: symbol)
        }
        .padding(ClashClientUI.ClashTheme.Spacing.standard)
        .navigationTitle(Text(verbatim: "Home"))
    }
}

#Preview("首页卡 · 连接中") {
    NavigationView {
        CantoHomeCard(
            proxy: CantoBridgeProxy(CantoPreviewBridge(phase: .connecting)),
            palette: .cantoPreview
        ) { symbol in
            CantoSymbolImage(symbol: symbol)
        }
        .padding(ClashClientUI.ClashTheme.Spacing.standard)
        .navigationTitle(Text(verbatim: "Home"))
    }
}

#Preview("首页卡 · 已连接") {
    NavigationView {
        CantoHomeCard(
            proxy: CantoBridgeProxy(CantoPreviewBridge(
                phase: .connected,
                isPaired: true,
                agentID: "4N7Q2W8Z0R5TVK9Y",
                recentActivity: cantoPreviewActivity([
                    ("core.proxy.select", -180, "applied")
                ])
            )),
            palette: .cantoPreview,
            profile: cantoPreviewProfile
        ) { symbol in
            CantoSymbolImage(symbol: symbol)
        }
        .padding(ClashClientUI.ClashTheme.Spacing.standard)
        .navigationTitle(Text(verbatim: "Home"))
    }
}

#Preview("首页卡 · 连接失败") {
    NavigationLink {
        EmptyView()
    } label: {
        CantoHomeCard(
            proxy: CantoBridgeProxy(CantoPreviewBridge(phase: .failed(reason: "Agent 未响应：连接被拒绝"))),
            palette: .cantoPreview
        ) { symbol in
            CantoSymbolImage(symbol: symbol)
        }
        .padding(ClashClientUI.ClashTheme.Spacing.standard)
    }
}
#endif
