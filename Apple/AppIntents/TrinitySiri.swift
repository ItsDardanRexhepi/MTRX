// TrinitySiri.swift
// MTRX — Trinity
//
// Siri entry point for Trinity: "Hey Siri, ask MTRX…"
//
// Built on App Intents — the modern SiriKit surface (iOS 16+). The
// intent runs Trinity's on-device model (Apple Foundation Models via
// InferenceRouter), so questions that would normally need the online
// chatbot are answered locally, including with no network at all:
// on-device Siri speech → App Intent → local foundation model.
//
// A network probe tells Trinity whether her live tools (getWeather,
// searchWeb) are usable this turn; offline she answers from the model's
// own knowledge and says so when something truly needs live data.

import AppIntents
import Foundation
import Network

// MARK: - Ask Trinity (Siri / Shortcuts / Spotlight)

struct AskTrinityQuestionIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Trinity"
    static var description = IntentDescription(
        "Ask Trinity anything. She answers on-device — even offline.",
        categoryName: "Trinity"
    )

    /// Answer inline in Siri without opening the app.
    static var openAppWhenRun: Bool = false

    @Parameter(
        title: "Question",
        requestValueDialog: "What would you like to ask Trinity?"
    )
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Trinity \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw $question.needsValueError("What would you like to ask Trinity?")
        }

        let online = await TrinitySiriSession.isOnline()
        let answer = await TrinitySiriSession.shared.answer(trimmed, online: online)
        return .result(value: answer, dialog: IntentDialog(stringLiteral: answer))
    }
}

// MARK: - Siri-side Trinity Session

/// On-device engine for Siri turns. Kept separate from the in-app chat
/// so a Siri question never pollutes the conversation context, while
/// still using the same persona, tools, and routing rules.
final class TrinitySiriSession {

    static let shared = TrinitySiriSession()

    private let router = InferenceRouter()

    private init() {}

    func answer(_ question: String, online: Bool) async -> String {
        var context = Self.dateTimeLine()
        context += online
            ? " Internet is reachable — getWeather and searchWeb are available."
            : " The device is OFFLINE: do not call getWeather or searchWeb. Answer entirely from your own knowledge, and say plainly when something truly needs live data."

        if let reply = await router.generateOnDeviceOnly(prompt: question, context: context) {
            return reply
        }

        return online
            ? "I couldn't reach my on-device model just now — try again in a moment, or open MTRX and ask me there."
            : "I answer offline questions with Apple Intelligence, and it isn't available on this device right now. Connect to the internet and ask me in the MTRX app instead."
    }

    /// One-shot reachability check; NWPathMonitor reports the current
    /// path immediately on start.
    static func isOnline() async -> Bool {
        // One-shot latch shared with the @Sendable pathUpdateHandler. A plain
        // local `var` can't be captured/mutated by a @Sendable closure (hard
        // error under the CI toolchain), so the flag lives behind a lock in an
        // @unchecked Sendable box.
        final class OneShot: @unchecked Sendable {
            private let lock = NSLock()
            private var fired = false
            func runOnce(_ body: () -> Void) {
                lock.lock()
                defer { lock.unlock() }
                guard !fired else { return }
                fired = true
                body()
            }
        }
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let gate = OneShot()
            monitor.pathUpdateHandler = { path in
                gate.runOnce {
                    continuation.resume(returning: path.status == .satisfied)
                    monitor.cancel()
                }
            }
            monitor.start(queue: DispatchQueue(label: "com.mtrx.trinity.netcheck"))
        }
    }

    /// Same live-clock context line Trinity gets in the in-app chat.
    private static func dateTimeLine() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMMM d, yyyy 'at' h:mm a"
        let zone = TimeZone.current.localizedName(for: .shortGeneric, locale: .current)
            ?? TimeZone.current.identifier
        return "Current local date and time: \(formatter.string(from: Date())) (\(zone))."
    }
}

// The Siri phrases for this intent are registered in
// MTRXShortcutsProvider (Apple/AppIntents/ShortcutsProvider.swift) —
// iOS allows exactly one AppShortcutsProvider per app.
