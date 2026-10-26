import Foundation
import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - UI 侧可选契约

/// SAS 阶段的可选数据源：由 B 的配对服务在需要人眼比对时提供 6 位确认码。
///
/// UI 只用它展示；未实现时配对页显示占位码位 + 引导文案，流程照常可走完。
/// （CantoBridge.swift 的 CantoPairingServiceProtocol 未声明确认码字段，
///  故这里以可选协议扩展，B 侧愿意的话直接 conform 即可，不影响既有实现。）
public protocol CantoSASCodeProviding: AnyObject, Sendable {
    /// 当前 SAS 确认码（如 "418 296"）；尚未就绪时为 nil。
    var sasCode: String? { get }
}

/// SAS 双端比对的挂起点：配对服务 await `wait()`，UI 用按钮 `decide(_:)` 放行。
///
/// 注意：`wait()` 的闭包会被传进 @Sendable 的 Task（见 startBonjourPairing），
/// 因此本类不能标 @MainActor，必须是 Sendable；内部状态用锁保护。
final class CantoSASDecision: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Bool, Never>?

    func wait() async -> Bool {
        await withCheckedContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
        }
    }

    func decide(_ approved: Bool) {
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        // resume 必须在锁外调：它可能同步唤醒等待者
        c?.resume(returning: approved)
    }
}

// MARK: - 配对页

/// 配对二级页：扫码 / 粘贴口令 / 同一 Wi-Fi 的 Bonjour 设备（SAS 确认）。
///
/// 依赖：总门面 CantoBridgeObservable（近场口令路径）+ 配对服务 CantoPairingServiceProtocol
/// （Bonjour 与 SAS）。UI 不实现、不持有它们的状态。
public struct CantoPairingView: View {
    @Environment(\.locale) private var locale

    /// 总门面（口令路径：bridge.startPairing(withURI:)）。
    @ObservedObject private var proxy: CantoBridgeProxy
    private var bridge: any CantoBridgeObservable { proxy.bridge }
    /// 配对服务（Bonjour 路径）。为 nil 时该区块显示「未启用」并保留扫码/口令路径。
    private let pairingService: CantoPairingServiceProtocol?
    private let palette: ClashClientUI.ClashProductPalette
    /// 配对完成回调（宿主可借此返回首页；默认只在本页显示结果）。
    private let onPaired: (() -> Void)?

    @State private var token = ""
    @State private var tokenPhase = CantoTokenPhase.idle
    @State private var discovered: [CantoBonjourAgent] = []
    @State private var restartToken = 0
    @State private var pendingDevice: CantoBonjourAgent?
    @State private var sasDecision: CantoSASDecision?
    @State private var sasCode: String?
    @State private var isSASConfirmed = false
    @State private var pairFailure: String?
    @State private var pairingTask: Task<Void, Never>?

    public init(
        proxy: CantoBridgeProxy,
        pairingService: CantoPairingServiceProtocol? = nil,
        palette: ClashClientUI.ClashProductPalette,
        onPaired: (() -> Void)? = nil
    ) {
        self.proxy = proxy
        self.pairingService = pairingService
        self.palette = palette
        self.onPaired = onPaired
    }

    public var body: some View {
        CantoPageScaffold(
            palette: palette,
            accessibilityIdentifier: "canto.pair.root"
        ) {
            scanSection
            ClashClientUI.ClashRowDivider()
            tokenSection
            bonjourSection
        }
        .navigationTitle(Text(clash: .copy("连接 Agent")))
        .sheet(item: $pendingDevice) { device in
            sasSheet(device)
        }
        .task { await observeDiscoveredAgents() }
        .onDisappear { pairingTask?.cancel() }
    }

    // MARK: 扫码

    private var scanSection: some View {
        ClashClientUI.ClashProductGroup("扫码连接", palette: palette) {
            VStack(
                alignment: .leading,
                spacing: ClashClientUI.ClashTheme.Spacing.standard
            ) {
                Text(clash: .copy("在电脑上运行 canto pair，用手机扫一下码"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                CantoQRScannerView(
                    onScan: { code in connect(withURI: code) },
                    restartToken: restartToken
                )
            }
        }
    }

    // MARK: 口令

    private var tokenSection: some View {
        ClashClientUI.ClashProductGroup(palette: palette) {
            VStack(
                alignment: .leading,
                spacing: ClashClientUI.ClashTheme.Spacing.standard
            ) {
                Text(clash: .copy("扫不到？粘贴配对口令"))
                    .font(.headline)
                    .foregroundStyle(.primary)

                HStack(spacing: ClashClientUI.ClashTheme.Spacing.compact) {
                    ClashClientUI.ClashFieldRow(
                        "配对口令",
                        hint: "canto://pair?v=1&k=…&s=…&e=…",
                        text: $token,
                        monospaced: true,
                        identifier: "canto.pair.token",
                        onEditingEnded: {
                            // 键盘提交：只有看起来是完整口令时才自动尝试，避免误触。
                            if token.hasPrefix("canto://pair") { connect(withURI: token) }
                        }
                    )
                    // 包内自足粘贴：iOS 16+ 用系统 PasteButton（不触发「已粘贴」横幅），
                    // iOS 15 回退到读剪贴板按钮（ClashPasteControl 属 App target，包内不可见）。
                    CantoPasteButton { pasted in token = pasted }
                }

                Text(clash: .copy("口令由电脑端 canto pair 生成，一次性有效。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    connect(withURI: token)
                } label: {
                    Text(clash: .copy("Connect"))
                        .frame(maxWidth: .infinity)
                }
                .clashPrimaryActionButtonStyle()
                .controlSize(.large)
                .disabled(!canConnect)
                .accessibilityIdentifier("canto.pair.connect")

                tokenStatusLine
            }
        }
    }

    private var canConnect: Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && tokenPhase != .connecting
    }

    @ViewBuilder
    private var tokenStatusLine: some View {
        switch tokenPhase {
        case .idle:
            EmptyView()
        case .connecting:
            HStack(spacing: ClashClientUI.ClashTheme.Spacing.compact) {
                ProgressView()
                Text(clash: .copy("正在与 Agent 握手…"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .accessibilityIdentifier("canto.pair.connecting")
        case .paired(let name):
            Label {
                Text(verbatim: ClashCopy.format("已连接 %@", locale: locale, name))
                    .font(.footnote)
            } icon: {
                CantoSymbolImage(symbol: .checkmarkCircleFill)
            }
            .foregroundStyle(.tint)
            .accessibilityIdentifier("canto.pair.paired")
        case .failed(let reason):
            Label {
                Text(verbatim: reason)
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                CantoSymbolImage(symbol: .exclamationmarkTriangleFill)
            }
            .foregroundStyle(.red)
            .accessibilityIdentifier("canto.pair.failure")
        }
    }

    // MARK: Bonjour

    private var bonjourSection: some View {
        ClashClientUI.ClashProductGroup(
            "同一 Wi-Fi 发现的设备",
            footer: bonjourFooter,
            palette: palette
        ) {
            bonjourContent
        }
    }

    @ViewBuilder
    private var bonjourContent: some View {
        if pairingService == nil {
            ClashClientUI.ClashCardEmptyState(
                title: "未启用局域网发现",
                message: "当前构建没有注入配对服务；用上面的扫码或口令路径连接。",
                icon: { CantoSymbolImage(symbol: .wifi) }
            )
        } else if discovered.isEmpty {
            ClashClientUI.ClashCardEmptyState(
                title: "正在搜索…",
                message: "确保电脑与手机在同一个 Wi-Fi，且在电脑上运行了 canto pair。",
                icon: { CantoSymbolImage(symbol: .wifi) }
            )
        } else {
            VStack(spacing: 0) {
                ForEach(discovered) { agent in
                    deviceRow(agent)
                    if agent.id != discovered.last?.id {
                        ClashClientUI.ClashRowDivider()
                    }
                }
            }
        }
    }

    private var bonjourFooter: ClashDisplayText? {
        guard pairingService != nil else { return nil }
        return "点击设备后，与电脑上的 6 位确认码比对一致再确认连接。"
    }

    private func deviceRow(_ agent: CantoBonjourAgent) -> some View {
        Button {
            startBonjourPairing(agent)
        } label: {
            HStack(
                alignment: .center,
                spacing: ClashClientUI.ClashTheme.Spacing.row
            ) {
                CantoSymbolImage(symbol: .network)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)

                VStack(
                    alignment: .leading,
                    spacing: ClashClientUI.ClashTheme.Typography.rowSubtitleGap(locale)
                ) {
                    Text(verbatim: agent.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(verbatim: deviceDetail(agent))
                        .font(ClashClientUI.ClashTheme.Typography.rowSubtitle(locale))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
                CantoSymbolImage(symbol: .chevronForward)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(
                maxWidth: .infinity,
                minHeight: ClashClientUI.ClashTheme.Control.minimumHitTarget,
                alignment: .leading
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(pairingTask != nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("canto.pair.device.\(agent.id)")
    }

    /// 设备副行：指纹尾 4 位 + 主机（同网地址）。
    ///
    /// CantoBonjourAgent 没有独立指纹字段，其 16 字符 id 由 agent 公钥派生
    /// （见 CantoIDs.agentIdFromPub），故用 id 末 4 位做人眼比对片段。
    private func deviceDetail(_ agent: CantoBonjourAgent) -> String {
        let tail = String(agent.id.suffix(4))
        let host = URL(string: agent.endpoint)?.host ?? agent.endpoint
        return ClashCopy.format("指纹 …%@ · %@", locale: locale, tail, host)
    }

    // MARK: SAS 确认

    private func sasSheet(_ device: CantoBonjourAgent) -> some View {
        CantoSASConfirmSheet(
            deviceName: device.name,
            fingerprintTail: String(device.id.suffix(4)),
            code: sasCode,
            isWaiting: isSASConfirmed,
            failure: pairFailure,
            onConfirm: {
                isSASConfirmed = true
                sasDecision?.decide(true)
            },
            onCancel: {
                sasDecision?.decide(false)
                pendingDevice = nil
            }
        )
        .task { await observeSASCode() }
    }

    /// SAS 确认码由 B 侧在握手过程中逐步产出，UI 以 0.4 秒轮询呈现
    /// （可选协议；未实现则始终显示占位码位）。
    private func observeSASCode() async {
        guard let provider = pairingService as? CantoSASCodeProviding else { return }
        while !Task.isCancelled {
            let latest = provider.sasCode
            if latest != sasCode {
                sasCode = latest
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
    }

    // MARK: 发现

    private func observeDiscoveredAgents() async {
        guard let pairingService else { return }
        for await agents in pairingService.discoverAgents() {
            discovered = agents
        }
    }

    // MARK: 连接动作

    private func startBonjourPairing(_ agent: CantoBonjourAgent) {
        guard let pairingService, pairingTask == nil else { return }
        pairFailure = nil
        sasCode = nil
        isSASConfirmed = false
        let decision = CantoSASDecision()
        sasDecision = decision
        pendingDevice = agent
        pairingTask = Task {
            do {
                let result = try await pairingService.pair(
                    bonjour: agent,
                    sasConfirmed: { await decision.wait() }
                )
                finishBonjourPairing(
                    failure: result.accepted
                        ? nil
                        : ClashCopy.string("电脑端拒绝了这次配对", locale: locale),
                    agentName: result.agentName ?? agent.name
                )
            } catch {
                finishBonjourPairing(
                    failure: String(describing: error),
                    agentName: nil
                )
            }
        }
    }

    private func finishBonjourPairing(failure: String?, agentName: String?) {
        pairingTask = nil
        sasDecision = nil
        pairFailure = failure
        if let failure {
            // 失败：留在设备页继续取景/重试。
            _ = failure
            restartToken += 1
        } else {
            pendingDevice = nil
            tokenPhase = .paired(
                agentName ?? ClashCopy.string("Agent", locale: locale)
            )
            onPaired?()
        }
    }

    /// 扫码 / 口令共用入口：只做格式前置校验，语义校验交给配对服务。
    private func connect(withURI raw: String) {
        let uri = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !uri.isEmpty, tokenPhase != .connecting else { return }
        guard uri.hasPrefix("canto://pair") else {
            tokenPhase = .failed(
                ClashCopy.string(
                    "这不是配对口令：应以 canto://pair 开头",
                    locale: locale
                )
            )
            return
        }
        tokenPhase = .connecting
        Task {
            await bridge.startPairing(withURI: uri)
            if case .failed(let reason) = bridge.phase {
                tokenPhase = .failed(reason)
                restartToken += 1
            } else if bridge.isPaired {
                let pairedName = bridge.agentID.map {
                    ClashCopy.format(
                        "Agent …%@",
                        locale: locale,
                        String($0.suffix(4))
                    )
                } ?? ClashCopy.string("Agent", locale: locale)
                tokenPhase = .paired(pairedName)
                token = ""
                onPaired?()
            } else {
                tokenPhase = .idle
            }
        }
    }
}

/// 口令路径的阶段（Bonjour 路径用 sheet + pairingTask）。
enum CantoTokenPhase: Equatable {
    case idle
    case connecting
    case paired(String)
    case failed(String)
}

// MARK: - SAS 确认弹窗

/// SAS 确认：显示 6 位确认码 + 「确认连接」「取消」。
struct CantoSASConfirmSheet: View {
    @Environment(\.locale) private var locale

    let deviceName: String
    let fingerprintTail: String
    let code: String?
    let isWaiting: Bool
    let failure: String?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: ClashClientUI.ClashTheme.Spacing.standard) {
                Text(clash: .copy("确认连接"))
                    .font(.headline)

                VStack(spacing: ClashClientUI.ClashTheme.Spacing.compact) {
                    Text(verbatim: deviceName)
                        .font(.title3.weight(.semibold))
                    Text(
                        verbatim: ClashCopy.format(
                            "设备指纹 …%@",
                            locale: locale,
                            fingerprintTail
                        )
                    )
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }

                codeBlock

                Text(clash: .copy("电脑上会显示同一组 6 位确认码；不一致就取消。"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                if let failure {
                    Label {
                        Text(verbatim: failure)
                            .font(.footnote)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        CantoSymbolImage(symbol: .exclamationmarkTriangleFill)
                    }
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("canto.pair.sas.failure")
                }
            }
            .padding(ClashClientUI.ClashTheme.Spacing.section)
            .frame(maxWidth: .infinity)

            Spacer(minLength: 0)

            ClashClientUI.ClashDialogActionBar(
                cancelTitle: "Cancel",
                onCancel: onCancel,
                confirmTitle: "确认连接",
                confirmDisabled: isWaiting,
                onConfirm: onConfirm
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("canto.pair.sas")
    }

    @ViewBuilder
    private var codeBlock: some View {
        if isWaiting {
            HStack(spacing: ClashClientUI.ClashTheme.Spacing.compact) {
                ProgressView()
                Text(clash: .copy("正在建立加密会话…"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if let code, !code.isEmpty {
            Text(verbatim: code)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.tint)
                .accessibilityIdentifier("canto.pair.sas.code")
        } else {
            VStack(spacing: ClashClientUI.ClashTheme.Spacing.tight) {
                Text(verbatim: "— — —")
                    .font(.system(size: 34, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(clash: .copy("确认码由电脑端显示；两端一致时点「确认连接」"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityIdentifier("canto.pair.sas.placeholder")
        }
    }
}

#if DEBUG
#Preview("配对页 · 未配对") {
    CantoPairingView(
        proxy: CantoBridgeProxy(CantoPreviewBridge()),
        pairingService: CantoPreviewPairingService(),
        palette: .cantoPreview
    )
}

#Preview("配对页 · 无配对服务") {
    CantoPairingView(
        proxy: CantoBridgeProxy(CantoPreviewBridge()),
        palette: .cantoPreview
    )
}
#endif

// MARK: - 包内粘贴控件

/// 口令粘贴控件（包内自足；宿主 App 的 ClashPasteControl 在 App target，包看不到）。
struct CantoPasteButton: View {
    let onPaste: (String) -> Void

    var body: some View {
        if #available(iOS 16.0, macOS 13.0, *) {
            PasteButton(payloadType: String.self) { strings in
                if let first = strings.first { onPaste(first) }
            }
            .labelStyle(.iconOnly)
            .buttonBorderShape(.roundedRectangle)
            .accessibilityIdentifier("canto.pair.paste")
        } else {
            Button {
                #if os(iOS)
                if let text = UIPasteboard.general.string { onPaste(text) }
                #endif
            } label: {
                CantoSymbolImage(symbol: .docOnClipboard)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("canto.pair.paste")
        }
    }
}
