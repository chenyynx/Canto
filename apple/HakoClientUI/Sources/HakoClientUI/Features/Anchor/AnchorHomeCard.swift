import Foundation
import SwiftUI

// MARK: - 首页 Agent 卡

/// 首页 Agent 卡（三状态）：未配对 / 连接中 / 已连接。
///
/// 与宿主首页卡同构：
///   [图标] 标题 ⋯ 右箭头 → 大字状态行 → 灰色副行；整卡 push 二级页，卡内不放按钮。
/// 卡面沿用 HakoHomePrimaryPageCard 的结构（iOS 26 系统玻璃 / 其余卡片底），
/// 布局常量全部取 HakoClientUI.HakoTheme，配色全部走语义色（强调色 = 宿主 AppAccent）。
///
/// 跳转：
///   - 默认用 NavigationLink 原生 push（紧凑触摸壳）；
///   - 常规壳（iPad 侧栏 / macOS）可用 `onOpen` 接管，由宿主写入自己的会话页。
public struct AnchorHomeCard<Icon: View>: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// any 桥（环境注入）：ObservableObject 的变更经 objectWillChange 手动桥接
    /// （@ObservedObject 不支持 existential）。
    private let bridge: any AnchorBridgeObservable
    @State private var revision = Int64(0)
    private let palette: HakoClientUI.HakoProductPalette
    private let profile: AnchorAgentProfile
    private let pairingService: AnchorPairingServiceProtocol?
    private let onOpen: ((AnchorCardPage) -> Void)?
    private let icon: (HakoSymbol) -> Icon

    public init(
        bridge: any AnchorBridgeObservable,
        palette: HakoClientUI.HakoProductPalette = .hakoProduct,
        profile: AnchorAgentProfile = AnchorAgentProfile(),
        pairingService: AnchorPairingServiceProtocol? = nil,
        onOpen: ((AnchorCardPage) -> Void)? = nil,
        @ViewBuilder icon: @escaping (HakoSymbol) -> Icon
    ) {
        self.bridge = bridge
        self.palette = palette
        self.profile = profile
        self.pairingService = pairingService
        self.onOpen = onOpen
        self.icon = icon
    }

    public var body: some View {
        // any 桥的 objectWillChange → @State revision：驱动卡片重算
        let _ = revision
        linkedCard
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.card.anchor")
            .onReceive(bridge.objectWillChange) { _ in
                revision &+= 1
            }
    }

    // MARK: 整卡跳转

    private var page: AnchorCardPage {
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
            .buttonStyle(AnchorCardPressStyle())
        } else {
            NavigationLink {
                HakoClientUI.HakoLazyView {
                    destination
                }
                .hakoNativePushBoundary()
            } label: {
                cardBody
            }
            .buttonStyle(AnchorCardPressStyle())
        }
    }

    @ViewBuilder
    private var destination: some View {
        if bridge.isPaired {
            AnchorSettingsView(
                bridge: bridge,
                profile: profile,
                palette: palette
            )
        } else {
            AnchorPairingView(
                bridge: bridge,
                pairingService: pairingService,
                palette: palette
            )
        }
    }

    // MARK: 卡面

    private var cardBody: some View {
        AnchorCardSurface(palette: palette) {
            VStack(
                alignment: .leading,
                spacing: HakoClientUI.HakoTheme.Spacing.standard
            ) {
                titleRow
                VStack(
                    alignment: .leading,
                    spacing: HakoClientUI.HakoTheme.Typography.rowSubtitleGap(locale)
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
            spacing: HakoClientUI.HakoTheme.Spacing.row
        ) {
            HakoClientUI.HakoCardTitle(
                titleTint: .primary,
                iconTint: .primary,
                followsAccent: true
            ) {
                Text(hako: .copy("连接 Agent"))
            } icon: {
                icon(.rectangleStack)
            }

            Spacer(minLength: HakoClientUI.HakoTheme.Spacing.compact)

            icon(.chevronForward)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
    }

    /// 大字状态行：未连接 / 连接中… / 已连接（+ 已挂起 / 连接失败）。
    private var statusLine: some View {
        HStack(spacing: HakoClientUI.HakoTheme.Spacing.compact) {
            if isConnecting, !dynamicTypeSize.isAccessibilitySize {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
            }
            Text(hako: .copy(AnchorPhaseCopy.statusLine(bridge.phase)))
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
        AnchorPhaseCopy.subtitleLine(
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
        if AnchorPhaseCopy.isAccented(bridge.phase) {
            return AnyShapeStyle(.tint)
        }
        if AnchorPhaseCopy.isFailure(bridge.phase) {
            return AnyShapeStyle(Color.red)
        }
        return AnyShapeStyle(.primary)
    }
}

// MARK: - 卡面容器

/// 卡面：结构对齐 HakoHomePrimaryPageCard（包内 private，无法跨模块复用）。
/// iOS 26 走系统玻璃，其余走 HakoCardSurface 卡片底，内边距统一 Spacing.standard。
private struct AnchorCardSurface<Content: View>: View {
    private let palette: HakoClientUI.HakoProductPalette
    private let content: Content

    init(
        palette: HakoClientUI.HakoProductPalette,
        @ViewBuilder content: () -> Content
    ) {
        self.palette = palette
        self.content = content()
    }

    var body: AnyView {
        let padded = content
            .padding(HakoClientUI.HakoTheme.Spacing.standard)
            .frame(maxWidth: .infinity, alignment: .leading)

        let wearsPlatformMaterial: Bool = {
            if HakoClientUI.HakoPlatformLayout.primaryPageCardUsesLiquidGlass {
                return true
            }
            if HakoClientUI.HakoPlatformLayout.pageUsesSystemSettingsIdiom {
                return false
            }
            return HakoClientUI.HakoPlatformLayout.touchCardWearsSystemMaterial
        }()

        let corner = HakoClientUI.HakoPlatformLayout.primaryPageCardUsesLiquidGlass
            ? HakoClientUI.HakoTheme.Radius.card
            : HakoClientUI.HakoTheme.Radius.liquidGlassCard

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
            HakoClientUI.HakoCardSurface(
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
private struct AnchorCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

#if DEBUG
#Preview("首页卡 · 未配对") {
    NavigationView {
        AnchorHomeCard(
            bridge: AnchorPreviewBridge(),
            palette: .anchorPreview,
            pairingService: AnchorPreviewPairingService()
        ) { symbol in
            AnchorSymbolImage(symbol: symbol)
        }
        .padding(HakoClientUI.HakoTheme.Spacing.standard)
        .navigationTitle(Text(verbatim: "Home"))
    }
}

#Preview("首页卡 · 连接中") {
    NavigationView {
        AnchorHomeCard(
            bridge: AnchorPreviewBridge(phase: .connecting),
            palette: .anchorPreview
        ) { symbol in
            AnchorSymbolImage(symbol: symbol)
        }
        .padding(HakoClientUI.HakoTheme.Spacing.standard)
        .navigationTitle(Text(verbatim: "Home"))
    }
}

#Preview("首页卡 · 已连接") {
    NavigationView {
        AnchorHomeCard(
            bridge: AnchorPreviewBridge(
                phase: .connected,
                isPaired: true,
                agentID: "4N7Q2W8Z0R5TVK9Y",
                recentActivity: anchorPreviewActivity([
                    ("core.proxy.select", -180, "applied")
                ])
            ),
            palette: .anchorPreview,
            profile: anchorPreviewProfile
        ) { symbol in
            AnchorSymbolImage(symbol: symbol)
        }
        .padding(HakoClientUI.HakoTheme.Spacing.standard)
        .navigationTitle(Text(verbatim: "Home"))
    }
}

#Preview("首页卡 · 连接失败") {
    NavigationLink {
        EmptyView()
    } label: {
        AnchorHomeCard(
            bridge: AnchorPreviewBridge(phase: .failed(reason: "Agent 未响应：连接被拒绝")),
            palette: .anchorPreview
        ) { symbol in
            AnchorSymbolImage(symbol: symbol)
        }
        .padding(HakoClientUI.HakoTheme.Spacing.standard)
    }
}
#endif
