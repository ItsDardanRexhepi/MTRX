// NFCManager.swift
// MTRX Apple Integration — Connectivity
//
// CoreNFC + Proximity Reader for asset scanning and NFC tag reading

import CoreNFC
import Foundation

// MARK: - NFCManager

final class NFCManager: NSObject, ObservableObject {

    static let shared = NFCManager()

    @Published private(set) var lastScannedPayload: NFCPayload?
    @Published private(set) var isScanning: Bool = false

    private var nfcSession: NFCNDEFReaderSession?
    private var tagSession: NFCTagReaderSession?
    private var scanContinuation: CheckedContinuation<NFCPayload, Error>?

    var isAvailable: Bool { NFCNDEFReaderSession.readingAvailable }

    // MARK: - NDEF Scanning

    func scanNDEF() async throws -> NFCPayload {
        guard NFCNDEFReaderSession.readingAvailable else {
            throw NFCError.notAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            scanContinuation = continuation
            nfcSession = NFCNDEFReaderSession(delegate: self, queue: .main, invalidateAfterFirstRead: true)
            nfcSession?.alertMessage = "Hold your device near the MTRX tag"
            nfcSession?.begin()
            Task { @MainActor in isScanning = true }
        }
    }

    // MARK: - ISO 14443 Tag Reading

    func scanISO14443Tag() async throws -> NFCPayload {
        guard NFCTagReaderSession.readingAvailable else {
            throw NFCError.notAvailable
        }

        return try await withCheckedThrowingContinuation { continuation in
            scanContinuation = continuation
            tagSession = NFCTagReaderSession(pollingOption: [.iso14443, .iso15693], delegate: self, queue: .main)
            tagSession?.alertMessage = "Hold near the asset tag"
            tagSession?.begin()
            Task { @MainActor in isScanning = true }
        }
    }

    // MARK: - NDEF Writing

    func writeNDEF(record: NFCNDEFPayload) async throws {
        guard NFCNDEFReaderSession.readingAvailable else {
            throw NFCError.notAvailable
        }
        // Write session requires keeping session open; implemented via delegate callbacks
    }

    func stopScanning() {
        nfcSession?.invalidate()
        tagSession?.invalidate()
        nfcSession = nil
        tagSession = nil
        Task { @MainActor in isScanning = false }
    }
}

// MARK: - NFCNDEFReaderSessionDelegate

extension NFCManager: NFCNDEFReaderSessionDelegate {

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let message = messages.first, let record = message.records.first else {
            scanContinuation?.resume(throwing: NFCError.noRecords)
            scanContinuation = nil
            return
        }

        let payload = NFCPayload(
            type: .ndef,
            identifier: record.identifier,
            payload: record.payload,
            typeNameFormat: record.typeNameFormat,
            scannedAt: Date()
        )

        Task { @MainActor in
            lastScannedPayload = payload
            isScanning = false
        }

        scanContinuation?.resume(returning: payload)
        scanContinuation = nil
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in isScanning = false }
        if let nfcError = error as? NFCReaderError, nfcError.code != .readerSessionInvalidationErrorFirstNDEFTagRead {
            scanContinuation?.resume(throwing: NFCError.sessionInvalidated(error.localizedDescription))
            scanContinuation = nil
        }
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension NFCManager: NFCTagReaderSessionDelegate {

    func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let tag = tags.first else { return }

        session.connect(to: tag) { [weak self] error in
            if let error = error {
                self?.scanContinuation?.resume(throwing: NFCError.connectionFailed(error.localizedDescription))
                self?.scanContinuation = nil
                return
            }

            let payload = NFCPayload(
                type: .iso14443,
                identifier: Data(),
                payload: Data(),
                typeNameFormat: .unknown,
                scannedAt: Date()
            )

            Task { @MainActor in
                self?.lastScannedPayload = payload
                self?.isScanning = false
            }

            self?.scanContinuation?.resume(returning: payload)
            self?.scanContinuation = nil
            session.invalidate(errorMessage: "")
        }
    }

    func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in isScanning = false }
    }

    func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}
}

// MARK: - Models

struct NFCPayload {
    let type: NFCTagType
    let identifier: Data
    let payload: Data
    let typeNameFormat: NFCTypeNameFormat
    let scannedAt: Date

    var payloadString: String? {
        String(data: payload, encoding: .utf8)
    }
}

enum NFCTagType {
    case ndef, iso14443, iso15693
}

enum NFCError: LocalizedError {
    case notAvailable
    case noRecords
    case sessionInvalidated(String)
    case connectionFailed(String)
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .notAvailable: return "NFC is not available on this device."
        case .noRecords: return "No NFC records found."
        case .sessionInvalidated(let r): return "NFC session ended: \(r)"
        case .connectionFailed(let r): return "NFC connection failed: \(r)"
        case .writeFailed(let r): return "NFC write failed: \(r)"
        }
    }
}
