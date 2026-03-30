// MessageIntent.swift
// MTRX Apple Integration — SiriKit
// XMTP encrypted messaging via Siri

import Intents

// MARK: - Message Intent Handler

final class MessageIntentHandler: NSObject, INSendMessageIntentHandling {

    // MARK: - Properties

    private let xmtpBridge = XMTPBridge.shared
    private let encryptionService = MessageEncryptionService.shared

    // MARK: - Recipient Resolution

    func resolveRecipients(for intent: INSendMessageIntent, with completion: @escaping ([INSendMessageRecipientResolutionResult]) -> Void) {
        guard let recipients = intent.recipients, !recipients.isEmpty else {
            completion([.needsValue()])
            return
        }

        var results: [INSendMessageRecipientResolutionResult] = []

        for recipient in recipients {
            // Resolve ENS names and wallet addresses for XMTP
            if let handle = recipient.personHandle?.value {
                if isValidXMTPAddress(handle) {
                    results.append(.success(with: recipient))
                } else {
                    // Attempt ENS resolution
                    resolveENSToXMTP(handle) { resolvedPerson in
                        if let person = resolvedPerson {
                            results.append(.success(with: person))
                        } else {
                            results.append(.unsupported(forReason: .noHandleForLabel))
                        }
                    }
                }
            } else {
                results.append(.needsValue())
            }
        }

        completion(results)
    }

    // MARK: - Content Resolution

    func resolveContent(for intent: INSendMessageIntent, with completion: @escaping (INStringResolutionResult) -> Void) {
        guard let content = intent.content, !content.isEmpty else {
            completion(.needsValue())
            return
        }

        // Validate message content doesn't contain sensitive data patterns
        if containsSensitivePatterns(content) {
            completion(.confirmationRequired(with: "[Redacted — contains sensitive data]"))
            return
        }

        completion(.success(with: content))
    }

    // MARK: - Confirmation

    func confirm(intent: INSendMessageIntent, completion: @escaping (INSendMessageIntentResponse) -> Void) {
        guard let recipients = intent.recipients, !recipients.isEmpty,
              let content = intent.content, !content.isEmpty else {
            completion(INSendMessageIntentResponse(code: .failure, userActivity: nil))
            return
        }

        // Check XMTP client connectivity
        xmtpBridge.checkConnectivity { isConnected in
            if isConnected {
                completion(INSendMessageIntentResponse(code: .ready, userActivity: nil))
            } else {
                completion(INSendMessageIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil))
            }
        }
    }

    // MARK: - Execution

    func handle(intent: INSendMessageIntent, completion: @escaping (INSendMessageIntentResponse) -> Void) {
        guard let recipients = intent.recipients,
              let content = intent.content else {
            completion(INSendMessageIntentResponse(code: .failure, userActivity: nil))
            return
        }

        let addresses = recipients.compactMap { $0.personHandle?.value }

        // Encrypt and send via XMTP
        encryptionService.encrypt(message: content) { [weak self] encryptedPayload in
            guard let encryptedPayload = encryptedPayload else {
                completion(INSendMessageIntentResponse(code: .failure, userActivity: nil))
                return
            }

            self?.xmtpBridge.send(
                encryptedPayload: encryptedPayload,
                to: addresses
            ) { result in
                switch result {
                case .success(let messageId):
                    let response = INSendMessageIntentResponse(code: .success, userActivity: nil)
                    response.sentMessages = [
                        INMessage(
                            identifier: messageId,
                            conversationIdentifier: addresses.first ?? "",
                            content: content,
                            dateSent: Date(),
                            sender: INPerson(
                                personHandle: INPersonHandle(value: "self", type: .unknown),
                                nameComponents: nil,
                                displayName: "You",
                                image: nil,
                                contactIdentifier: nil,
                                customIdentifier: nil
                            ),
                            recipients: recipients,
                            groupName: nil,
                            messageType: .text
                        )
                    ]
                    completion(response)

                case .failure:
                    completion(INSendMessageIntentResponse(code: .failure, userActivity: nil))
                }
            }
        }
    }

    // MARK: - XMTP Address Validation

    private func isValidXMTPAddress(_ address: String) -> Bool {
        // Validate Ethereum address format (0x + 40 hex chars) or ENS name
        let ethPattern = "^0x[0-9a-fA-F]{40}$"
        let ensPattern = "^[a-zA-Z0-9-]+\\.eth$"
        return address.range(of: ethPattern, options: .regularExpression) != nil ||
               address.range(of: ensPattern, options: .regularExpression) != nil
    }

    private func resolveENSToXMTP(_ name: String, completion: @escaping (INPerson?) -> Void) {
        xmtpBridge.resolveENS(name) { address in
            guard let address = address else {
                completion(nil)
                return
            }
            let person = INPerson(
                personHandle: INPersonHandle(value: address, type: .unknown),
                nameComponents: nil,
                displayName: name,
                image: nil,
                contactIdentifier: nil,
                customIdentifier: address
            )
            completion(person)
        }
    }

    // MARK: - Sensitive Data Detection

    private func containsSensitivePatterns(_ content: String) -> Bool {
        let patterns = [
            "\\b[0-9a-fA-F]{64}\\b",     // Private keys
            "\\b\\d{4}[- ]?\\d{4}[- ]?\\d{4}[- ]?\\d{4}\\b", // Card numbers
            "\\bseed phrase\\b",
            "\\bmnemonic\\b"
        ]
        return patterns.contains { content.range(of: $0, options: .regularExpression) != nil }
    }
}

// MARK: - XMTP Bridge

final class XMTPBridge {
    static let shared = XMTPBridge()

    func checkConnectivity(completion: @escaping (Bool) -> Void) {
        completion(false)
    }

    func send(encryptedPayload: Data, to addresses: [String], completion: @escaping (Result<String, Error>) -> Void) {
        completion(.failure(NSError(domain: "com.mtrx.xmtp", code: -1, userInfo: nil)))
    }

    func resolveENS(_ name: String, completion: @escaping (String?) -> Void) {
        completion(nil)
    }
}

// MARK: - Message Encryption Service

final class MessageEncryptionService {
    static let shared = MessageEncryptionService()

    func encrypt(message: String, completion: @escaping (Data?) -> Void) {
        guard let data = message.data(using: .utf8) else {
            completion(nil)
            return
        }
        // Placeholder: XMTP uses Signal protocol encryption
        completion(data)
    }
}
