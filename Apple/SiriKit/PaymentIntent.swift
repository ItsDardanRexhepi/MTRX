// PaymentIntent.swift
// MTRX Apple Integration — SiriKit
// Send ETH and tokens via Siri with biometric confirmation

import Intents
import LocalAuthentication

// MARK: - Payment Intent Handler

final class PaymentIntentHandler: NSObject, INSendPaymentIntentHandling {

    // MARK: - Properties

    private let authContext = LAContext()
    private let minimumConfirmationThreshold: Decimal = 0.01 // ETH
    private let maximumSiriTransactionLimit: Decimal = 1.0   // ETH

    // MARK: - Amount Resolution

    func resolvePayee(for intent: INSendPaymentIntent, with completion: @escaping (INPersonResolutionResult) -> Void) {
        guard let payee = intent.payee else {
            completion(.needsValue())
            return
        }

        // Resolve against known wallet addresses and ENS names
        TrinityContactResolver.shared.resolveWalletContact(payee) { resolvedContact in
            if let contact = resolvedContact {
                completion(.success(with: contact))
            } else {
                completion(.unsupported(forReason: .noAccount))
            }
        }
    }

    func resolveCurrencyAmount(for intent: INSendPaymentIntent, with completion: @escaping (INCurrencyAmountResolutionResult) -> Void) {
        guard let currencyAmount = intent.currencyAmount,
              let amount = currencyAmount.amount?.decimalValue else {
            completion(.needsValue())
            return
        }

        // Validate amount is within Siri transaction limits
        if amount <= 0 {
            completion(.unsupported(forReason: .amountsDoNotMatch))
            return
        }

        if amount > maximumSiriTransactionLimit {
            completion(.confirmationRequired(with: currencyAmount))
            return
        }

        completion(.success(with: currencyAmount))
    }

    // MARK: - Confirmation

    func confirm(intent: INSendPaymentIntent, completion: @escaping (INSendPaymentIntentResponse) -> Void) {
        guard let amount = intent.currencyAmount?.amount?.decimalValue else {
            completion(INSendPaymentIntentResponse(code: .failure, userActivity: nil))
            return
        }

        // Require biometric authentication for all payments
        authenticateWithBiometrics(reason: "Confirm ETH payment of \(amount)") { [weak self] success in
            guard success else {
                completion(INSendPaymentIntentResponse(code: .failureRequiringAppLaunch, userActivity: nil))
                return
            }

            // Validate gas estimation
            self?.estimateGas(for: amount) { gasEstimate in
                if gasEstimate != nil {
                    completion(INSendPaymentIntentResponse(code: .ready, userActivity: nil))
                } else {
                    completion(INSendPaymentIntentResponse(code: .failure, userActivity: nil))
                }
            }
        }
    }

    // MARK: - Execution

    func handle(intent: INSendPaymentIntent, completion: @escaping (INSendPaymentIntentResponse) -> Void) {
        guard let payee = intent.payee,
              let currencyAmount = intent.currencyAmount,
              let amount = currencyAmount.amount?.decimalValue else {
            completion(INSendPaymentIntentResponse(code: .failure, userActivity: nil))
            return
        }

        // Execute the transaction through Trinity's transaction engine
        TrinityTransactionEngine.shared.executePayment(
            to: payee.displayName ?? "",
            amount: amount,
            currency: currencyAmount.currencyCode ?? "ETH"
        ) { result in
            switch result {
            case .success(let txHash):
                let response = INSendPaymentIntentResponse(code: .success, userActivity: nil)
                response.paymentRecord = self.buildPaymentRecord(
                    payee: payee,
                    amount: currencyAmount,
                    transactionHash: txHash
                )
                completion(response)

            case .failure:
                completion(INSendPaymentIntentResponse(code: .failure, userActivity: nil))
            }
        }
    }

    // MARK: - Biometric Authentication

    private func authenticateWithBiometrics(reason: String, completion: @escaping (Bool) -> Void) {
        var error: NSError?
        guard authContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            completion(false)
            return
        }

        authContext.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, _ in
            DispatchQueue.main.async {
                completion(success)
            }
        }
    }

    // MARK: - Gas Estimation

    private func estimateGas(for amount: Decimal, completion: @escaping (Decimal?) -> Void) {
        // Delegate to Trinity's gas estimation oracle
        TrinityGasOracle.shared.estimate(for: amount, completion: completion)
    }

    // MARK: - Payment Record

    private func buildPaymentRecord(payee: INPerson, amount: INCurrencyAmount, transactionHash: String) -> INPaymentRecord {
        let status = INPaymentStatus.completed
        return INPaymentRecord(
            payee: payee,
            payer: nil,
            currencyAmount: amount,
            paymentMethod: INPaymentMethod(type: .unknown, name: "Ethereum", identificationHint: nil, icon: nil),
            note: "TX: \(transactionHash)",
            status: status
        )
    }
}

// MARK: - Trinity Contact Resolver (Stub)

final class TrinityContactResolver {
    static let shared = TrinityContactResolver()
    func resolveWalletContact(_ person: INPerson, completion: @escaping (INPerson?) -> Void) {
        completion(person)
    }
}

// MARK: - Trinity Transaction Engine (Stub)

final class TrinityTransactionEngine {
    static let shared = TrinityTransactionEngine()

    func executePayment(to recipient: String, amount: Decimal, currency: String, completion: @escaping (Result<String, Error>) -> Void) {
        // Bridge to MTRX transaction layer
        completion(.failure(NSError(domain: "com.mtrx.trinity", code: -1, userInfo: [NSLocalizedDescriptionKey: "Not yet connected to MTRX backend"])))
    }
}

// MARK: - Trinity Gas Oracle (Stub)

final class TrinityGasOracle {
    static let shared = TrinityGasOracle()
    func estimate(for amount: Decimal, completion: @escaping (Decimal?) -> Void) {
        completion(nil)
    }
}
