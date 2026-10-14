import SwiftUI

#if os(iOS)
import AVFoundation
import UIKit
#endif

// MARK: - 扫码区

/// 相机扫码相机状态（仅 iOS）。
enum AnchorCameraPhase: Equatable {
    /// 权限未决（首次进页，正在申请）。
    case unknown
    /// 权限缺失或被拒 —— 给引导文案 + 跳系统设置。
    case denied
    /// 无可用摄像头 / 会话建立失败；关联值是给用户看的原因。
    case unavailable(String)
    /// 取景中。
    case running
    /// 已扫到，暂停取景（避免重复回调）。
    case scanned
}

/// 配对页的大二维码扫描区。
///
/// iOS：AVCaptureSession + AVCaptureVideoPreviewLayer 取景，识别 QR 后回调一次并暂停。
/// macOS：无摄像头扫码路径，只给口令引导（配对页的口令区仍完整可用）。
struct AnchorQRScannerView: View {
    /// 扫到二维码文本（已 trim 空白）；同一码在 2 秒内不会重复回调。
    let onScan: (String) -> Void
    /// 配对页递增本值即可要求重新开始取景（例如口令连接失败后）。
    var restartToken: Int = 0

#if os(iOS)
    @StateObject private var scanner = AnchorQRScannerModel()
    @Environment(\.openURL) private var openURL
#endif

    var body: some View {
#if os(iOS)
        iosBody
#else
        macBody
#endif
    }

    // MARK: macOS

    private var macBody: some View {
        VStack(spacing: HakoClientUI.HakoTheme.Spacing.compact) {
            AnchorSymbolImage(symbol: .qrcodeViewfinder)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(HakoCopy.key("这台设备没有相机扫码路径"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(HakoCopy.key("在电脑上运行 anchor pair，把配对口令粘贴到下方即可"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(HakoClientUI.HakoTheme.Spacing.section)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("anchor.pair.scanner.unavailable")
    }

#if os(iOS)
    // MARK: iOS 取景

    private var iosBody: some View {
        ZStack {
            Rectangle().fill(viewportFill)
            scannerContent
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(
            RoundedRectangle(
                cornerRadius: HakoClientUI.HakoTheme.Radius.card,
                style: .continuous
            )
        )
        .overlay(scanFrame)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anchor.pair.scanner")
        .task { scanner.start() }
        .onChange(of: restartToken) { _ in
            scanner.start()
        }
        .onChange(of: scanner.scannedCode) { code in
            guard let code, !code.isEmpty else { return }
            onScan(code)
        }
        .onDisappear { scanner.stop() }
    }

    @ViewBuilder
    private var scannerContent: some View {
        switch scanner.phase {
        case .running, .scanned:
            AnchorQRPreviewView(session: scanner.session)
            if scanner.phase == .scanned {
                scannedBadge
            }
        case .unknown:
            placeholder(
                symbol: .qrcodeViewfinder,
                title: "正在申请相机权限…",
                message: nil
            )
        case .denied:
            permissionGuidance
        case .unavailable(let reason):
            placeholder(
                symbol: .exclamationmarkTriangle,
                title: "扫码暂不可用",
                message: reason
            )
        }
    }

    private var scannedBadge: some View {
        Label {
            Text(HakoCopy.key("已扫到，正在连接…"))
                .font(.footnote.weight(.semibold))
        } icon: {
            AnchorSymbolImage(symbol: .checkmarkCircleFill)
        }
        .foregroundStyle(.tint)
        .padding(.horizontal, HakoClientUI.HakoTheme.Spacing.row)
        .padding(.vertical, HakoClientUI.HakoTheme.Spacing.compact)
        .background(.thinMaterial, in: Capsule())
        .accessibilityIdentifier("anchor.pair.scanner.scanned")
    }

    private var permissionGuidance: some View {
        VStack(spacing: HakoClientUI.HakoTheme.Spacing.compact) {
            AnchorSymbolImage(symbol: .infoCircle)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(HakoCopy.key("相机权限被拒绝"))
                .font(.headline)
            Text(
                HakoCopy.key(
                    "到「设置 › 隐私与安全性 › 相机」允许 Clash 使用相机；也可以直接用下方口令连接"
                )
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                openURL(url)
            } label: {
                Text(HakoCopy.key("前往系统设置"))
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("anchor.pair.scanner.settings")
        }
        .padding(HakoClientUI.HakoTheme.Spacing.section)
        .accessibilityIdentifier("anchor.pair.scanner.denied")
    }

    private func placeholder(
        symbol: HakoSymbol,
        title: String,
        message: String?
    ) -> some View {
        VStack(spacing: HakoClientUI.HakoTheme.Spacing.compact) {
            AnchorSymbolImage(symbol: symbol)
                .font(.title)
                .foregroundStyle(.secondary)
            Text(HakoCopy.key(title))
                .font(.headline)
            if let message {
                Text(HakoCopy.key(message))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(HakoClientUI.HakoTheme.Spacing.section)
    }

    /// 取景框：强调色描边 + 中心提示（accent 跟随宿主主色）。
    private var scanFrame: some View {
        ZStack {
            RoundedRectangle(
                cornerRadius: HakoClientUI.HakoTheme.Radius.control,
                style: .continuous
            )
            .strokeBorder(.tint, lineWidth: 3)

            if scanner.phase == .running {
                Text(HakoCopy.key("把电脑上的二维码放进取景框"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, HakoClientUI.HakoTheme.Spacing.row)
                    .padding(.vertical, HakoClientUI.HakoTheme.Spacing.tight)
                    .background(.thinMaterial, in: Capsule())
            }
        }
        .padding(HakoClientUI.HakoTheme.Spacing.section)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 取景框底色：相机预览按行业惯例用深底，故此处用系统黑（非字面量）；
    /// 非取景状态用语义分层填充，深浅色自适应。
    private var viewportFill: AnyShapeStyle {
        switch scanner.phase {
        case .running, .scanned:
            return AnyShapeStyle(Color.black)
        default:
            return AnyShapeStyle(.quaternary)
        }
    }
#endif
}

#if os(iOS)

// MARK: - 取景层

/// AVCaptureVideoPreviewLayer 宿主视图（layerClass 直挂，避免每帧重排）。
private final class AnchorQRPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // layerClass 已锁定为 AVCaptureVideoPreviewLayer，强转安全。
        layer as! AVCaptureVideoPreviewLayer
    }
}

private struct AnchorQRPreviewView: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> AnchorQRPreviewUIView {
        let view = AnchorQRPreviewUIView()
        view.backgroundColor = .clear
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: AnchorQRPreviewUIView, context: Context) {
        if uiView.previewLayer.session !== session {
            uiView.previewLayer.session = session
        }
    }
}

// MARK: - 会话控制器

/// 扫码会话与权限状态机。
///
/// 并发约定（@unchecked Sendable 的理由）：
///   - AVCaptureSession 的配置/启停在 sessionQueue 上串行执行；
///   - 对外可见状态（phase / scannedCode）一律回主队列发布，供 SwiftUI 读取。
final class AnchorQRScannerModel: NSObject, ObservableObject, @unchecked Sendable {
    @Published private(set) var phase: AnchorCameraPhase = .unknown
    @Published private(set) var scannedCode: String?

    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "org.example.hako.anchor.scanner")
    private var isConfigured = false
    private var lastDeliveredCode: String?
    private var lastDeliveredAt = Date.distantPast

    /// 同一二维码 2 秒内只回调一次（取景里每帧都可能命中同一个码）。
    private static let duplicateWindow: TimeInterval = 2

    override init() {
        super.init()
    }

    // MARK: 生命周期

    func start() {
        // 预览宿主没有相机（且会弹权限框），直接给占位文案。
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            phase = .unavailable("预览模式下不启用相机")
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureAndRun()
        case .notDetermined:
            phase = .unknown
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        self.configureAndRun()
                    } else {
                        self.phase = .denied
                    }
                }
            }
        default:
            phase = .denied
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning {
                self.session.stopRunning()
            }
        }
    }

    // MARK: 会话配置

    private func configureAndRun() {
        sessionQueue.async {
            if !self.isConfigured {
                guard self.configureSession() else { return }
                self.isConfigured = true
            }
            if !self.session.isRunning {
                self.session.startRunning()
            }
            DispatchQueue.main.async {
                if self.phase != .scanned {
                    self.phase = .running
                }
            }
        }
    }

    /// 只在 sessionQueue 上调用。
    private func configureSession() -> Bool {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        guard let device = AVCaptureDevice.default(for: .video) else {
            DispatchQueue.main.async { self.phase = .unavailable("没有找到可用的摄像头") }
            return false
        }
        guard let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            DispatchQueue.main.async { self.phase = .unavailable("摄像头初始化失败") }
            return false
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            DispatchQueue.main.async { self.phase = .unavailable("无法建立二维码识别通道") }
            return false
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        // metadataObjectTypes 必须在 addOutput 之后设置。
        output.metadataObjectTypes = [.qr]
        return true
    }

    // MARK: 识别回调（主队列）

    private func deliver(_ code: String) {
        let now = Date()
        if code == lastDeliveredCode,
           now.timeIntervalSince(lastDeliveredAt) < Self.duplicateWindow {
            return
        }
        lastDeliveredCode = code
        lastDeliveredAt = now
        scannedCode = code
        phase = .scanned
        stop()
    }
}

extension AnchorQRScannerModel: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        let candidates = metadataObjects.compactMap {
            $0 as? AVMetadataMachineReadableCodeObject
        }
        guard let value = candidates
            .compactMap({ $0.stringValue })
            .map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty })
        else { return }
        deliver(value)
    }
}

#endif

#if DEBUG
#Preview("扫码区") {
    AnchorQRScannerView(onScan: { _ in })
        .padding(HakoClientUI.HakoTheme.Spacing.standard)
        .background(.quaternary)
}
#endif
