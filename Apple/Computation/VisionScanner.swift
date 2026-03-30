import Vision
import VisionKit
import UIKit

/// Vision framework document scanning and text extraction for contract reading
@MainActor
final class VisionScanner: NSObject, ObservableObject {
    @Published var recognizedText: String = ""
    @Published var isScanning = false

    private let imageProcessor = CoreImageProcessor()

    /// Extract text from a UIImage using Vision OCR
    func extractText(from image: UIImage) async throws -> String {
        let processed = imageProcessor.processDocumentImage(image) ?? image
        guard let cgImage = processed.cgImage else {
            throw VisionScannerError.invalidImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error { continuation.resume(throwing: error); return }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US"]

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Scan document using VNDocumentCameraViewController
    func presentScanner(from viewController: UIViewController) {
        guard VNDocumentCameraViewController.isSupported else { return }
        let scanner = VNDocumentCameraViewController()
        scanner.delegate = self
        isScanning = true
        viewController.present(scanner, animated: true)
    }

    enum VisionScannerError: Error { case invalidImage, scanCancelled }
}

extension VisionScanner: VNDocumentCameraViewControllerDelegate {
    nonisolated func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
        Task { @MainActor in
            isScanning = false
            controller.dismiss(animated: true)
            var fullText = ""
            for i in 0..<scan.pageCount {
                let pageImage = scan.imageOfPage(at: i)
                if let text = try? await extractText(from: pageImage) {
                    fullText += text + "\n\n"
                }
            }
            recognizedText = fullText.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    nonisolated func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
        Task { @MainActor in isScanning = false; controller.dismiss(animated: true) }
    }

    nonisolated func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
        Task { @MainActor in isScanning = false; controller.dismiss(animated: true) }
    }
}
