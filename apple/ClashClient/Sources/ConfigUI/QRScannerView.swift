import CoreImage
import SwiftUI
#if os(macOS)
import AVFoundation
import AppKit
import UniformTypeIdentifiers
#else
import AVFoundation
import PhotosUI
import UIKit
#endif

enum QRImageDecoderError: Error, Equatable, LocalizedError {
    case notFound
    case unreadableImage

    var errorDescription: String? {
        switch self {
        case .notFound: return "No QR code was found in that image."
        case .unreadableImage: return "The selected image could not be read."
        }
    }
}

enum QRImageDecoder {
    static func decode(_ image: CGImage) throws -> String {
        guard let detector = CIDetector(
            ofType: CIDetectorTypeQRCode,
            context: CIContext(options: nil),
            options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
        ) else {
            throw QRImageDecoderError.unreadableImage
        }
        let features = detector.features(in: CIImage(cgImage: image))
        guard let value = features.compactMap({ ($0 as? CIQRCodeFeature)?.messageString }).first else {
            throw QRImageDecoderError.notFound
        }
        return value
    }
}

#if os(macOS)
 
 
 
 
 
 
 
 
enum QRImagePanel {
    @MainActor
    static func choose(_ completion: @escaping (Result<String, Error>?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "Choose QR Image"
        panel.prompt = "Choose"
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else {
                completion(nil)
                return
            }
            let result: Result<String, Error>
            if let image = NSImage(contentsOf: url),
               let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
            {
                result = Result { try QRImageDecoder.decode(cgImage) }
            } else {
                result = .failure(QRImageDecoderError.unreadableImage)
            }
            completion(result)
        }
    }
}

struct QRPhotoPicker: View {
    let completion: (Result<String, Error>?) -> Void

    @State private var didOpenPanel = false

    var body: some View {
        ProgressView("Choose a QR image…")
            .padding()
            .frame(minWidth: 280, minHeight: 120)
            .onAppear {
                guard !didOpenPanel else { return }
                didOpenPanel = true
                openPanel()
            }
    }

    private func openPanel() { QRImagePanel.choose(completion) }
}
 
 
 
 
 
 
 
struct QRScannerView: NSViewRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeNSView(context: Context) -> ScannerView {
        let view = ScannerView()
        view.start(delegate: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: ScannerView, context: Context) {}

    static func dismantleNSView(_ nsView: ScannerView, coordinator: Coordinator) {
        nsView.stop()
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onCode: (String) -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !delivered,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr, let value = object.stringValue else { return }
            delivered = true
            onCode(value)
        }
    }

    final class ScannerView: NSView {
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var output: AVCaptureMetadataOutput?
         
         
         
         
         
         
        private static let sessionQueue = DispatchQueue(label: "clash.qr.session")
         
         
         
        private var isTornDown = false
         
         
         
        private let unavailable = NSTextField(labelWithString: "")

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            wantsLayer = true
            layer?.backgroundColor = NSColor.black.cgColor
            unavailable.alignment = .center
            unavailable.textColor = .secondaryLabelColor
            unavailable.isHidden = true
            unavailable.translatesAutoresizingMaskIntoConstraints = false
            addSubview(unavailable)
            NSLayoutConstraint.activate([
                unavailable.centerXAnchor.constraint(equalTo: centerXAnchor),
                unavailable.centerYAnchor.constraint(equalTo: centerYAnchor),
                unavailable.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 16),
                unavailable.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -16),
            ])
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

        func start(delegate: AVCaptureMetadataOutputObjectsDelegate) {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                configure(delegate: delegate)
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        guard let self, !self.isTornDown else { return }
                        guard granted else {
                            self.showUnavailable()
                            return
                        }
                        self.configure(delegate: delegate)
                    }
                }
            case .denied, .restricted:
                showUnavailable()
            @unknown default:
                showUnavailable()
            }
        }

         
         
        private func showUnavailable() {
            unavailable.stringValue = ClashCopy.string("Camera unavailable", locale: .current)
            unavailable.isHidden = false
        }

        private func configure(delegate: AVCaptureMetadataOutputObjectsDelegate) {
            guard !isTornDown, preview == nil,
                  let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                showUnavailable()
                return
            }
            let output = AVCaptureMetadataOutput()
            session.beginConfiguration()
            session.addInput(input)
            if session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            self.output = output

             
             
             
             
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = bounds
             
             
             
             
             
            self.layer?.insertSublayer(layer, at: 0)
            preview = layer

            Self.sessionQueue.async { [session] in
                if !session.isRunning { session.startRunning() }
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.isTornDown else { return }
                     
                     
                     
                     
                     
                    output.setMetadataObjectsDelegate(delegate, queue: .main)
                    guard output.availableMetadataObjectTypes.contains(.qr) else {
                        self.showUnavailable()
                        return
                    }
                    output.metadataObjectTypes = [.qr]
                }
            }
        }

        func stop() {
            isTornDown = true
            output?.setMetadataObjectsDelegate(nil, queue: nil)
            output = nil
            preview?.removeFromSuperlayer()
            preview = nil
             
             
            Self.sessionQueue.async { [session] in
                if session.isRunning { session.stopRunning() }
            }
        }

        override func layout() {
            super.layout()
            preview?.frame = bounds
        }
    }
}


#else
 
 
struct QRPhotoPicker: UIViewControllerRepresentable {
    let completion: (Result<String, Error>?) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(completion: completion) }

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.filter = .images
        configuration.selectionLimit = 1
        let controller = PHPickerViewController(configuration: configuration)
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let completion: (Result<String, Error>?) -> Void

        init(completion: @escaping (Result<String, Error>?) -> Void) {
            self.completion = completion
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
             
             
             
             
             
            guard let provider = results.first?.itemProvider else {
                completion(nil)
                return
            }
            provider.loadObject(ofClass: UIImage.self) { [completion] object, error in
                let result: Result<String, Error>
                if let error {
                    result = .failure(error)
                } else if let image = object as? UIImage,
                          let source = image.ciImage ?? CIImage(image: image),
                          let cgImage = CIContext().createCGImage(source, from: source.extent) {
                    result = Result { try QRImageDecoder.decode(cgImage) }
                } else {
                    result = .failure(QRImageDecoderError.unreadableImage)
                }
                DispatchQueue.main.async { completion(result) }
            }
        }
    }
}
 
 
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onCode: (String) -> Void
        private var delivered = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !delivered,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  object.type == .qr, let value = object.stringValue else { return }
            delivered = true
            onCode(value)
        }
    }

    final class ScannerViewController: UIViewController {
        weak var delegate: AVCaptureMetadataOutputObjectsDelegate?
        private let session = AVCaptureSession()
         
        private var canScan = true

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                showUnavailable()
                return
            }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                showUnavailable()
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(delegate, queue: .main)
             
             
             
             
             
             
             
             
             
             
             
             
             
             
             
            guard output.availableMetadataObjectTypes.contains(.qr) else {
                session.removeOutput(output)
                showUnavailable()
                return
            }
            output.metadataObjectTypes = [.qr]

            let preview = AVCaptureVideoPreviewLayer(session: session)
            preview.frame = view.layer.bounds
            preview.videoGravity = .resizeAspectFill
            view.layer.addSublayer(preview)
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            guard canScan else { return }
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                if !session.isRunning { session.startRunning() }
            }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            DispatchQueue.global(qos: .userInitiated).async { [session] in
                if session.isRunning { session.stopRunning() }
            }
        }

         
         
         
         
         
         
        private func showUnavailable() {
            canScan = false
            for output in session.outputs { session.removeOutput(output) }
            for input in session.inputs { session.removeInput(input) }
            let label = UILabel()
            label.text = "Camera unavailable"
            label.textColor = .white
            label.textAlignment = .center
            label.frame = view.bounds
            label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            view.addSubview(label)
        }
    }
}
#endif
