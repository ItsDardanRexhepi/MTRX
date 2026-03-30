// PhotosManager.swift
// MTRX Apple Integration — Interaction
//
// Document scanning from photo library for contract and identity verification

import Photos
import PhotosUI
import SwiftUI
import Vision

// MARK: - PhotosManager

final class PhotosManager: ObservableObject {

    static let shared = PhotosManager()

    @Published private(set) var isAuthorized: Bool = false
    @Published private(set) var isProcessing: Bool = false

    // MARK: - Authorization

    func requestAccess() async {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        await MainActor.run { isAuthorized = status == .authorized || status == .limited }
    }

    // MARK: - Document Scanning from Image

    func scanDocument(from imageData: Data) async throws -> DocumentScanResult {
        await MainActor.run { isProcessing = true }
        defer { Task { @MainActor in isProcessing = false } }

        guard let cgImage = createCGImage(from: imageData) else {
            throw PhotosError.invalidImage
        }

        let recognizedText = try await recognizeText(in: cgImage)
        let rectangles = try await detectRectangles(in: cgImage)

        return DocumentScanResult(
            text: recognizedText,
            rectangleCount: rectangles.count,
            imageSize: CGSize(width: cgImage.width, height: cgImage.height),
            scannedAt: Date()
        )
    }

    // MARK: - Text Recognition

    private func recognizeText(in image: CGImage) async throws -> String {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: PhotosError.recognitionFailed(error.localizedDescription))
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let text = observations.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
                continuation.resume(returning: text)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: PhotosError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Rectangle Detection

    private func detectRectangles(in image: CGImage) async throws -> [VNRectangleObservation] {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: PhotosError.recognitionFailed(error.localizedDescription))
                    return
                }
                let rectangles = request.results as? [VNRectangleObservation] ?? []
                continuation.resume(returning: rectangles)
            }
            request.maximumObservations = 10
            request.minimumConfidence = 0.8

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: PhotosError.recognitionFailed(error.localizedDescription))
            }
        }
    }

    // MARK: - Image Processing

    func processIdentityDocument(imageData: Data) async throws -> IdentityDocumentData {
        let scanResult = try await scanDocument(from: imageData)
        return IdentityDocumentData(
            rawText: scanResult.text,
            extractedFields: extractFields(from: scanResult.text),
            scannedAt: Date()
        )
    }

    private func extractFields(from text: String) -> [String: String] {
        var fields: [String: String] = [:]
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(":") {
                let parts = line.split(separator: ":", maxSplits: 1)
                if parts.count == 2 {
                    fields[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        return fields
    }

    // MARK: - Helpers

    private func createCGImage(from data: Data) -> CGImage? {
        guard let uiImage = UIImage(data: data) else { return nil }
        return uiImage.cgImage
    }
}

// MARK: - Models

struct DocumentScanResult {
    let text: String
    let rectangleCount: Int
    let imageSize: CGSize
    let scannedAt: Date
}

struct IdentityDocumentData {
    let rawText: String
    let extractedFields: [String: String]
    let scannedAt: Date
}

enum PhotosError: LocalizedError {
    case notAuthorized
    case invalidImage
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Photos access not authorized."
        case .invalidImage: return "Could not process the image."
        case .recognitionFailed(let r): return "Document recognition failed: \(r)"
        }
    }
}
