import AVFoundation
import SwiftUI

/// Scans a wallet QR code. `onScan` returns nil to accept a code (the caller
/// closes the sheet) or a message saying why it can't be used; the scanner
/// then stays open for another try.
struct QRScannerSheet: View {
    let onScan: (String) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var permission = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var rejection: String?
    private let hasCamera = AVCaptureDevice.default(for: .video) != nil

    var body: some View {
        NavigationStack {
            Group {
                if !hasCamera {
                    unavailable(title: "No camera available", symbol: "camera.fill",
                                message: "This device can't scan QR codes. Paste the address instead.")
                } else {
                    switch permission {
                    case .authorized:
                        CameraScanner { value in
                            rejection = onScan(value)
                            return rejection == nil
                        }
                        .ignoresSafeArea()
                        .overlay {
                            RoundedRectangle(cornerRadius: Theme.Radius.panel)
                                .stroke(rejection == nil ? .white.opacity(0.9) : Theme.Palette.danger, lineWidth: 3)
                                .frame(width: 250, height: 250)
                                .accessibilityHidden(true)
                        }
                        .overlay(alignment: .bottom) { scanHint }
                    case .notDetermined:
                        ProgressView().task {
                            _ = await AVCaptureDevice.requestAccess(for: .video)
                            permission = AVCaptureDevice.authorizationStatus(for: .video)
                        }
                    default:
                        unavailable(title: "Camera access is off", symbol: "camera.fill",
                                    message: "Allow camera access in Settings to scan an address, or paste it instead.",
                                    settings: true)
                    }
                }
            }
            .navigationTitle("Scan address")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }

    /// What to point at, or why the last code didn't work.
    private var scanHint: some View {
        Label {
            Group {
                if let rejection { Text(rejection) } else { Text("Point the camera at a TRON address QR code") }
            }
            .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: rejection == nil ? "qrcode" : "exclamationmark.triangle.fill")
        }
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(rejection == nil ? AnyShapeStyle(.black.opacity(0.6)) : AnyShapeStyle(Theme.Palette.danger), in: .rect(cornerRadius: Theme.Radius.m))
        .padding(.horizontal, Theme.Spacing.screen)
        .padding(.bottom, 40)
        .animation(.snappy, value: rejection)
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func unavailable(title: LocalizedStringKey, symbol: String, message: LocalizedStringKey,
                             settings: Bool = false) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbol)
        } description: {
            VStack(spacing: 8) {
                Text(message)
                if let rejection { Text(rejection).foregroundStyle(Theme.Palette.danger) }
            }
        } actions: {
            if settings {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            Button("Paste address") {
                guard let text = Clipboard.string, !text.isEmpty else {
                    rejection = tr("There's nothing to paste. Copy an address first.")
                    return
                }
                rejection = onScan(text)
            }
        }
    }
}

private struct CameraScanner: UIViewControllerRepresentable {
    /// true accepts the code; false keeps scanning.
    let onScan: (String) -> Bool

    func makeUIViewController(context: Context) -> ScannerController {
        let controller = ScannerController()
        controller.onScan = onScan
        return controller
    }

    func updateUIViewController(_ controller: ScannerController, context: Context) {}
}

final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Bool)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var delivered = false
    /// The last code turned down: the camera sees it many times a second, so it's ignored until another appears.
    private var lastRejected: String?
    /// Keeps the preview upright as an iPad (or unfolded iPhone) turns.
    private var rotation: AVCaptureDevice.RotationCoordinator?
    private var rotationObservation: NSKeyValueObservation?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer

        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
        rotation = coordinator
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            Task { @MainActor in self?.applyPreviewRotation(angle) }
        }

        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.startRunning() }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = previewLayer?.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        let session = self.session
        DispatchQueue.global(qos: .userInitiated).async { session.stopRunning() }
    }

    nonisolated func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        MainActor.assumeIsolated {
            guard !delivered, value != lastRejected else { return }
            if onScan?(value) == true {
                delivered = true
                Haptics.success()
            } else {
                lastRejected = value
                Haptics.error()
            }
        }
    }
}
