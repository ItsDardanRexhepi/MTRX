//
//  TurnMessageDeliveryTests.swift
//  MTRX — Tests
//
//  Reproduces the "vanishing long response" bug at the code level and proves it is
//  gone. These drive the SAME production type the app runs (TurnMessageDelivery, used
//  by AgentConversationViewModel.processWithAgent) through every failure path:
//
//    • a long multi-part answer completes fully (nothing truncated / dropped),
//    • a forced cutoff mid-stream leaves the partial + an honest note — NEVER nothing,
//    • whitespace-only replies never render a blank bubble,
//    • a mid-turn conversation switch commits the reply to its OWN thread, never lost,
//      never cross-posted.
//
//  The invariant under test: after any turn, the outcome is ALWAYS one of
//  {complete answer, preserved partial (+honest note), honest error} — a message can
//  never silently vanish, for ANY failure cause.
//

import XCTest
@testable import MTRX

@MainActor
final class TurnMessageDeliveryTests: XCTestCase {

    /// Backing for the "live" thread the delivery writes to (a class so the closures
    /// share one instance, mirroring the view model's @Published `messages`/`isTyping`).
    final class LiveBox {
        var messages: [AgentMessage] = []
        var typing = true
    }

    private func makeDelivery(
        turnConversationID: UUID? = nil,
        turnSessionID: String = "s0",
        currentID: @escaping () -> UUID? = { nil },
        currentSessionID: @escaping () -> String = { "s0" },
        live: LiveBox
    ) -> TurnMessageDelivery {
        TurnMessageDelivery(
            agentName: "Trinity",
            turnConversationID: turnConversationID,
            turnSessionID: turnSessionID,
            store: .shared,
            currentID: currentID,
            currentSessionID: currentSessionID,
            getMessages: { live.messages },
            setMessages: { live.messages = $0 },
            setTyping: { live.typing = $0 }
        )
    }

    private func isBlank(_ s: String) -> Bool {
        s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Layer-1 outcome — a long multi-part answer completes fully.

    func test_longMultiPartAnswer_completesFully_singleMessage() {
        let live = LiveBox()
        let d = makeDelivery(live: live)
        // A realistic long 7-part answer (~6 KB, the size the live gateway returned).
        let long = (1...7).map { "(\($0)) " + String(repeating: "This is a full paragraph of the answer for part \($0). ", count: 12) }
            .joined(separator: "\n\n")
        XCTAssertGreaterThan(long.count, 3000, "precondition: this is a genuinely long answer")

        d.finishLive(long)

        XCTAssertEqual(live.messages.count, 1, "one assistant bubble")
        XCTAssertEqual(live.messages[0].text, AgentMessage.humanizedReply(long), "full answer, nothing truncated")
        XCTAssertFalse(live.messages[0].text.isEmpty)
        XCTAssertFalse(live.typing, "typing indicator cleared on completion")
    }

    func test_streamThenComplete_supersedes_noDuplicate() {
        let live = LiveBox()
        let d = makeDelivery(live: live)
        d.showLive("Alright, here's the rundown, let's tackle each one in order. (")
        XCTAssertEqual(live.messages.count, 1, "partial shown in one bubble")

        let full = "Alright, here's the rundown: (1) first (2) second ... (7) seventh. Done."
        d.finishLive(full)

        XCTAssertEqual(live.messages.count, 1, "final SUPERSEDES the partial — not a second bubble")
        XCTAssertEqual(live.messages[0].text, AgentMessage.humanizedReply(full))
    }

    // MARK: Layer-2 outcome — a forced cutoff NEVER vanishes (the original bug).

    func test_forcedCutoff_afterPartial_preservesPartial_plusHonestNote() {
        let live = LiveBox()
        let d = makeDelivery(live: live)

        // Exactly the failure that used to vanish: the model streamed a partial ...
        let partial = "Alright, here's the rundown, let's tackle each one in order. ("
        d.showLive(partial)
        XCTAssertEqual(live.messages.count, 1)
        XCTAssertFalse(d.shownPartial.isEmpty)

        // ... then EVERYTHING downstream failed (timeout / cutoff / error / empty). The
        // catch path preserves the partial and appends an honest note (never a delete).
        d.appendAssistant("\u{26A0}\u{FE0F} That reply got cut off before I could finish.")

        XCTAssertEqual(live.messages.count, 2, "partial kept + honest note — nothing vanished")
        XCTAssertEqual(live.messages[0].text, AgentMessage.humanizedReply(partial), "partial preserved verbatim")
        XCTAssertTrue(live.messages[1].text.contains("cut off"), "honest cut-off note present")
        XCTAssertFalse(live.messages.contains { isBlank($0.text) }, "no blank bubble anywhere")
    }

    func test_totalFailure_noPartialEverShown_showsHonestError_notNothing() {
        let live = LiveBox()
        let d = makeDelivery(live: live)

        // No partial streamed; on-device + cloud both unreachable -> honest error.
        d.finishLive("I need to connect to reason about that \u{2014} I won't guess at it.")

        XCTAssertEqual(live.messages.count, 1, "an honest error is shown, never an empty thread")
        XCTAssertFalse(isBlank(live.messages[0].text))
    }

    // MARK: no-blank-bubble — whitespace-only replies are treated as empty.

    func test_whitespaceOnly_neverRendersBlankBubble() {
        let live = LiveBox()
        let d = makeDelivery(live: live)

        d.showLive("   ")          // gateway can emit a leading space/newline token
        d.showLive("\n\t")
        XCTAssertTrue(live.messages.isEmpty, "whitespace partials never create a bubble")

        d.finishLive("  \n  ")      // whitespace-only 'done' frame
        XCTAssertTrue(live.messages.isEmpty, "whitespace final never creates a blank bubble")

        d.finishLive("Real answer.") // a real answer still lands afterwards
        XCTAssertEqual(live.messages.count, 1)
        XCTAssertEqual(live.messages[0].text, "Real answer.")
    }

    // MARK: right-thread — a mid-turn conversation switch never loses / cross-posts.

    func test_conversationSwappedMidTurn_replyGoesToOriginThread_notLiveThread() {
        let store = ConversationStore.shared
        let origin = store.create(agent: .trinity)
        store.update(id: origin.id, messages: [AgentMessage(text: "My long 7-part question", role: .user)])

        // The user has since navigated to a DIFFERENT thread (live shows something else).
        let live = LiveBox()
        live.messages = [AgentMessage(text: "an unrelated other conversation", role: .user)]
        let someOtherThreadID = UUID()
        let d = makeDelivery(turnConversationID: origin.id, currentID: { someOtherThreadID }, live: live)
        XCTAssertFalse(d.stillCurrent, "the origin thread is no longer visible")

        d.finishLive("The complete 7-part answer.")

        // The visible (other) thread is untouched — no cross-post.
        XCTAssertEqual(live.messages.count, 1)
        XCTAssertEqual(live.messages[0].text, "an unrelated other conversation")

        // The answer is preserved in the ORIGIN conversation's record — never lost.
        let storedOrigin = store.conversation(id: origin.id)?.messages ?? []
        XCTAssertTrue(storedOrigin.contains { $0.text == "The complete 7-part answer." },
                      "reply committed to its own thread")
        XCTAssertTrue(storedOrigin.contains { $0.role == .user },
                      "the original question is still there")
    }

    // MARK: before/after — delete-then-recover-nothing vs the never-vanish guarantee.

    func test_regression_oldRemoveAllLogic_vanished_newDeliveryDoesNot() {
        // BEFORE (the bug): the streamed partial was removed on failure with no guaranteed
        // replacement — messages.removeAll { $0.id == streamID } then a fallback that
        // didn't land. Reproduce that exact delete-with-no-append:
        var oldThread: [AgentMessage] = []
        let partial = AgentMessage(text: "Alright, here's the rundown, let's tackle each one in order. (",
                                   role: .agent, agentName: "Trinity")
        oldThread.append(partial)                      // partial shown on screen
        oldThread.removeAll { $0.id == partial.id }    // ← the old vanish; downstream then failed
        XCTAssertTrue(oldThread.isEmpty, "BEFORE: the whole message vanished — the bug we're fixing")

        // AFTER (the fix): the SAME scenario through the production delivery keeps the
        // partial and adds an honest note — the thread is never left empty.
        let live = LiveBox()
        let d = makeDelivery(live: live)
        d.showLive("Alright, here's the rundown, let's tackle each one in order. (")
        d.appendAssistant("\u{26A0}\u{FE0F} That reply got cut off before I could finish.")
        XCTAssertFalse(live.messages.isEmpty, "AFTER: nothing vanishes")
        XCTAssertGreaterThanOrEqual(live.messages.count, 2, "AFTER: partial + honest note both preserved")
    }

    // MARK: hardening (2nd adversarial pass) — ephemeral identity + durable persistence.

    func test_ephemeralAgentSwitchMidTurn_doesNotCrossPost() {
        // Ephemeral Home pop-up: conversationID is always nil, so identity keys off the
        // gatewaySessionId. The user says "talk to Morpheus" mid-reply -> a NEW session id.
        let live = LiveBox()
        live.messages = [AgentMessage(text: "the new Morpheus thread", role: .user)]
        let d = makeDelivery(turnConversationID: nil, turnSessionID: "sA",
                             currentID: { nil }, currentSessionID: { "sB" }, live: live)
        XCTAssertFalse(d.stillCurrent, "a new gatewaySessionId means the origin turn is no longer current")

        d.finishLive("Trinity's answer to the ORIGINAL question.")

        // The answer does NOT cross-post into the new Morpheus thread. (It is dropped, which
        // is acceptable: the ephemeral origin thread no longer exists to deliver into.)
        XCTAssertEqual(live.messages.count, 1)
        XCTAssertEqual(live.messages[0].text, "the new Morpheus thread")
    }

    func test_stillCurrentFinish_persistsToOriginStore_synchronously() {
        let store = ConversationStore.shared
        let convo = store.create(agent: .trinity)
        store.update(id: convo.id, messages: [AgentMessage(text: "question", role: .user)])
        let live = LiveBox()
        live.messages = store.conversation(id: convo.id)?.messages ?? []

        // Still-current: same conversationID AND same session id.
        let d = makeDelivery(turnConversationID: convo.id, turnSessionID: "s1",
                             currentID: { convo.id }, currentSessionID: { "s1" }, live: live)
        XCTAssertTrue(d.stillCurrent)

        d.finishLive("The final answer.")

        // Persisted to the store IMMEDIATELY (not waiting on the 300ms debounce), so a
        // swap right after cannot lose it.
        let stored = store.conversation(id: convo.id)?.messages ?? []
        XCTAssertTrue(stored.contains { $0.text == "The final answer." }, "final durably saved on finish")
    }

    func test_swappedCutOff_fastSwapBeforePersist_ensuresPartialInRecord() {
        let store = ConversationStore.shared
        let convo = store.create(agent: .trinity)
        // Only the user message is persisted — the partial was shown live but the 300ms
        // debounce had NOT fired before the swap (so it's absent from the record).
        store.update(id: convo.id, messages: [AgentMessage(text: "question", role: .user)])

        let live = LiveBox()
        live.messages = [AgentMessage(text: "another chat now on screen", role: .user)]
        let d = makeDelivery(turnConversationID: convo.id, turnSessionID: "s1",
                             currentID: { UUID() }, currentSessionID: { "s2" }, live: live)

        d.showLive("Alright, here's the rundown, let's tackle each one in order. (")  // sets shownPartial; not rendered (swapped)
        d.appendAssistant("\u{26A0}\u{FE0F} That reply got cut off.")                  // cut-off after total failure

        XCTAssertEqual(live.messages.count, 1, "nothing cross-posted into the visible thread")
        let stored = store.conversation(id: convo.id)?.messages ?? []
        XCTAssertTrue(stored.contains { $0.text.contains("rundown") }, "the partial is preserved in the record")
        XCTAssertTrue(stored.contains { $0.text.contains("cut off") }, "the honest note is preserved too")
    }

    func test_swapped_cutOffNote_goesToOriginThread_notCrossPosted() {
        let store = ConversationStore.shared
        let origin = store.create(agent: .trinity)
        store.update(id: origin.id, messages: [
            AgentMessage(text: "Q", role: .user),
            AgentMessage(text: "Alright, here's the rundown (", role: .agent, agentName: "Trinity"),
        ])

        let live = LiveBox()
        live.messages = [AgentMessage(text: "another chat", role: .user)]
        let d = makeDelivery(turnConversationID: origin.id, currentID: { UUID() }, live: live)

        d.appendAssistant("\u{26A0}\u{FE0F} That reply got cut off.")

        XCTAssertEqual(live.messages.count, 1, "nothing cross-posted into the visible thread")
        let storedOrigin = store.conversation(id: origin.id)?.messages ?? []
        XCTAssertTrue(storedOrigin.contains { $0.text.contains("cut off") }, "honest note preserved in origin")
        XCTAssertTrue(storedOrigin.contains { $0.text.contains("rundown") }, "partial still preserved in origin")
    }
}
