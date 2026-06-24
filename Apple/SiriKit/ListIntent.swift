// ListIntent.swift
// MTRX Apple Integration — SiriKit
// Portfolio watchlists and transaction reminders via Siri

import Intents

// MARK: - List Intent Handler

final class ListIntentHandler: NSObject, INCreateTaskListIntentHandling {

    // MARK: - Properties

    private let portfolioStore = PortfolioWatchlistStore.shared
    private let reminderEngine = TransactionReminderEngine.shared

    // MARK: - Title Resolution

    func resolveTitle(for intent: INCreateTaskListIntent, with completion: @escaping (INSpeakableStringResolutionResult) -> Void) {
        guard let title = intent.title else {
            completion(.needsValue())
            return
        }

        // Map common Siri phrases to Trinity list types
        let normalizedTitle = normalizeTrinityListTitle(title.spokenPhrase)
        let resolved = INSpeakableString(vocabularyIdentifier: normalizedTitle, spokenPhrase: normalizedTitle, pronunciationHint: nil)
        completion(.success(with: resolved))
    }

    // MARK: - Task Titles Resolution

    func resolveTaskTitles(for intent: INCreateTaskListIntent, with completion: @escaping ([INSpeakableStringResolutionResult]) -> Void) {
        guard let taskTitles = intent.taskTitles, !taskTitles.isEmpty else {
            completion([.needsValue()])
            return
        }

        let results = taskTitles.map { title -> INSpeakableStringResolutionResult in
            // Validate token symbols and addresses
            if isValidTokenSymbol(title.spokenPhrase) || isValidAddress(title.spokenPhrase) {
                return .success(with: title)
            }
            return .success(with: title)
        }
        completion(results)
    }

    // MARK: - Confirmation

    func confirm(intent: INCreateTaskListIntent, completion: @escaping (INCreateTaskListIntentResponse) -> Void) {
        guard intent.title != nil else {
            completion(INCreateTaskListIntentResponse(code: .failure, userActivity: nil))
            return
        }
        completion(INCreateTaskListIntentResponse(code: .ready, userActivity: nil))
    }

    // MARK: - Execution

    func handle(intent: INCreateTaskListIntent, completion: @escaping (INCreateTaskListIntentResponse) -> Void) {
        guard let title = intent.title else {
            completion(INCreateTaskListIntentResponse(code: .failure, userActivity: nil))
            return
        }

        let listType = classifyListType(title.spokenPhrase)

        switch listType {
        case .watchlist:
            handleWatchlistCreation(intent: intent, completion: completion)
        case .transactionReminder:
            handleTransactionReminder(intent: intent, completion: completion)
        case .portfolioAlert:
            handlePortfolioAlert(intent: intent, completion: completion)
        case .generic:
            handleGenericList(intent: intent, completion: completion)
        }
    }

    // MARK: - Watchlist Creation

    private func handleWatchlistCreation(intent: INCreateTaskListIntent, completion: @escaping (INCreateTaskListIntentResponse) -> Void) {
        let tokens = intent.taskTitles?.map { $0.spokenPhrase } ?? []

        portfolioStore.createWatchlist(
            name: intent.title?.spokenPhrase ?? "Watchlist",
            tokens: tokens
        ) { result in
            switch result {
            case .success(let watchlist):
                let response = INCreateTaskListIntentResponse(code: .success, userActivity: nil)
                response.createdTaskList = INTaskList(
                    title: intent.title!,
                    tasks: watchlist.tokens.map { token in
                        INTask(
                            title: INSpeakableString(spokenPhrase: token),
                            status: .notCompleted,
                            taskType: .notCompletable,
                            spatialEventTrigger: nil,
                            temporalEventTrigger: nil,
                            createdDateComponents: nil,
                            modifiedDateComponents: nil,
                            identifier: nil
                        )
                    },
                    groupName: INSpeakableString(spokenPhrase: "MTRX Watchlists"),
                    createdDateComponents: Calendar.current.dateComponents(
                        [.year, .month, .day, .hour, .minute],
                        from: Date()
                    ),
                    modifiedDateComponents: nil,
                    identifier: watchlist.id
                )
                completion(response)

            case .failure:
                completion(INCreateTaskListIntentResponse(code: .failure, userActivity: nil))
            }
        }
    }

    // MARK: - Transaction Reminder

    private func handleTransactionReminder(intent: INCreateTaskListIntent, completion: @escaping (INCreateTaskListIntentResponse) -> Void) {
        let tasks = intent.taskTitles?.map { $0.spokenPhrase } ?? []

        reminderEngine.createReminders(tasks: tasks) { success in
            let code: INCreateTaskListIntentResponseCode = success ? .success : .failure
            completion(INCreateTaskListIntentResponse(code: code, userActivity: nil))
        }
    }

    // MARK: - Portfolio Alert

    private func handlePortfolioAlert(intent: INCreateTaskListIntent, completion: @escaping (INCreateTaskListIntentResponse) -> Void) {
        // No alert is stored or scheduled, so don't report the alert as created. Fail honestly
        // rather than telling the user an alert exists that will never fire.
        completion(INCreateTaskListIntentResponse(code: .failure, userActivity: nil))
    }

    // MARK: - Generic List

    private func handleGenericList(intent: INCreateTaskListIntent, completion: @escaping (INCreateTaskListIntentResponse) -> Void) {
        // No generic-list store exists, so nothing is created. Fail honestly instead of
        // confirming a list creation that didn't happen.
        completion(INCreateTaskListIntentResponse(code: .failure, userActivity: nil))
    }

    // MARK: - Classification

    private enum TrinityListType {
        case watchlist
        case transactionReminder
        case portfolioAlert
        case generic
    }

    private func classifyListType(_ title: String) -> TrinityListType {
        let lowered = title.lowercased()
        if lowered.contains("watch") || lowered.contains("track") || lowered.contains("monitor") {
            return .watchlist
        } else if lowered.contains("remind") || lowered.contains("schedule") || lowered.contains("payment") {
            return .transactionReminder
        } else if lowered.contains("alert") || lowered.contains("price") || lowered.contains("threshold") {
            return .portfolioAlert
        }
        return .generic
    }

    private func normalizeTrinityListTitle(_ phrase: String) -> String {
        let lowered = phrase.lowercased()
        if lowered.contains("watch") { return "Token Watchlist" }
        if lowered.contains("remind") { return "Transaction Reminders" }
        if lowered.contains("alert") { return "Portfolio Alerts" }
        return phrase
    }

    private func isValidTokenSymbol(_ symbol: String) -> Bool {
        let pattern = "^[A-Z]{2,10}$"
        return symbol.range(of: pattern, options: .regularExpression) != nil
    }

    private func isValidAddress(_ address: String) -> Bool {
        let pattern = "^0x[0-9a-fA-F]{40}$"
        return address.range(of: pattern, options: .regularExpression) != nil
    }
}

// MARK: - Portfolio Watchlist Store

final class PortfolioWatchlistStore {
    static let shared = PortfolioWatchlistStore()

    struct Watchlist {
        let id: String
        let name: String
        let tokens: [String]
    }

    func createWatchlist(name: String, tokens: [String], completion: @escaping (Result<Watchlist, Error>) -> Void) {
        // Nothing here persists the watchlist — no App Group, no store the main app reads — so
        // it must not report success. The in-memory struct vanishes after this call. Fail
        // honestly until a real persistence path exists, rather than confirming a saved list.
        completion(.failure(NSError(domain: "MTRX.Intent", code: 1, userInfo: [NSLocalizedDescriptionKey:
            "Watchlists aren't available from Siri in this build yet. Nothing was saved."])))
    }
}

// MARK: - Transaction Reminder Engine

final class TransactionReminderEngine {
    static let shared = TransactionReminderEngine()

    func createReminders(tasks: [String], completion: @escaping (Bool) -> Void) {
        // No reminder is scheduled or persisted here (no local-notification scheduling is
        // wired), so do not report success — that would promise a reminder that never fires.
        // Fail honestly until scheduling is wired.
        completion(false)
    }
}
