//
//  QRCodeScannerView.swift
//  MTRX
//
//  A real AVFoundation QR-code scanner, exposed to SwiftUI as a
//  UIViewControllerRepresentable. Uses AVCaptureMetadataOutput (.qr) for robust
//  live decoding. Requests camera permission on first use and surfaces a clear
//  error instead of a black screen when access is denied or unavailable.
//
//  Camera usage is already declared in Info.plist (NSCameraUsageDescription).
//

import SwiftUI
import AVFoundation

struct QRCodeScannerView: UIViewControllerRepresentable {

    /// Called once with the first decoded QR string. The presenter should dismiss.
    var onScan: (String) -> Void
    /// Called with a human-readable reason when scanning can't start.
    var onError: ((String) -> Void)?

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onScan = onScan
        controller.onError = onError
        return controller
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

final class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {

    var onScan: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var isConfigured = false
    private var didScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestAccessAndConfigure()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSessionIfReady()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    // MARK: - Setup

    private func requestAccessAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
            startSessionIfReady()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self else { return }
                    if granted {
                        self.configureSession()
                        self.startSessionIfReady()
                    } else {
                        self.onError?("Camera access is needed to scan QR codes. Enable it in Settings.")
                    }
                }
            }
        default:
            onError?("Camera access is off. Enable it for MTRX in Settings to scan QR codes.")
        }
    }

    private func configureSession() {
        guard !isConfigured else { return }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            onError?("This device's camera isn't available for scanning.")
            return
        }
        session.beginConfiguration()
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            onError?("QR scanning isn't supported on this device.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.videoGravity = .resizeAspectFill
        preview.frame = view.bounds
        view.layer.addSublayer(preview)
        previewLayer = preview

        isConfigured = true
    }

    private func startSessionIfReady() {
        guard isConfigured, !session.isRunning else { return }
        // startRunning blocks; keep it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
        }
    }

    // MARK: - AVCaptureMetadataOutputObjectsDelegate

    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !didScan,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let value = object.stringValue, !value.isEmpty else { return }

        didScan = true
        session.stopRunning()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onScan?(value)
    }
}

// MARK: - Presentable scanner sheet

/// A full-screen QR scanner with a cancel control and inline error/hint text.
/// Present from any feature via `.fullScreenCover` and receive the decoded
/// string in `onScan` (the sheet dismisses itself on a successful scan).
struct QRScannerSheet: View {

    let title: String
    let onScan: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            QRCodeScannerView(
                onScan: { value in
                    onScan(value)
                    dismiss()
                },
                onError: { errorMessage = $0 }
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Close scanner")
                }
                .padding()

                Spacer()

                Text(errorMessage ?? "Point the camera at a QR code")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(.bottom, 40)
            }
        }
    }
}
